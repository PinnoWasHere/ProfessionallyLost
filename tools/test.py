"""Runs Professionally Lost's headless tests on the own fake game (tests/own).

    python tools/test.py                              every tests/headless/*_test.lua
    python tools/test.py tests/headless/clamp_test.lua   only the files named
    python tools/test.py --jobs 4 --lua lua5.1        four at a time, on plain Lua 5.1

Each file runs in its own process: the fake game loads, then the addon by its .toc, then
tests/world and tests/rules, then the test file. Needs Python 3.9+ and LuaJIT (or Lua 5.1) on the
PATH. Exits 1 when any test fails, errors or gives no report.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = "tests/own/run.lua"
SUMMARY = re.compile(r"^OWN (\d+) passed (\d+) failed (\d+) errors$", re.M)
ITEM = re.compile(r"^(?:FAIL|ERROR) ", re.M)
SECONDS = 600


def test_files(named: list[str]) -> list[str]:
    """The named test files, or every tests/headless/*_test.lua, as paths from the repo root."""
    if named:
        return [Path(n).as_posix() for n in named]
    return sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "tests" / "headless").glob("*_test.lua"))


def report(test: str, out: str) -> tuple[int, list[str]]:
    """(test count, failure lines) from one run's output."""
    summary = SUMMARY.search(out)
    if not summary:
        return 0, [f"{test}: no report: {out.strip()[-300:]}"]
    passed, failed, errors = (int(n) for n in summary.groups())
    starts = [m.start() for m in ITEM.finditer(out)] + [summary.start()]
    fails = []
    for a, b in zip(starts, starts[1:]):
        head, _, rest = out[a:b].strip().partition("\n")
        kind, _, name = head.partition(" ")
        name = name.split(" / ", 1)[-1]
        fails.append(f"{test}: {'' if kind == 'FAIL' else 'error: '}{name}: {' '.join(rest.split())}")
    if (failed or errors) and not fails:
        fails.append(f"{test}: the run failed without a failing test")
    return passed + failed, fails


def run_one(lua: str, test: str) -> tuple[int, list[str]]:
    try:
        run = subprocess.run([lua, RUNNER, "--only", test], cwd=ROOT, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=SECONDS)
    except subprocess.TimeoutExpired:
        return 0, [f"{test}: no report: still running after {SECONDS} s"]
    return report(test, run.stdout + run.stderr)


LOCATION = re.compile(r"((?:ProfessionallyLost|tests|tools)/[\w./-]+\.lua):(\d+)")


def first_error(line: str) -> str:
    """The message of one failure line, without the leading test file."""
    return line.split(": ", 1)[-1].strip()


def annotate(line: str) -> str:
    """A GitHub error annotation for one failure line, with the line number when it names one."""
    found = LOCATION.search(line)
    where = f"file={found.group(1)},line={found.group(2)}" if found else f"file={line.split(': ', 1)[0]}"
    message = first_error(line).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return f"::error {where}::{message}"


def write_summary(path: str, fails: list[str]) -> None:
    """Appends the failed tests and their first error to the GitHub step summary file."""
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"### Headless tests: {len(fails)} failed\n\n")
        for line in fails:
            f.write(f"- `{line.split(': ', 1)[0]}`: {first_error(line)}\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="test files to run (default: every tests/headless/*_test.lua)")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2, help="files run at once")
    ap.add_argument("--lua", default="luajit", help="the Lua to run on: luajit (default) or a Lua 5.1")
    opt = ap.parse_args()
    lua = shutil.which(opt.lua)
    if not lua:
        print(f"{opt.lua} is not on the PATH; install LuaJIT or pass --lua <a Lua 5.1>")
        return 1
    tests = test_files(opt.files)
    with ThreadPoolExecutor(max_workers=max(1, opt.jobs)) as pool:
        results = list(pool.map(lambda t: run_one(lua, t), tests))
    count = sum(n for n, _ in results)
    fails = [line for _, lines in results for line in lines]
    for line in fails:
        print("FAIL " + line)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if fails and summary:
        write_summary(summary, fails)
        for line in fails:
            print(annotate(line))
    print(f"{len(tests)} files, {count} tests: {'FAIL' if fails else 'ok'}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
