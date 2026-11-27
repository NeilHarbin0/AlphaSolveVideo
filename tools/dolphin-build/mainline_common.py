"""What the Windows and Linux builds of Slippi's mainline playback Dolphin share: the pinned source with this repo's
patches, downloads checked against a SHA-256, CMake 3.31 and Ninja in a venv, and Rust 1.88.0.

build-windows-mainline.py and build-linux-mainline.py import this; build-mac-mainline.sh does the same in bash.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional, Sequence

REPO = Path(__file__).resolve().parents[2]

COMMIT = "c5f635948ed43f4d14a72069343e0cecdc117391"  # fix/mainline-playback, 2026-06-15, as build-mac-mainline.sh
DOLPHIN_GIT = "https://github.com/project-slippi/dolphin.git"
RUST = "1.88.0"  # Externals/SlippiRustExtensions/rust-toolchain.toml


def _exe(name: str) -> str:
    return name + (".exe" if os.name == "nt" else "")


def _cache_root() -> Path:
    if os.environ.get("ALPHASOLVE_CACHE"):
        return Path(os.environ["ALPHASOLVE_CACHE"]).expanduser()
    if sys.platform == "darwin":
        base = Path.home() / "Library" / "Caches"
    elif os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local")
    else:
        base = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return base / "AlphaSolveVideo"


CACHE = _cache_root()
SRC = CACHE / "mainline"
BUILD = SRC / "build"
PATCHES = REPO / "tools" / "dolphin-build" / "patches-mainline"
VENV = CACHE / "venv-cmake3"


def log(message: str) -> None:
    print(f"\n== {message}", flush=True)


def fail(message: str) -> None:
    sys.exit(f"ERROR: {message}")


def git(*args: str, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(SRC), *args], check=check, capture_output=capture,
                          encoding="utf-8", errors="replace")


def tee(cmd: Sequence, log_file: Path, env: Optional[Dict[str, str]] = None) -> str:
    """Run a command, showing its output as it comes and keeping a copy in log_file. Returns the output."""
    print("+ " + " ".join(str(c) for c in cmd), flush=True)
    lines: List[str] = []
    with subprocess.Popen([str(c) for c in cmd], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
                          encoding="utf-8", errors="replace") as proc, \
            open(log_file, "w", encoding="utf-8") as out:
        for line in proc.stdout:
            sys.stdout.write(line)
            out.write(line)
            lines.append(line)
    if proc.returncode:
        fail(f"{Path(str(cmd[0])).name} exited with {proc.returncode}; the output is in {log_file}")
    return "".join(lines)


# ---------------------------------------------------------------- source
def fetch() -> None:
    if not (SRC / ".git").exists():
        log(f"Fetching Slippi mainline Dolphin {COMMIT}")
        SRC.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init", "-q", str(SRC)], check=True)
        git("config", "core.autocrlf", "false")  # the patches and Dolphin's sources are LF
        git("config", "core.longpaths", "true")
        git("remote", "add", "origin", DOLPHIN_GIT)
    if git("rev-parse", "HEAD", check=False, capture=True).stdout.strip() != COMMIT:
        git("fetch", "-q", "--depth", "1", "origin", COMMIT)
        git("checkout", "-q", "FETCH_HEAD")
    # Every submodule but Externals/Qt (378 MB of Windows Qt binaries), which the NoGUI build doesn't use.
    listed = git("config", "-f", ".gitmodules", "--get-regexp", r"\.path$", capture=True).stdout.split()
    paths = [p for p in listed[1::2] if p != "Externals/Qt"]
    git("-c", "core.autocrlf=false", "submodule", "update", "--init", "--recursive", "--depth", "1",
        "--jobs", "4", "--", *paths)
    apply_patches()


def apply_patches() -> None:
    """As build-mac-mainline.sh: the patches go on in order, so the tree has the first k of them. The last of
    those has nothing on top, so it reverse-checks on its own; the rest go on one by one."""
    patches = sorted(PATCHES.glob("*.patch"))
    for p in patches:
        if b"\r\n" in p.read_bytes():
            fail(f"{p} has Windows (CRLF) line endings, so it won't apply. This checkout predates .gitattributes "
                 "keeping patches LF: run `git rm --cached -r . && git reset --hard` in the repo (it only "
                 "rewrites line endings), or clone it again.")
    applied = 0
    for i in range(len(patches), 0, -1):
        if git("apply", "--reverse", "--check", str(patches[i - 1]), check=False, capture=True).returncode == 0:
            applied = i
            break
    for p in patches[:applied]:
        print(f"already applied: {p.name}")
    for p in patches[applied:]:
        log(f"Applying {p.name}")
        if git("apply", str(p), check=False).returncode != 0:
            fail(f"{p.name} doesn't apply to {SRC}: it has changes the patches don't expect (an older version "
                 "of a patch, or edits). Undo them, then run this again:\n"
                 f'  git -C "{SRC}" checkout -- . && git -C "{SRC}" clean -fd Source && '
                 f'git -C "{SRC}" submodule foreach --recursive git checkout -- .')


# ---------------------------------------------------------------- tools
def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    try:
        with urllib.request.urlopen(url, timeout=600) as r, open(part, "wb") as f:
            shutil.copyfileobj(r, f, 1 << 20)
    except OSError:  # e.g. no CA certificates for Python: curl is part of Windows 10 and later, and of most Linux
        subprocess.run(["curl", "-fL", "--retry", "3", "-o", str(part), url], check=True)
    part.replace(dest)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def venv_tools(programs: Sequence[str] = ("cmake", "ninja"),
               requirements: Sequence[str] = ("cmake>=3.31,<3.32", "ninja")) -> Path:
    """The folder of a venv with these programs from pip (CMake 4 rejects the cmake_minimum_required of some
    submodules, hence CMake 3.31). Installs them the first time."""
    bin_dir = VENV / ("Scripts" if os.name == "nt" else "bin")
    if not all((bin_dir / _exe(name)).exists() for name in programs):
        log(f"Installing {', '.join(programs)} into {VENV}")
        if subprocess.run([sys.executable, "-m", "venv", str(VENV)]).returncode != 0:
            fail(f"couldn't make a venv at {VENV}; on Debian or Ubuntu, install python3-venv")
        subprocess.run([str(bin_dir / _exe("python")), "-m", "pip", "install", "-q",
                        "--disable-pip-version-check", *requirements], check=True)
    return bin_dir


def ensure_rust() -> None:
    if not shutil.which("rustup"):
        fail("rustup not found: install Rust from https://rustup.rs")
    toolchains = subprocess.run(["rustup", "toolchain", "list"], capture_output=True, encoding="utf-8",
                                errors="replace").stdout
    if not any(line.startswith(RUST) for line in toolchains.splitlines()):
        log(f"Installing Rust {RUST}")
        subprocess.run(["rustup", "toolchain", "install", RUST, "--profile", "minimal", "--component", "rustfmt"],
                       check=True)


def run_steps(steps: Dict[str, Sequence], argv: Sequence[str], script: str) -> int:
    step = argv[0] if argv else "all"
    if step not in steps or len(argv) > 1:
        print(f"usage: {script} [{'|'.join(steps)}]", file=sys.stderr)
        return 2
    for function in steps[step]:
        function()
    return 0
