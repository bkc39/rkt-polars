#!/usr/bin/env python3
"""Check a pair of libcompat candidates before they are committed.

    verify-candidates.py LINUX_SO DARWIN_DYLIB [--against OLD_LINUX_SO]

linux must be an x86-64 ELF needing glibc <= 2.17, darwin an arm64 Mach-O
with a code signature, and both must export the same symbols.  On success
prints one line per fact, as commit-message bullets; with --against, the
first bullet lists the exports added and removed.  Exits 1 on a failure.
The binaries are parsed directly, so no binutils or LLVM tools are needed.
"""
import argparse
import pathlib
import re
import struct
import sys
import textwrap

GLIBC_FLOOR = (2, 17)
EM_X86_64 = 62
CPU_TYPE_ARM64 = 0x0100000C
SHT_DYNSYM = 11
SHT_GNU_VERNEED = 0x6FFFFFFE
LC_SYMTAB = 0x2
LC_CODE_SIGNATURE = 0x1D
LC_BUILD_VERSION = 0x32


def cstr(data, offset):
    return data[offset : data.index(b"\0", offset)].decode()


def elf(path):
    data = pathlib.Path(path).read_bytes()
    if data[:4] != b"\x7fELF" or data[4:6] != b"\x02\x01":
        raise ValueError(f"{path}: not a 64-bit little-endian ELF")
    machine = struct.unpack_from("<H", data, 18)[0]
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum = struct.unpack_from("<HH", data, 0x3A)
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize)
                for i in range(shnum)]
    exports, needed = set(), set()
    for _, kind, _, _, offset, size, link, info, _, entsize in sections:
        strtab = sections[link][4]
        if kind == SHT_DYNSYM:
            for sym in range(offset, offset + size, entsize):
                name, st_info, _, shndx, _, _ = struct.unpack_from("<IBBHQQ", data, sym)
                if shndx != 0 and st_info >> 4 in (1, 2):
                    exports.add(cstr(data, strtab + name))
        elif kind == SHT_GNU_VERNEED:
            entry = offset
            for _ in range(info):
                _, count, _, aux, following = struct.unpack_from("<HHIII", data, entry)
                vernaux = entry + aux
                for _ in range(count):
                    _, _, _, name, step = struct.unpack_from("<IHHII", data, vernaux)
                    needed.add(cstr(data, strtab + name))
                    vernaux += step
                entry += following
    glibc = sorted(tuple(int(x) for x in m.group(1).split("."))
                   for v in needed if (m := re.fullmatch(r"GLIBC_([0-9.]+)", v)))
    return {"machine": machine, "exports": exports, "glibc": glibc[-1] if glibc else None}


def macho(path):
    data = pathlib.Path(path).read_bytes()
    magic, cputype, _, _, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != 0xFEEDFACF:
        raise ValueError(f"{path}: not a thin 64-bit Mach-O")
    exports, signed, minos = set(), False, None
    command = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, command)
        if cmd == LC_CODE_SIGNATURE:
            signed = True
        elif cmd == LC_BUILD_VERSION:
            v = struct.unpack_from("<I", data, command + 12)[0]
            minos = f"{v >> 16}.{(v >> 8) & 0xFF}"
        elif cmd == LC_SYMTAB:
            symoff, nsyms, stroff, _ = struct.unpack_from("<IIII", data, command + 8)
            for i in range(nsyms):
                name, n_type, _, _, _ = struct.unpack_from("<IBBHQ", data, symoff + 16 * i)
                if n_type & 0xE0 == 0 and n_type & 0x01 and n_type & 0x0E == 0x0E:
                    exports.add(cstr(data, stroff + name).removeprefix("_"))
        command += size
    return {"cputype": cputype, "exports": exports, "signed": signed, "minos": minos}


def listing(names):
    return ", ".join(f"`{n}`" for n in sorted(names))


def bullet(text):
    return textwrap.fill(text, width=72, initial_indent="- ", subsequent_indent="  ")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("linux")
    parser.add_argument("darwin")
    parser.add_argument("--against", metavar="OLD_LINUX_SO")
    args = parser.parse_args()

    try:
        linux, darwin = elf(args.linux), macho(args.darwin)
    except ValueError as e:
        sys.exit(f"verify-candidates: {e}")
    errors = []
    if linux["machine"] != EM_X86_64:
        errors.append(f"linux: e_machine {linux['machine']}, not x86-64")
    floor = ".".join(map(str, linux["glibc"] or ()))
    if linux["glibc"] and linux["glibc"] > GLIBC_FLOOR:
        errors.append(f"linux: needs GLIBC_{floor}; the catalog host needs <= 2.17")
    if darwin["cputype"] != CPU_TYPE_ARM64:
        errors.append(f"darwin: cputype {darwin['cputype']:#x}, not arm64")
    if not darwin["signed"]:
        errors.append("darwin: no code signature; Apple Silicon kills an unsigned dylib")
    only_linux = linux["exports"] - darwin["exports"]
    only_darwin = darwin["exports"] - linux["exports"]
    if only_linux or only_darwin:
        errors.append("the two candidates export different symbols: "
                      f"only linux {listing(only_linux) or 'none'}; "
                      f"only darwin {listing(only_darwin) or 'none'}")
    for error in errors:
        print(f"verify-candidates: {error}", file=sys.stderr)
    if errors:
        sys.exit(1)

    exports = f"Exports: {len(linux['exports'])} on both platforms"
    if args.against:
        before = elf(args.against)["exports"]
        changes = []
        if added := linux["exports"] - before:
            changes.append(f"added {listing(added)}")
        if removed := before - linux["exports"]:
            changes.append(f"removed {listing(removed)}")
        if changes:
            exports += f" ({len(before)} before): " + "; ".join(changes)
        else:
            exports += ", unchanged"
    print(bullet(exports + "."))
    print(bullet(f"linux: x86-64 ELF, glibc floor GLIBC_{floor or 'none'} (<= 2.17)."))
    print(bullet(f"darwin: arm64 Mach-O, minos {darwin['minos'] or '?'}, "
                 "code signature present."))


if __name__ == "__main__":
    main()
