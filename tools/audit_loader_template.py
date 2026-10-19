#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
import gzip
import hashlib
import json
import re
import struct
import sys
import zlib
from pathlib import Path

KEYS=("SerialNumber","SN81","ethaddr","admin","supervisor","WpaPskKey","EngDebugFlag","once")
OFFS=(0x80000,0x140000,0x1a0000)
SIZE=0x3ffc

info_path=Path(__file__).resolve().parent.parent/"templates"/"TEMPLATE_INFO.json"
info=json.loads(info_path.read_text()) if info_path.exists() else {}

for fn in sys.argv[1:]:
    p=Path(fn)
    b=(gzip.open(p,"rb").read() if str(p).endswith(".gz") else p.read_bytes())
    if len(b)!=0x200000:
        raise SystemExit(f"{fn}: not 2MiB")

    envs=[]
    for off in OFFS:
        magic,sz,stored=struct.unpack("<III",b[off:off+12])
        data=b[off+12:off+12+SIZE]
        calc=zlib.crc32(data)&0xffffffff
        if magic!=0x75456e76 or sz!=0x4000 or stored!=calc:
            raise SystemExit(f"{fn}: invalid BOOT_MAGIC/CRC at {off:#x}")
        vals={}
        for part in data.split(b"\0"):
            if not part:
                break
            text=part.decode("latin1")
            if "=" in text:
                k,v=text.split("=",1)
                vals[k]=v
        envs.append(vals)

    if not all(envs[0].get(k)==envs[1].get(k)==envs[2].get(k) for k in KEYS):
        raise SystemExit(f"{fn}: environment copies differ")

    digest=hashlib.sha256(b).hexdigest()
    family=None
    if p.name=="loader-generic.bin.gz":
        family="generic"
    elif p.name=="loader-odido.bin.gz":
        family="odido"

    if family and family in info:
        expected=info[family]
        if digest!=expected.get("sha256"):
            raise SystemExit(f"{fn}: SHA256 mismatch: {digest} != {expected.get('sha256')}")
        placeholders=expected.get("placeholders",{})
        for k in KEYS:
            if envs[0].get(k)!=placeholders.get(k):
                raise SystemExit(
                    f"{fn}: placeholder mismatch for {k}: "
                    f"{envs[0].get(k)!r} != {placeholders.get(k)!r}"
                )
        if expected.get("old_sensitive_values_absent") is not True:
            raise SystemExit(f"{fn}: TEMPLATE_INFO does not mark anonymization verified")

        # Scan the complete 2MiB image, not only the three parsed environments.
        allowed_mac=placeholders.get("ethaddr")
        macs={m.decode("ascii").lower() for m in re.findall(
            rb"(?i)(?:[0-9a-f]{2}:){5}[0-9a-f]{2}", b
        )}
        if macs-{allowed_mac.lower()}:
            raise SystemExit(f"{fn}: unexpected MAC-like value(s): {sorted(macs)}")
        for k in KEYS:
            want=(k+"="+placeholders[k]).encode("latin1")
            prefix=(k+"=").encode("latin1")
            pos=0
            while True:
                pos=b.find(prefix,pos)
                if pos<0: break
                end=b.find(b"\0",pos)
                if end<0: end=min(len(b),pos+256)
                found=b[pos:end]
                if found!=want:
                    raise SystemExit(f"{fn}: unexpected whole-image assignment for {k}")
                pos=end+1

    print(f"{fn}: PASS sha256={digest}")
    for k in KEYS:
        print(f"  {k}={envs[0].get(k,'<missing>')}")

if len(sys.argv)==1:
    raise SystemExit(
        "usage: audit_loader_template.py "
        "templates/loader-generic.bin.gz templates/loader-odido.bin.gz"
    )
