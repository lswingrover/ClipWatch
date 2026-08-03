#!/usr/bin/env python3
"""ship_clipwatch.py — Ship ClipWatch via the shared scotty ship_swift_app.py driver.

Thin wrapper (fleet parity): all real ship logic — version bump, build+install,
credential preflight, changelog, commit, tag, push, GitHub Release with the built
.app attached — lives in the ONE shared driver. All flags pass through:
  --push  --minor|--major|--version X.Y.Z  --notes "..."  --dry-run
"""
import os, subprocess, sys
from pathlib import Path

# Self-locating: default to the scotty checkout so no env juggling is needed.
scripts_dir = os.environ.get("SHIP_SCRIPTS_DIR") or str(Path.home() / "Developer/scotty/scripts")
SHARED = Path(scripts_dir) / "ship_swift_app.py"
if not SHARED.exists():
    raise SystemExit(f"Error: ship_swift_app.py not found at {SHARED}. Set SHIP_SCRIPTS_DIR to the scotty scripts dir.")

env = {**os.environ}
env.setdefault("SCOTTY_SHIP_VIA_SKILL", "1")  # this wrapper is the sanctioned ship entrypoint
sys.exit(subprocess.run(["python3", str(SHARED), "--app", "ClipWatch"] + sys.argv[1:], env=env).returncode)
