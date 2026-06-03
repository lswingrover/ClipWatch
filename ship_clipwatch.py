#!/usr/bin/env python3
"""ship_clipwatch.py — Ship ClipWatch. Delegates to ship_swift_app.py.
All options (--push, --dry-run) are passed through.

Requires SHIP_SCRIPTS_DIR env var pointing to a directory containing
ship_swift_app.py. See that script for full documentation.
"""

import os, subprocess, sys
from pathlib import Path

scripts_dir = os.environ.get("SHIP_SCRIPTS_DIR")
if not scripts_dir:
    raise SystemExit("Error: SHIP_SCRIPTS_DIR env var not set. Point it to the directory containing ship_swift_app.py.")

SHARED = Path(scripts_dir) / "ship_swift_app.py"
if not SHARED.exists():
    raise SystemExit(f"Error: ship_swift_app.py not found at {SHARED}")

result = subprocess.run(["python3", str(SHARED), "--app", "ClipWatch"] + sys.argv[1:])
sys.exit(result.returncode)
