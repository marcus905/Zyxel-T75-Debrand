#!/usr/bin/env python3
import struct, sys, zlib, hashlib
from pathlib import Path
import gzip
KEYS=("SerialNumber","SN81","ethaddr","admin","supervisor","WpaPskKey","EngDebugFlag","once")
OFFS=(0x80000,0x140000,0x1a0000)
SIZE=0x3ffc
for fn in sys.argv[1:]:
    p=Path(fn); b=(gzip.open(p,"rb").read() if str(p).endswith(".gz") else p.read_bytes())
    if len(b)!=0x200000: raise SystemExit(f"{fn}: not 2MiB")
    envs=[]
    for off in OFFS:
        magic,sz,stored=struct.unpack("<III",b[off:off+12])
        data=b[off+12:off+12+SIZE]
        calc=zlib.crc32(data)&0xffffffff
        if magic!=0x75456e76 or sz!=0x4000 or stored!=calc:
            raise SystemExit(f"{fn}: invalid BOOT_MAGIC/CRC at {off:#x}")
        vals={}
        for part in data.split(b"\0"):
            if not part: break
            text=part.decode("latin1")
            if "=" in text:
                k,v=text.split("=",1); vals[k]=v
        envs.append(vals)
    if not all(envs[0].get(k)==envs[1].get(k)==envs[2].get(k) for k in KEYS):
        raise SystemExit(f"{fn}: environment copies differ")
    print(f"{fn}: sha256={hashlib.sha256(b).hexdigest()}")
    for k in KEYS:
        print(f"  {k}={envs[0].get(k,'<missing>')}")
