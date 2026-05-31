#!/usr/bin/env python3
"""ship_clipwatch.py — Ship ClipWatch. Delegates to ~/Developer/shared/ship_swift_app.py.
All options (--push, --dry-run) are passed through.
See ~/Developer/shared/ship_swift_app.py for full documentation.
"""
import subprocess, sys
from pathlib import Path
SHARED = Path.home() / "Developer/scotty/scripts/ship_swift_app.py"
result = subprocess.run(["python3", str(SHARED), "--app", "ClipWatch"] + sys.argv[1:])
sys.exit(result.returncode)
