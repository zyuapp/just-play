#!/usr/bin/env python3
"""Update the XcodeGen version; regenerate Info.plist before committing."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("bump", choices=("patch", "minor", "major"))
args = parser.parse_args()
spec = Path(__file__).resolve().parents[1] / "project.yml"
text = spec.read_text()
version_pattern = r'(CFBundleShortVersionString: ")([0-9]+\.[0-9]+(?:\.[0-9]+)?)(")'
build_pattern = r'(CFBundleVersion: ")([0-9]+)(")'
version = re.findall(version_pattern, text)
build = re.findall(build_pattern, text)
if len(version) != 1 or len(build) != 1:
    raise SystemExit("Expected exactly one numeric app version and build number in project.yml")
parts = [int(part) for part in version[0][1].split(".")]
parts += [0] * (3 - len(parts))
index = {"major": 0, "minor": 1, "patch": 2}[args.bump]
parts[index] += 1
parts[index + 1:] = [0] * (2 - index)
new_version = ".".join(map(str, parts))
text = re.sub(version_pattern, lambda m: m[1] + new_version + m[3], text)
text = re.sub(build_pattern, lambda m: m[1] + str(int(m[2]) + 1) + m[3], text)
spec.write_text(text)
print(new_version)
