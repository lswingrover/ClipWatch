#!/usr/bin/env python3
"""ship_clipwatch.py — Build, install, commit, tag, and push ClipWatch.

Usage:
    python3 ship_clipwatch.py            # build + install only
    python3 ship_clipwatch.py --push     # build + install + commit + tag + push
    python3 ship_clipwatch.py --dry-run  # show what would happen
"""
import subprocess, sys, re
from pathlib import Path

REPO = Path(__file__).parent
DRY  = "--dry-run" in sys.argv
PUSH = "--push" in sys.argv

def run(cmd, **kw):
    if DRY:
        print(f"  [dry-run] {' '.join(cmd) if isinstance(cmd, list) else cmd}")
        return ""
    result = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if result.returncode != 0:
        print(f"❌  FAILED: {result.stderr.strip() or result.stdout.strip()}")
        sys.exit(1)
    return result.stdout.strip()

def version() -> str:
    ver_file = REPO / "Sources/ClipWatch/Version.swift"
    m = re.search(r'"([\d.]+)"', ver_file.read_text())
    return m.group(1) if m else "unknown"

print(f"\n==================================================")
print(f"  Shipping ClipWatch")
print(f"==================================================\n")

v = version()
print(f"▶ Version: {v}")

# Check git state
status = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain"],
                        capture_output=True, text=True).stdout.strip()
if status:
    print(f"  Dirty files:\n{status}")

# Build + install
print("\n▶ Running build_app.sh...")
build_result = subprocess.run(
    ["bash", str(REPO / "build_app.sh")],
    cwd=str(REPO)
)
if build_result.returncode != 0:
    print("❌  build_app.sh failed")
    sys.exit(1)
print("✅  Build + install complete")

if not PUSH:
    print("\n  (pass --push to commit + tag + push)")
    sys.exit(0)

# Commit + tag + push
print("\n▶ Committing...")
run(["git", "-C", str(REPO), "add", "-A"], shell=False)
run(["git", "-C", str(REPO), "commit", "--allow-empty",
     "-m", f"chore: ship ClipWatch v{v}"], shell=False)
print(f"▶ Tagging v{v}...")
run(["git", "-C", str(REPO), "tag", "-f", f"v{v}"], shell=False)
print("▶ Pushing...")
run(["git", "-C", str(REPO), "push", "--follow-tags"], shell=False)
print(f"\n✅  ClipWatch v{v} shipped")
