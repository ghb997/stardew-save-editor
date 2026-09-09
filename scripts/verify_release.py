#!/usr/bin/env python3
"""Offline, standard-library-only release checks. This does not compile Swift or run XCTest.

Run from any directory: python scripts/verify_release.py
Exit status 0 means the listed static checks passed; 1 means a check failed.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zlib


class OpenStepParser:
    """Parse the dictionaries/arrays/strings used by an ASCII .pbxproj file.

    Comments are tokenized, not removed with a regex over quoted strings.
    Duplicate keys, unterminated values and trailing input are errors.
    """
    TOKEN = re.compile(
        r'(?P<space>\s+)|(?P<comment>/\*.*?\*/|//[^\r\n]*)|'
        r'(?P<string>"(?:\\.|[^"\\])*")|(?P<punct>[{}()=;,])|'
        r'(?P<atom>(?:(?!/\*|//)[^\s{}()=;,"])+)', re.S
    )

    def __init__(self, text: str):
        self.tokens = []
        position = 0
        while position < len(text):
            match = self.TOKEN.match(text, position)
            if not match:
                raise ValueError(f"Invalid OpenStep token near offset {position}")
            if match.lastgroup not in ("space", "comment"):
                token = match.group()
                if match.lastgroup == "string":
                    token = re.sub(r'\\(["\\])', r'\1', token[1:-1])
                    self.tokens.append(("scalar", token))
                elif match.lastgroup == "atom":
                    self.tokens.append(("scalar", token))
                else:
                    self.tokens.append((token, token))
            position = match.end()
        self.position = 0

    def take(self, kind=None):
        if self.position >= len(self.tokens):
            raise ValueError("Unexpected end of OpenStep document")
        token = self.tokens[self.position]
        if kind is not None and token[0] != kind:
            raise ValueError(f"Expected {kind!r}, found {token!r}")
        self.position += 1
        return token[1]

    def peek(self):
        return self.tokens[self.position][0] if self.position < len(self.tokens) else None

    def value(self):
        if self.peek() == "{":
            self.take("{")
            result = {}
            while self.peek() != "}":
                key = self.take("scalar")
                if key in result:
                    raise ValueError(f"Duplicate OpenStep dictionary key: {key}")
                self.take("=")
                result[key] = self.value()
                self.take(";")
            self.take("}")
            return result
        if self.peek() == "(":
            self.take("(")
            result = []
            while self.peek() != ")":
                result.append(self.value())
                if self.peek() == ",":
                    self.take(",")
                elif self.peek() != ")":
                    raise ValueError("Missing comma in OpenStep array")
            self.take(")")
            return result
        return self.take("scalar")

    def parse(self):
        result = self.value()
        if self.position != len(self.tokens):
            raise ValueError("Trailing OpenStep input")
        return result


def unique_json_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path):
    def invalid_constant(value):
        raise ValueError(f"Nonstandard JSON constant: {value}")
    return json.loads(path.read_text(encoding="utf-8-sig"),
                      object_pairs_hook=unique_json_pairs, parse_constant=invalid_constant)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_dimensions(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Invalid PNG signature")
    position, dimensions, saw_data = 8, None, False
    while position < len(data):
        if position + 12 > len(data):
            raise ValueError("Truncated PNG chunk header")
        length = struct.unpack_from(">I", data, position)[0]
        end = position + 12 + length
        if end > len(data):
            raise ValueError("Truncated PNG chunk data")
        kind = data[position + 4:position + 8]
        payload = data[position + 8:position + 8 + length]
        expected_crc = struct.unpack_from(">I", data, position + 8 + length)[0]
        if zlib.crc32(kind + payload) & 0xFFFFFFFF != expected_crc:
            raise ValueError(f"PNG CRC mismatch in {kind!r}")
        if position == 8:
            if kind != b"IHDR" or length != 13:
                raise ValueError("PNG must begin with a 13-byte IHDR")
            dimensions = struct.unpack_from(">II", payload)
            if not all(dimensions):
                raise ValueError("PNG has zero width/height")
        elif kind == b"IHDR":
            raise ValueError("Duplicate PNG IHDR")
        if kind == b"IDAT":
            saw_data = True
        if kind == b"IEND":
            if length != 0 or not saw_data or end != len(data):
                raise ValueError("Invalid PNG ending")
            return dimensions
        position = end
    raise ValueError("Missing PNG IEND")


def jpeg_dimensions(data):
    if data[:2] != b"\xff\xd8":
        raise ValueError("Invalid JPEG signature")
    position = 2
    frame_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
    while position < len(data):
        if data[position] != 0xFF:
            raise ValueError("Expected JPEG marker")
        while position < len(data) and data[position] == 0xFF:
            position += 1
        if position >= len(data):
            break
        marker = data[position]
        position += 1
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        if position + 2 > len(data):
            break
        length = struct.unpack_from(">H", data, position)[0]
        if length < 2 or position + length > len(data):
            raise ValueError("Truncated JPEG segment")
        if marker in frame_markers:
            if length < 7:
                raise ValueError("Truncated JPEG frame")
            height, width = struct.unpack_from(">HH", data, position + 3)
            return width, height
        if marker == 0xDA:
            break
        position += length
    raise ValueError("JPEG dimensions not found")


class Validator:
    def __init__(self, root, expected_version, expected_build, output):
        self.root = root.resolve()
        self.expected_version = expected_version
        self.expected_build = expected_build
        self.output = output.resolve()
        self.checks, self.facts = [], {}
        self.objects, self.document = {}, {}

    def record(self, name, passed, detail):
        self.checks.append({"check": name, "status": "passed" if passed else "failed", "detail": detail})

    def relative(self, path):
        return path.resolve().relative_to(self.root).as_posix()

    def project(self):
        project_path = self.root / "PelicanSaveEditor.xcodeproj/project.pbxproj"
        self.document = OpenStepParser(project_path.read_text(encoding="utf-8-sig")).parse()
        self.objects = objects = self.document["objects"]
        self.record("pbxproj_structure", True, {"objects": len(objects), "sha256": sha256(project_path), "duplicate_object_keys": 0})
        parents = defaultdict(list)
        for identifier, obj in objects.items():
            if obj.get("isa") == "PBXGroup":
                children = obj.get("children", [])
                if len(children) != len(set(children)):
                    self.record("unique_group_children", False, identifier)
                for child in children:
                    if child not in objects:
                        self.record("group_child_reference", False, {"group": identifier, "missing": child})
                    parents[child].append(identifier)

        def resolve(identifier, visiting=()):
            if identifier in visiting:
                raise ValueError(f"Cycle in Xcode group graph: {identifier}")
            obj = objects[identifier]
            tree, path = obj.get("sourceTree", "<group>"), obj.get("path", "")
            if tree in ("BUILT_PRODUCTS_DIR", "SDKROOT", "DEVELOPER_DIR"):
                return None
            if tree == "SOURCE_ROOT":
                return (self.root / path).resolve()
            if tree != "<group>":
                raise ValueError(f"Unsupported sourceTree for offline validation: {tree}")
            if len(parents[identifier]) > 1:
                raise ValueError(f"Ambiguous group parents for {identifier}")
            base = resolve(parents[identifier][0], visiting + (identifier,)) if parents[identifier] else self.root
            return (base / path).resolve() if base is not None else None

        resolved, reference_errors, virtual = {}, [], []
        for identifier, obj in objects.items():
            if obj.get("isa") != "PBXFileReference":
                continue
            path = resolve(identifier)
            if path is None:
                virtual.append(obj.get("path"))
                continue
            if not path.is_relative_to(self.root):
                reference_errors.append(f"Reference escapes release root: {path}")
            elif not path.exists():
                reference_errors.append(f"Missing file reference: {self.relative(path)}")
            resolved[identifier] = path
        self.record("xcode_file_references_exist", not reference_errors,
                    {"checked": len(resolved), "build_products_or_sdk_skipped": virtual, "errors": reference_errors})

        memberships, target_sources = defaultdict(list), {}
        build_errors = []
        for identifier, target in objects.items():
            if target.get("isa") != "PBXNativeTarget":
                continue
            name = target["name"]
            target_sources[name] = []
            for phase_id in target.get("buildPhases", []):
                if phase_id not in objects:
                    build_errors.append(f"Missing build phase: {phase_id}")
                    continue
                phase = objects[phase_id]
                build_ids = phase.get("files", [])
                if len(build_ids) != len(set(build_ids)):
                    build_errors.append(f"Duplicate build entry in {name}/{phase_id}")
                for build_id in build_ids:
                    build = objects.get(build_id, {})
                    reference = build.get("fileRef")
                    if build.get("isa") != "PBXBuildFile" or reference not in objects:
                        build_errors.append(f"Invalid build file/reference: {build_id}")
                        continue
                    path = resolved.get(reference)
                    if phase.get("isa") == "PBXSourcesBuildPhase":
                        if path is None or path.suffix != ".swift":
                            build_errors.append(f"Unexpected source entry: {build_id}")
                            continue
                        relative = self.relative(path)
                        memberships[relative].append(name)
                        target_sources[name].append(relative)
        disk_sources = sorted(self.root.glob("PelicanSaveEditor/**/*.swift")) + sorted(self.root.glob("PelicanSaveEditorTests/**/*.swift"))
        disk_names = {self.relative(path) for path in disk_sources}
        for path in sorted(disk_names):
            expected = "PelicanSaveEditorTests" if path.startswith("PelicanSaveEditorTests/") else "PelicanSaveEditor"
            if memberships.get(path) != [expected]:
                build_errors.append(f"{path}: expected exactly [{expected}], got {memberships.get(path, [])}")
            references = [identifier for identifier, value in resolved.items() if value == self.root / path]
            if len(references) != 1:
                build_errors.append(f"{path}: expected one file reference, found {len(references)}")
        for path in memberships.keys() - disk_names:
            build_errors.append(f"Registered source missing on disk: {path}")
        self.record("swift_sources_registered_once_in_correct_target", not build_errors,
                    {"target_source_counts": {key: len(value) for key, value in target_sources.items()}, "errors": build_errors})
        self.facts["target_sources"] = target_sources
        self.facts["swift_source_sha256"] = {self.relative(path): sha256(path) for path in disk_sources}
        test_counts = {}
        for path in disk_sources:
            if path.parent.name == "PelicanSaveEditorTests":
                test_counts[self.relative(path)] = len(re.findall(r"(?m)^\s*func\s+test\w*\s*\(", path.read_text(encoding="utf-8-sig")))
        self.facts["source_counts"] = {"swift_files": len(disk_sources), "test_files": len(test_counts),
                                       "declared_test_methods": sum(test_counts.values()), "test_methods_by_file": test_counts}

    def documents(self):
        errors, counts = [], Counter()
        for path in sorted(self.root.rglob("*")):
            if not path.is_file() or path.resolve() == self.output or any(part in (".git", "DerivedData", "build", "artifacts", "__pycache__") for part in path.parts):
                continue
            try:
                if path.suffix == ".json":
                    read_json(path)
                    counts["json"] += 1
                elif path.suffix in (".plist", ".xcprivacy"):
                    plistlib.loads(path.read_bytes())
                    counts["plist_and_privacy_manifest"] += 1
                elif path.suffix in (".xcscheme", ".xcworkspacedata"):
                    document = ET.parse(path)
                    counts["xcode_xml"] += 1
                    for reference in document.iter("BuildableReference"):
                        identifier = reference.attrib["BlueprintIdentifier"]
                        target = self.objects.get(identifier, {})
                        if target.get("isa") != "PBXNativeTarget" or target.get("name") != reference.attrib["BlueprintName"]:
                            raise ValueError(f"Scheme refers to missing/wrong target {identifier}")
            except Exception as error:
                errors.append(f"{self.relative(path)}: {error}")
        self.record("json_plist_and_xcode_xml_valid", not errors, {"counts": dict(counts), "errors": errors})

    def assets(self):
        manifest = read_json(self.root / "GAME_ASSETS_MANIFEST.json")
        errors, details, seen_names, seen_files = [], [], set(), set()
        for entry in manifest:
            try:
                name, filename = entry["asset"], entry["file"]
                if name in seen_names or filename in seen_files:
                    raise ValueError("Duplicate asset or local path")
                seen_names.add(name)
                seen_files.add(filename)
                path = (self.root / filename).resolve()
                if not path.is_relative_to(self.root):
                    raise ValueError("Asset path escapes release root")
                actual_hash = sha256(path)
                if actual_hash != entry["sha256"].lower():
                    raise ValueError("SHA-256 mismatch")
                data = path.read_bytes()
                size = png_dimensions(data) if path.suffix.lower() == ".png" else jpeg_dimensions(data)
                if size != (entry["width"], entry["height"]):
                    raise ValueError(f"Dimension mismatch: actual {size}")
                if entry.get("source_kind") == "user_provided_archive":
                    if not entry.get("source_archive") or not re.fullmatch(r"[0-9a-fA-F]{64}", entry.get("source_archive_sha256", "")):
                        raise ValueError("Missing user archive name or SHA-256 provenance")
                    archive_entry = entry.get("source_archive_entry", "")
                    archive_path = Path(archive_entry)
                    if not archive_entry or archive_path.is_absolute() or ".." in archive_path.parts or "\\" in archive_entry:
                        raise ValueError("Unsafe or missing user archive entry provenance")
                elif not re.match(r"https://", entry.get("source_url", "")):
                    raise ValueError("Missing HTTPS source URL")
                contents = read_json(path.parent / "Contents.json")
                filenames = [item.get("filename") for item in contents.get("images", []) if item.get("filename")]
                if filenames.count(path.name) != 1:
                    raise ValueError("Image missing or duplicated in asset catalog Contents.json")
                if path.parent.name not in (f"{name}.imageset", f"{name}.appiconset"):
                    raise ValueError("Asset name does not match catalog directory")
                details.append({"asset": name, "file": filename, "width": size[0], "height": size[1], "sha256": actual_hash})
            except Exception as error:
                errors.append(f"{entry.get('asset', '<unnamed>')}: {error}")
        bitmap_paths = {self.relative(path) for path in (self.root / "PelicanSaveEditor/Assets.xcassets").rglob("*")
                        if path.suffix.lower() in (".png", ".jpg", ".jpeg")}
        if bitmap_paths != seen_files:
            errors.append({"unlisted_bitmaps": sorted(bitmap_paths - seen_files), "missing_bitmaps": sorted(seen_files - bitmap_paths)})
        for contents_path in (self.root / "PelicanSaveEditor/Assets.xcassets").rglob("Contents.json"):
            try:
                contents = read_json(contents_path)
                for item in contents.get("images", []):
                    if item.get("filename") and not (contents_path.parent / item["filename"]).is_file():
                        errors.append(f"Missing catalog image: {self.relative(contents_path.parent / item['filename'])}")
            except Exception as error:
                errors.append(f"{self.relative(contents_path)}: {error}")
        self.record("asset_manifest_hash_dimensions_and_catalog_coverage", not errors,
                    {"manifest_entries": len(manifest), "verified_bitmaps": len(details), "png_crc_validation": True, "errors": errors})
        self.facts["assets"] = details

    def versions(self):
        errors = []
        expected = {"MARKETING_VERSION": self.expected_version, "CURRENT_PROJECT_VERSION": self.expected_build}
        settings_values = {key: set() for key in expected}
        for obj in self.objects.values():
            if obj.get("isa") == "XCBuildConfiguration":
                settings = obj.get("buildSettings", {})
                for key in expected:
                    if key in settings:
                        settings_values[key].add(settings[key])
        for key, value in expected.items():
            if settings_values[key] != {value}:
                errors.append(f"pbxproj {key}: expected {value}, got {sorted(settings_values[key])}")
        # Deliberately limited extraction of scalar build settings, not a YAML parser.
        yaml = (self.root / "project.yml").read_text(encoding="utf-8-sig")
        for key, value in expected.items():
            matches = re.findall(rf'^\s*{key}:\s*[\"\']?([^\"\'\s#]+)', yaml, re.M)
            if set(matches) != {value}:
                errors.append(f"project.yml {key}: expected {value}, got {matches}")
        info = plistlib.loads((self.root / "PelicanSaveEditor/Info.plist").read_bytes())
        for plist_key, build_key in (("CFBundleShortVersionString", "MARKETING_VERSION"), ("CFBundleVersion", "CURRENT_PROJECT_VERSION")):
            if info.get(plist_key) not in (f"$({build_key})", expected[build_key]):
                errors.append(f"Info.plist {plist_key}: {info.get(plist_key)}")
        readme = (self.root / "README.md").read_text(encoding="utf-8-sig")
        declared = re.search(r"源码版本[：:]\s*`([^`]+)`[（(]构建\s*`([^`]+)`", readme)
        if not declared or declared.groups() != (self.expected_version, self.expected_build):
            errors.append(f"README declared release: {declared.groups() if declared else 'not found'}")
        settings_path = self.root / "PelicanSaveEditor/Views/Home/SettingsView.swift"
        settings_text = settings_path.read_text(encoding="utf-8-sig")
        for plist_key, expected_value in (("CFBundleShortVersionString", self.expected_version), ("CFBundleVersion", self.expected_build)):
            line = next((line for line in settings_text.splitlines() if plist_key in line), "")
            if f'?? "{expected_value}"' not in line:
                errors.append(f"Settings fallback for {plist_key} does not match {expected_value}")
        self.record("release_versions_consistent", not errors,
                    {"expected_version": self.expected_version, "expected_build": self.expected_build,
                     "pbxproj_values": {key: sorted(values) for key, values in settings_values.items()}, "errors": errors})

    def run(self):
        for operation in (self.project, self.documents, self.assets, self.versions):
            try:
                operation()
            except Exception as error:
                self.record(operation.__name__, False, f"{type(error).__name__}: {error}")
        failures = [check for check in self.checks if check["status"] == "failed"]
        report = {
            "schema_version": 1,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "release_root": str(self.root),
            "validation_type": "offline_static_release_checks",
            "compiled_swift": False,
            "executed_xctest": False,
            "validated_on_ios_device": False,
            "limitations": ["Does not compile or type-check Swift.", "Does not execute XCTest or UI tests.",
                            "Does not validate iOS file-provider behavior or in-game save compatibility.",
                            "Does not re-fetch or license-check remote asset sources."],
            "summary": {"status": "passed" if not failures else "failed", "checks": len(self.checks), "failed_checks": len(failures)},
            "checks": self.checks,
            "facts": self.facts,
        }
        self.output.parent.mkdir(parents=True, exist_ok=True)
        self.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"report": str(self.output), **report["summary"], "counts": self.facts.get("source_counts"),
                          "asset_count": len(self.facts.get("assets", [])), "failures": failures}, ensure_ascii=True, indent=2))
        return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--version", default="0.3.3")
    parser.add_argument("--build", default="9")
    args = parser.parse_args()
    output = args.output or args.root / "validation/static-release-results.json"
    return Validator(args.root, args.version, args.build, output).run()


if __name__ == "__main__":
    sys.exit(main())
