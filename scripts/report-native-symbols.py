"""Collect static ELF evidence from a Docker export without extracting/executing it."""

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile


SYMBOL_GROUPS = {
    "xml_hash": {"XML_SetHashSalt", "XML_SetHashSalt16Bytes",
                 "PyExpat_XML_SetHashSalt", "PyExpat_XML_SetHashSalt16Bytes"},
    "legacy_dns": {"ns_printrr", "ns_printrrf", "fp_nquery", "__ns_printrr", "__ns_printrrf", "__fp_nquery"},
    "acl": {"acl_get_file", "acl_set_file", "acl_delete_def_file", "acl_extended_file", "acl_extended_file_nofollow"},
    "gzip_write": {"gzwrite", "gzprintf", "gzvprintf", "gzputs", "gzputc", "gzflush", "gzclose", "gzclose_w", "gz_vacate"},
    "dynamic_lookup": {"dlopen", "dlsym", "dlvsym", "dlmopen", "__libc_dlopen_mode"},
}
WATCHED = frozenset().union(*SYMBOL_GROUPS.values())
MAX_ELF_BYTES = 256 * 1024 * 1024
MAX_MEMBERS = 200_000
COMPONENT_NAMES = ("infocmp", "nsenter", "getfacl", "setfacl", "chacl", "perl_archive_tar")
LIMITATIONS = [
    "Static symbol evidence only: imports are possible calls, not proof of exploitation.",
    "No import is NOT proof of absence: static/inlined/hidden code and runtime symbol lookup can bypass this inventory.",
    "Exports identify providers, not callers; stripped internal functions may be absent from symbol tables.",
    "XML hash symbols do not prove the selected runtime branch; ElementTree can call through the pyexpat C API.",
    "All regular ELF files are inspected, including root-only tools; symlink/hardlink aliases are counted but not resolved.",
    "This does not trace requests, resolve loader search paths, test host privileges, approve CVEs, or alter the scanner gate.",
    "Component paths use known filenames in the effective filesystem, not proof against renamed copies or host tools.",
]


def canonical_name(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or not path.parts or any(ord(c) < 32 for c in name):
        raise ValueError("Invalid archive path")
    return "/" + path.as_posix()


def symbol_evidence(sections):
    imports, exports = set(), set()
    tables = 0
    for section in sections:
        if section["sh_type"] not in ("SHT_SYMTAB", "SHT_DYNSYM"):
            continue
        tables += 1
        for symbol in section.iter_symbols():
            name = symbol.name.split("@", 1)[0]
            if name in WATCHED:
                target = imports if symbol["st_shndx"] == "SHN_UNDEF" else exports
                target.add(name)
    return {"symbol_tables": tables, "imports": sorted(imports), "exports": sorted(exports)}


def inspect_elf(data):
    from elftools.elf.elffile import ELFFile

    elf = ELFFile(io.BytesIO(data))
    needed = set()
    for segment in elf.iter_segments():
        if segment["p_type"] == "PT_DYNAMIC":
            for tag in segment.iter_tags():
                if tag.entry.d_tag == "DT_NEEDED":
                    needed.add(tag.needed)
    return {
        "machine": elf["e_machine"],
        "bits": elf.elfclass,
        "needed": sorted(needed),
        **symbol_evidence(elf.iter_sections()),
    }


def collect(archive, image_id):
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
        raise ValueError("Immutable image identity required")
    records, names = [], set()
    components = {name: [] for name in COMPONENT_NAMES}
    members = links = regular = 0
    for member in archive:
        members += 1
        if members > MAX_MEMBERS:
            raise ValueError("Archive member limit exceeded")
        name = canonical_name(member.name)
        if name in names:
            raise ValueError("Duplicate archive path")
        names.add(name)
        if not member.isdir():
            basename = PurePosixPath(name).name
            if basename in components and basename != "perl_archive_tar":
                components[basename].append(name)
            if name.endswith("/Archive/Tar.pm"):
                components["perl_archive_tar"].append(name)
        if member.issym() or member.islnk():
            links += 1
        if not member.isfile():
            continue
        regular += 1
        with archive.extractfile(member) as stream:
            if stream.read(4) != b"\x7fELF":
                continue
            if member.size > MAX_ELF_BYTES:
                raise ValueError("ELF size limit exceeded")
            stream.seek(0)
            data = stream.read(MAX_ELF_BYTES + 1)
        if len(data) != member.size:
            raise ValueError("Incomplete ELF data")
        records.append({
            "path": name,
            "sha256": hashlib.sha256(data).hexdigest(),
            "size": member.size,
            "mode": oct(member.mode),
            "uid": member.uid,
            "gid": member.gid,
            **inspect_elf(data),
        })
    if not records:
        raise ValueError("No ELF evidence found")
    return {
        "schema_version": 1,
        "image_id": image_id,
        "status": "evidence_only_not_security_approval",
        "counts": {"archive_members": members, "regular_files": regular, "link_aliases_not_resolved": links, "elf_files": len(records)},
        "symbol_groups": {key: sorted(value) for key, value in SYMBOL_GROUPS.items()},
        "component_inventory": {key: sorted(paths) for key, paths in components.items()},
        "limitations": LIMITATIONS,
        "files": sorted(records, key=lambda row: row["path"]),
    }


def summary(report):
    lines = ["## Native symbol evidence (not approval)", "", report["image_id"], "",
             f"ELF files: {report['counts']['elf_files']}. Full hashes, providers and imports are in the native-symbol-evidence artifact.", ""]
    for group, symbols in SYMBOL_GROUPS.items():
        callers = [row["path"] for row in report["files"] if symbols.intersection(row["imports"])]
        lines.append(f"{group}: {len(callers)} files with matching imports.")
    for component, paths in report.get("component_inventory", {}).items():
        lines.append(f"Component {component}: {len(paths)} matching paths in the effective filesystem.")
    lines.extend(["", *LIMITATIONS, ""])
    return "\n".join(lines)


def annotations(report):
    if "component_inventory" in report:
        payload = {"image_id": report["image_id"], "scope": "known_names_in_effective_filesystem",
                   "components": {name: {"count": len(paths), "paths": paths[:12]}
                                  for name, paths in report["component_inventory"].items()}}
        message = json.dumps(payload, ensure_ascii=True).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::notice title=Component inventory (not approval)::{message}")
    for group, symbols in SYMBOL_GROUPS.items():
        callers = [{"path": row["path"], "imports": sorted(symbols.intersection(row["imports"]))}
                   for row in report["files"] if symbols.intersection(row["imports"])]
        callers.sort(key=lambda row: (not row["path"].startswith(("/usr/local/", "/app/")), row["path"]))
        # Keep public annotations bounded; the artifact retains every file.
        payload = {"image_id": report["image_id"], "elf_files": report["counts"]["elf_files"],
                   "group": group, "caller_files": len(callers),
                   "callers": callers[:12], "omitted_from_annotation": max(0, len(callers) - 12)}
        message = json.dumps(payload, ensure_ascii=True).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::notice title=Native imports {group} (not approval)::{message}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--image-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--github-annotation", action="store_true")
    args = parser.parse_args(argv)
    try:
        # Docker export is an uncompressed root filesystem tar, not docker save.
        with tarfile.open(args.archive, "r:") as archive:
            report = collect(archive, args.image_id)
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        rendered = summary(report)
        if args.summary:
            with args.summary.open("a", encoding="utf-8") as stream:
                stream.write(rendered)
        print(rendered)
        if args.github_annotation:
            annotations(report)
        return 0
    except Exception:
        print("Native evidence incomplete; no security conclusion. See tool validation, not production credentials.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
