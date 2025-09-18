#!/usr/bin/env python3
"""Utilities to verify Flipper packages without hardware.

This script provides a repeatable pipeline for checking that each app in the
repository builds cleanly using ``ufbt``.  It replaces the ad-hoc process of
copying sources into the firmware tree and loading them on-device, enabling
local verification with just the toolchain.

Steps performed for every ``apps/*/fap`` directory:

1. ``ufbt lint`` – style and static analysis checks.
2. ``ufbt build`` – compile the package and ensure the resulting ``.fap`` is
   produced.

If any step fails, a concise error is printed and the script exits with a
non-zero status code, making it suitable for CI environments.  The optional
``--skip-build`` and ``--skip-lint`` flags can be used to focus on a specific
stage, and ``--release`` asks ``ufbt`` to build a release package.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable, List


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-lint",
        action="store_true",
        help="Skip running 'ufbt lint'.",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip running 'ufbt build'.",
    )
    parser.add_argument(
        "--release",
        action="store_true",
        help="Build release artifacts using 'ufbt build --release'.",
    )
    parser.add_argument(
        "apps",
        nargs="*",
        metavar="APP_PATH",
        help=(
            "Specific app directories to check. Provide paths like "
            "'apps/mouse-jiggler/fap'. If omitted, every discovered app is used."
        ),
    )
    return parser.parse_args(list(argv))


def discover_apps(explicit_apps: Iterable[str]) -> List[Path]:
    repo_root = Path(__file__).resolve().parents[1]
    if explicit_apps:
        apps = [repo_root / Path(app_path) for app_path in explicit_apps]
    else:
        apps = sorted(repo_root.glob("apps/*/fap"))

    filtered = []
    for app in apps:
        if not app.exists():
            raise FileNotFoundError(f"App path does not exist: {app}")
        if not app.is_dir():
            raise NotADirectoryError(f"App path is not a directory: {app}")
        filtered.append(app)
    if not filtered:
        raise RuntimeError("No applications discovered. Check the paths supplied.")
    return filtered


def ensure_ufbt_available() -> None:
    if shutil.which("ufbt") is None:
        raise SystemExit(
            "ufbt executable not found. Install it with 'pip install ufbt' or "
            "activate the repository's venv."
        )


def run_command(command: List[str], *, cwd: Path) -> None:
    print(f"\n→ {' '.join(command)} (in {cwd})")
    completed = subprocess.run(command, cwd=cwd, check=False)
    if completed.returncode != 0:
        raise subprocess.CalledProcessError(
            completed.returncode, command, None, None
        )


def run_pipeline(app_dir: Path, *, skip_lint: bool, skip_build: bool, release: bool) -> None:
    if not skip_lint:
        run_command(["ufbt", "lint"], cwd=app_dir)

    if not skip_build:
        cmd = ["ufbt", "build"]
        if release:
            cmd.append("--release")
        run_command(cmd, cwd=app_dir)


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    ensure_ufbt_available()
    apps = discover_apps(args.apps)

    print("Discovered apps to test:")
    for app in apps:
        print(f"  - {app.relative_to(Path.cwd())}")

    failures: List[tuple[Path, BaseException]] = []
    for app_dir in apps:
        print("\n=== Running pipeline for", app_dir.name, "===")
        try:
            run_pipeline(
                app_dir,
                skip_lint=args.skip_lint,
                skip_build=args.skip_build,
                release=args.release,
            )
        except BaseException as exc:  # pragma: no cover - defensive programming
            failures.append((app_dir, exc))
            print(f"❌ Failure in {app_dir}: {exc}")

    if failures:
        print("\nSummary: FAIL")
        for app_dir, exc in failures:
            print(f"  - {app_dir}: {exc}")
        return 1

    print("\nSummary: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
