"""Compiles every ProfessionallyLost/**/*.lua under plain Lua 5.1 (the game's Lua) with lupa.

    pip install lupa
    python tools/lua51_check.py

Prints `file:line: message` for each file that does not compile, and `::error` annotations on
GitHub Actions. Exits 1 when any file fails.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "ProfessionallyLost"
POSITION = re.compile(r"^.*?:(\d+):\s*(.*)$", re.S)


def main() -> int:
    try:
        from lupa import lua51
    except ImportError:
        print("lupa with Lua 5.1 is missing; run: pip install lupa")
        return 1
    lua = lua51.LuaRuntime()
    load = lua.eval("function(src, name) local f, err = loadstring(src, name) return err end")
    files = sorted(ADDON.rglob("*.lua"))
    bad = 0
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        source = path.read_bytes().decode("utf-8", errors="replace")
        err = load(source, "=" + rel)
        if err is None:
            continue
        bad += 1
        match = POSITION.match(str(err))
        line, message = (match.group(1), match.group(2)) if match else ("1", str(err))
        print(f"{rel}:{line}: {message}")
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::error file={rel},line={line}::{message}")
    print(f"{len(files)} files under Lua 5.1: {'FAIL' if bad else 'ok'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
