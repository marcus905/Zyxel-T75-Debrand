#!/usr/bin/env python3
"""
Normalize a Zyxel EX7501-B0 conversion source into T75 Source Pack v1.

Accepted inputs:
  * vendor .bin
  * vendor .zip containing a .bin
  * converter backup directory (backup.conf/sourcepack.conf)
  * ECC-corrected logical 512MiB mtd0 dump (loader + image UBI)
  * ECC-corrected logical image/mtd2 UBI dump (firmware payloads only)

Output is a directory with sourcepack.conf + logical payload files.\nDo not use dumps captured with nanddump -n: ECC-bypassed bit errors cannot be\nrepaired from a data-only dump and may silently corrupt extracted payloads.
A public vendor update intentionally has no loader; the USB converter then uses
its known-good family loader template.
"""
from __future__ import annotations
import argparse, struct, hashlib, shutil, zipfile, re, json
from pathlib import Path
from collections import defaultdict

PEB=0x40000

ENV_DATA_SIZE=0x3ffc
ENV_OFFSETS=(0x80000,0x140000,0x1a0000)
ANON_LOADER_ENV={
    "SerialNumber":"T75_TEMPLATE",
    "SN81":"T75_TEMPLATE",
    "ethaddr":"02:00:00:00:00:00",
    "admin":"T75_TEMPLATE",
    "supervisor":"T75_TEMPLATE",
    "WpaPskKey":"T75_TEMPLATE",
    "EngDebugFlag":"00",
    "once":"true",
}

def anonymize_loader(blob: bytes) -> bytes:
    """Convert an exact device loader into a reusable identity-free family template."""
    if len(blob)!=0x200000:
        raise SystemExit("loader to anonymize is not exactly 2MiB")
    data=blob[ENV_OFFSETS[0]+12:ENV_OFFSETS[0]+12+ENV_DATA_SIZE]
    lines=[]
    for part in data.split(b"\0"):
        if not part: break
        lines.append(part.decode("latin1"))
    keys={x.split("=",1)[0] for x in lines if "=" in x}
    missing=[k for k in ANON_LOADER_ENV if k not in keys]
    if missing:
        raise SystemExit("loader environment lacks expected keys: "+",".join(missing))
    new=[]
    for line in lines:
        if "=" in line:
            k,v=line.split("=",1)
            if k in ANON_LOADER_ENV: v=ANON_LOADER_ENV[k]
            new.append(k+"="+v)
        else:
            new.append(line)
    payload=b"\0".join(x.encode("latin1") for x in new)+b"\0\0\0"
    if len(payload)>ENV_DATA_SIZE:
        raise SystemExit("anonymized loader environment is too large")
    payload += b"\xff"*(ENV_DATA_SIZE-len(payload))
    crc=(__import__("zlib").crc32(payload)&0xffffffff)
    rec=struct.pack("<II",0x75456e76,0x4000)+struct.pack("<I",crc)+payload+b"\xff"*4
    out=bytearray(blob)
    for off in ENV_OFFSETS:
        out[off:off+len(rec)]=rec
    return bytes(out)


def sha(b): return hashlib.sha256(b).hexdigest()
def shafile(p):
    h=hashlib.sha256()
    with p.open("rb") as f:
        for c in iter(lambda:f.read(1<<20),b""): h.update(c)
    return h.hexdigest()

def u32(b,o): return struct.unpack(">I",b[o:o+4])[0]
def cstr(b,o):
    e=b.find(b"\0",o)
    return b[o:e].decode("latin1")

def parse_dtb_images(blob):
    if blob[:4] != b"\xd0\r\xfe\xed": raise ValueError("not a FIT/DTB")
    total,so,st = u32(blob,4),u32(blob,8),u32(blob,12)
    d=blob[:total]; p=so; stack=[]; props={}
    while True:
        tok=u32(d,p); p+=4
        if tok==1:
            name=cstr(d,p); p += len(name.encode("latin1"))+1
            p=(p+3)&~3; stack.append(name)
        elif tok==2: stack.pop()
        elif tok==3:
            ln,no=u32(d,p),u32(d,p+4); p+=8
            prop=cstr(d,st+no); path="/"+"/".join(x for x in stack if x)
            val=d[p:p+ln]
            if path.startswith("/images/"): props.setdefault(path,{})[prop]=val
            p=(p+ln+3)&~3
        elif tok==4: pass
        elif tok==9: break
        else: raise ValueError(f"bad FDT token {tok}")
    out={}
    for path,pr in props.items():
        desc=(pr.get("description",b"").split(b"\0")[0]).decode("latin1","ignore")
        if desc in {"bootfs","rootfs","zydefault","zyfwinfo","zyfwsign"}:
            pos=struct.unpack(">I",pr["data-position"][:4])[0]
            size=struct.unpack(">I",pr["data-size"][:4])[0]
            # Find child hash node separately.
            hv=None
            for hp,hppr in props.items():
                if hp.startswith(path+"/hash-") and len(hppr.get("value",b""))==32:
                    hv=hppr["value"].hex()
            out[desc]=(pos,size,hv)
    return out

def vendor_bin(inp,out):
    b=inp.read_bytes()
    items=parse_dtb_images(b[:65536])
    for req in ("bootfs","rootfs","zydefault","zyfwinfo"):
        if req not in items: raise SystemExit(f"vendor FIT lacks {req}")
    meta={}
    for name,(pos,size,want) in items.items():
        data=b[pos:pos+size]
        if len(data)!=size: raise SystemExit(f"short {name}")
        got=sha(data)
        if want and got!=want: raise SystemExit(f"{name} FIT SHA mismatch")
        (out/f"{name}.bin").write_bytes(data)
        meta[name]=(size,got)
    fam="odido" if "zyfwsign" in items else ("generic" if b"ACHN" in (out/"zyfwinfo.bin").read_bytes() else "odido" if b"ACDA" in (out/"zyfwinfo.bin").read_bytes() else "unknown")
    return fam,False,meta

def raw_ubi(inp,out,family_override=None):
    raw=inp.read_bytes()
    off=0
    loader=None
    if raw[:4]!=b"UBI#" and len(raw)>0x200004 and raw[0x200000:0x200004]==b"UBI#":
        loader=raw[:0x200000]; off=0x200000
    elif raw[:4]!=b"UBI#":
        raise SystemExit("raw input has no UBI at 0 or 0x200000")
    img=raw[off:]
    vols=defaultdict(dict)
    for pebn in range(len(img)//PEB):
        po=pebn*PEB; ec=img[po:po+64]
        if ec[:4]!=b"UBI#": continue
        vo,do=struct.unpack(">II",ec[16:24]); vh=img[po+vo:po+vo+64]
        if vh[:4]!=b"UBI!": continue
        vt=vh[5]; vid,ln=struct.unpack(">II",vh[8:16]); ds=struct.unpack(">I",vh[20:24])[0]; sq=struct.unpack(">Q",vh[40:48])[0]
        rec=(sq,pebn,vt,do,ds)
        if ln not in vols[vid] or sq>vols[vid][ln][0]: vols[vid][ln]=rec

    # Determine a populated slot, preferring metadata COMMITTED when easily available.
    candidates=[]
    for slot, ids in [(1,(3,4,16,18,20)),(2,(5,6,17,19,21))]:
        if all(x in vols for x in ids[:4]): candidates.append((slot,ids))
    if not candidates: raise SystemExit("raw UBI contains no complete firmware slot")
    if len(candidates)>1: raise SystemExit("raw UBI contains two complete firmware slots; use a vendor update or converter backup directory instead")
    slot,ids=candidates[0]
    names=["bootfs","rootfs","zydefault","zyfwinfo","zyfwsign"]
    meta={}
    for name,vid in zip(names,ids):
        if vid not in vols:
            continue
        m=vols[vid]; maxln=max(m); vt=next(iter(m.values()))[2]
        chunks=[]
        lebsize=None
        for ln in range(maxln+1):
            if ln not in m:
                if lebsize is None:
                    anyr=next(iter(m.values())); lebsize=PEB-anyr[3]
                chunks.append(b"\xff"*lebsize); continue
            sq,pn,vt2,do,ds=m[ln]; leb=img[pn*PEB+do:(pn+1)*PEB]; lebsize=len(leb)
            chunks.append(leb[:ds] if vt2==2 else leb)
        data=b"".join(chunks)
        (out/f"{name}.bin").write_bytes(data); meta[name]=(len(data),sha(data))
    if loader:
        (out/"loader.bin").write_bytes(anonymize_loader(loader))
    fam=family_override or ("odido" if "zyfwsign" in meta else "generic")
    return fam, bool(loader), meta

def write_conf(out,fam,loader,meta,origin):
    lines=[
      "T75_SOURCEPACK_VERSION=1",
      f"FAMILY='{fam}'",
      f"ORIGIN='{origin}'",
      f"LOADER_PRESENT={1 if loader else 0}",
    ]
    if loader:
        lines += ["LOADER_FILE='loader.bin'", f"LOADER_SIZE={(out/'loader.bin').stat().st_size}", f"LOADER_SHA256='{shafile(out/'loader.bin')}'"]
    for name in ("bootfs","rootfs","zydefault","zyfwinfo","zyfwsign"):
        if name in meta:
            u=name.upper()
            lines += [f"{u}_FILE='{name}.bin'", f"{u}_SIZE={meta[name][0]}", f"{u}_SHA256='{meta[name][1]}'"]
    lines.append(f"ZYFWSIGN_PRESENT={1 if 'zyfwsign' in meta else 0}")
    (out/"sourcepack.conf").write_text("\n".join(lines)+"\n")
    (out/"manifest.json").write_text(json.dumps({
        "format":"T75-source-pack-v1","family":fam,"origin":origin,
        "loader_present":loader,
        "files":{n:{"size":sz,"sha256":h} for n,(sz,h) in meta.items()}
    },indent=2)+"\n")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("source",type=Path)
    ap.add_argument("out",type=Path)
    ap.add_argument("--family",choices=["generic","odido"])
    a=ap.parse_args()
    if a.out.exists(): shutil.rmtree(a.out)
    a.out.mkdir(parents=True)

    src=a.source
    if src.is_dir():
        conf=src/"sourcepack.conf"
        if conf.exists():
            for p in src.iterdir():
                if p.is_file() and p.name not in {".",".."}: shutil.copy2(p,a.out/p.name)
            print(f"Copied existing source pack to {a.out}"); return
        bc=src/"backup.conf"
        if not bc.exists(): raise SystemExit("directory is neither source pack nor converter backup")
        text=bc.read_text()
        fam=a.family or re.search(r"^FAMILY=(.*)$",text,re.M).group(1).strip("'\"")
        meta={}
        for n in ("bootfs","rootfs","zydefault","zyfwinfo","zyfwsign"):
            f=src/f"{n}.bin"
            if f.exists():
                shutil.copy2(f,a.out/f.name); meta[n]=(f.stat().st_size,shafile(f))
        loader=(src/"loader.bin").exists()
        if loader: (a.out/"loader.bin").write_bytes(anonymize_loader((src/"loader.bin").read_bytes()))
        write_conf(a.out,fam,loader,meta,"device-backup"); return

    work=src
    origin="vendor-update"
    if src.suffix.lower()==".zip":
        with zipfile.ZipFile(src) as z:
            members=[n for n in z.namelist() if n.lower().endswith(".bin")]
            if not members: raise SystemExit("zip contains no .bin")
            b=z.read(members[0]); work=a.out/".vendor.bin"; work.write_bytes(b)
    try:
        head=work.read_bytes()[:4]
        size=work.stat().st_size
        if head==b"\xd0\r\xfe\xed":
            fam,loader,meta=vendor_bin(work,a.out)
        elif head==b"UBI#" or (size>=0x200004 and work.open("rb").read(0x200004)[0x200000:0x200004]==b"UBI#"):
            origin="raw-nand"
            fam,loader,meta=raw_ubi(work,a.out,a.family)
        else:
            raise SystemExit("unrecognized input format")
        if a.family: fam=a.family
        if fam=="unknown": raise SystemExit("cannot identify family; use --family")
        write_conf(a.out,fam,loader,meta,origin)
    finally:
        v=a.out/".vendor.bin"
        if v.exists(): v.unlink()
    print((a.out/"sourcepack.conf").read_text())

if __name__=="__main__": main()
