#!/usr/bin/env python3
"""Linux build of Slippi's mainline playback Dolphin: headless (NoGUI), with frame dumping and this repo's patches.
The Linux counterpart of build-mac-mainline.sh and build-windows-mainline.py; docs/plan-linux.md has the reasoning.

    python3 tools/dolphin-build/build-linux-mainline.py [fetch|configure|build|bundle|all]   (default: all)

Needs GCC 11 or newer, make, git, curl, xz, pkg-config, Python 3.9 or newer with venv, and the development files of
zlib, ALSA and EGL. On Debian or Ubuntu:

    sudo apt install build-essential git curl ca-certificates xz-utils pkg-config python3 python3-venv nasm \\
        zlib1g-dev libasound2-dev libegl-dev

and Rust from https://rustup.rs. CMake 3.31, Ninja and patchelf come from pip, into a venv in the work folder, and
FFmpeg 8.1.3 is built from source (build-ffmpeg.sh), as on macOS. tools/dolphin-build/linux.Dockerfile has all of
this in Ubuntu 22.04, whose glibc (2.35) sets the oldest Linux the package runs on; a build on a newer system needs
that system's glibc or newer.

The result goes to packages/slippi-playback-mainline/ (dolphin-emu-nogui, its libraries and Sys/), where slp2alpha
looks for it. The GitHub Actions workflow .github/workflows/dolphin-linux.yml runs this script.

Environment:
  ALPHASOLVE_CACHE   work folder (default ~/.cache/AlphaSolveVideo)
  OUTPUT_DIR         where the package goes (default <repo>/packages/slippi-playback-mainline)
  JOBS               build parallelism (default: all cores)
"""

from __future__ import annotations

import datetime
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from mainline_common import (BUILD, CACHE, COMMIT, DOLPHIN_GIT, PATCHES, REPO, RUST, SRC, ensure_rust, fail, fetch,
                             log, run_steps, tee, venv_tools)

ARCH = platform.machine()  # x86_64 or aarch64
FFMPEG_VERSION = "8.1.3"  # as build-mac-mainline.sh
FFMPEG = CACHE / f"ffmpeg8-linux-{ARCH}"
OUT = Path(os.environ.get("OUTPUT_DIR") or REPO / "packages" / "slippi-playback-mainline")
EXE = "dolphin-emu-nogui"
RUST_LIB = "libslippi_rust_extensions.so"
APT = ("sudo apt install build-essential git curl ca-certificates xz-utils pkg-config python3 python3-venv nasm "
       "zlib1g-dev libasound2-dev libegl-dev")
CMAKE_ARGS = [
    "-G", "Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
    f"-DFFMPEG_DIR={FFMPEG}",
    "-DSLIPPI_PLAYBACK=ON",
    "-DLINUX_LOCAL_DEV=ON",  # Sys next to the program, not in ~/.config/SlippiOnline
    "-DENABLE_QT=OFF",
    "-DENABLE_NOGUI=ON",
    "-DENABLE_SDL=OFF",
    "-DENABLE_TESTS=OFF",
    "-DENABLE_LLVM=OFF",
    "-DENABLE_ANALYTICS=OFF",
    "-DENABLE_AUTOUPDATE=OFF",
    "-DUSE_DISCORD_PRESENCE=OFF",
    "-DUSE_SYSTEM_LIBS=OFF",
    # No window, no controllers, no sound: and no dependency on whatever the build machine has for them
    "-DENABLE_X11=OFF",
    "-DENABLE_EVDEV=OFF",
    "-DENABLE_HWDB=OFF",
    "-DENABLE_BLUEZ=OFF",
    "-DENABLE_ALSA=OFF",
    "-DENABLE_PULSEAUDIO=OFF",
    f"-DRust_TOOLCHAIN={RUST}",
]  # Vulkan (the backend) and EGL (OpenGL's, the fallback) stay on

# Libraries the package may take from the system: glibc's, the C++ runtime, and three that every desktop has.
# Vulkan isn't one: Dolphin loads libvulkan.so.1 itself, when the Vulkan backend starts.
SYSTEM_LIBS = {
    "libc.so.6", "libm.so.6", "libdl.so.2", "librt.so.1", "libpthread.so.0",
    "ld-linux-x86-64.so.2", "ld-linux-aarch64.so.1",
    "libstdc++.so.6", "libgcc_s.so.1",
    "libz.so.1", "libEGL.so.1", "libasound.so.2",
}


# ---------------------------------------------------------------- tools
def require_linux() -> None:
    if not sys.platform.startswith("linux"):
        fail("this builds the Linux package; on macOS use tools/dolphin-build/build-mac-mainline.sh, or this script "
             "in Docker (tools/dolphin-build/linux.Dockerfile)")


def check_packages() -> None:
    """The compilers and development files the build needs, with the apt line that installs what's missing."""
    missing = [tool for tool in ("gcc", "g++", "make", "git", "curl", "xz", "pkg-config", "readelf", "strip")
               if not shutil.which(tool)]
    gcc = subprocess.run(["gcc", "-dumpfullversion"], capture_output=True, encoding="utf-8").stdout.strip() \
        if shutil.which("gcc") else ""
    if gcc and int(gcc.split(".")[0]) < 11:
        missing.append(f"GCC 11 or newer (this is {gcc})")
    if shutil.which("pkg-config"):
        missing += [f"{name} development files" for name in ("zlib", "alsa", "egl")
                    if subprocess.run(["pkg-config", "--exists", name]).returncode != 0]
    if subprocess.run([sys.executable, "-c", "import ensurepip, venv"], capture_output=True).returncode != 0:
        missing.append("Python's venv")
    if missing:
        fail("missing: " + ", ".join(missing) + f". On Debian or Ubuntu:\n  {APT}")
    if ARCH == "x86_64" and not shutil.which("nasm"):
        print("Note: without nasm, FFmpeg is built without its x86 assembly")


def build_env() -> Dict[str, str]:
    env = dict(os.environ)
    cargo_bin = Path.home() / ".cargo" / "bin"  # where rustup installs, if it isn't on the PATH yet
    env["PATH"] = os.pathsep.join([str(venv_tools()), str(cargo_bin), env.get("PATH", "")])
    return env


def ensure_ffmpeg() -> Path:
    """Our minimal FFmpeg (FFV1 and Ut Video, AVI, Matroska and MOV), built from source as on macOS."""
    if not (FFMPEG / "lib" / "libavcodec.so").exists():
        log(f"Building FFmpeg {FFMPEG_VERSION} into {FFMPEG}")
        tee(["bash", REPO / "tools" / "dolphin-build" / "build-ffmpeg.sh", FFMPEG_VERSION, ARCH, FFMPEG],
            CACHE / "ffmpeg8-build.log", dict(os.environ, ALPHASOLVE_CACHE=str(CACHE)))
    return FFMPEG


# ---------------------------------------------------------------- configure, build
def configure() -> None:
    require_linux()
    check_packages()
    env = build_env()
    if not shutil.which("rustup", path=env["PATH"]):
        fail("rustup not found: install Rust from https://rustup.rs")
    os.environ["PATH"] = env["PATH"]
    ensure_rust()
    ensure_ffmpeg()
    log(f"Configuring ({ARCH}, playback, NoGUI only, FFmpeg {FFMPEG_VERSION} from {FFMPEG})")
    out = tee(["cmake", "-S", SRC, "-B", BUILD, *CMAKE_ARGS], CACHE / "mainline-configure.log", env)
    if "libav/ffmpeg found, enabling AVI frame dumps" not in out:
        fail("CMake did not find FFmpeg, so frame dumping would be disabled")
    found = [line for line in out.splitlines() if "Found avcodec:" in line]
    if not found or str(FFMPEG) not in found[0]:
        fail(f"CMake found another FFmpeg than {FFMPEG}: {found[:1]}")
    if "EGL OpenGL interface enabled" not in out:
        fail("CMake did not find EGL, so there would be no OpenGL backend without a window")


def build() -> None:
    require_linux()
    env = build_env()
    jobs = os.environ.get("JOBS") or str(os.cpu_count() or 4)
    log(f"Building dolphin-nogui with {jobs} parallel jobs")
    tee(["cmake", "--build", BUILD, "--target", "dolphin-nogui", "-j", jobs], CACHE / "mainline-build.log", env)


# ---------------------------------------------------------------- bundle
def elf_needed(binary: Path) -> Tuple[List[str], Optional[str]]:
    """The libraries an ELF file asks for (its NEEDED entries) and its run path."""
    out = subprocess.run(["readelf", "-d", str(binary)], capture_output=True, encoding="utf-8", errors="replace",
                         check=True).stdout
    needed = re.findall(r"\(NEEDED\)\s+Shared library: \[(.+?)\]", out)
    runpath = re.search(r"\((?:RUNPATH|RPATH)\)\s+Library r(?:un)?path: \[(.*?)\]", out)
    return needed, runpath.group(1) if runpath else None


def glibc_needed(binary: Path) -> Tuple[int, int]:
    """The newest glibc symbol version an ELF file uses."""
    out = subprocess.run(["readelf", "--version-info", "-W", str(binary)], capture_output=True, encoding="utf-8",
                         errors="replace", check=True).stdout
    versions = [(int(a), int(b)) for a, b in re.findall(r"Name: GLIBC_(\d+)\.(\d+)", out)]
    return max(versions, default=(0, 0))


def rust_library() -> Path:
    found = sorted(BUILD.glob(f"cargo/build/*/release/{RUST_LIB}"))
    if len(found) != 1:
        fail(f"expected one {RUST_LIB} under {BUILD / 'cargo' / 'build'}, found {[str(f) for f in found]}")
    return found[0]


def bundle() -> None:
    require_linux()
    exe = BUILD / "Binaries" / EXE
    if not exe.exists():
        fail(f"{exe} isn't built")
    patchelf = venv_tools(("cmake", "ninja", "patchelf"), ("cmake>=3.31,<3.32", "ninja", "patchelf")) / "patchelf"
    stage = BUILD / "AlphaSolvePackage"
    log(f"Assembling {stage}")
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir(parents=True)
    shutil.copy2(exe, stage / EXE)

    # The libraries the program needs that aren't the system's: ours, under the names the program asks for.
    sources = {RUST_LIB: rust_library()}
    sources.update({p.name: p for p in sorted((FFMPEG / "lib").glob("lib*.so.*"))})
    todo, missing = [stage / EXE], set()
    while todo:
        binary = todo.pop()
        for name in elf_needed(binary)[0]:
            if name in SYSTEM_LIBS or (stage / name).exists():
                continue
            if name in sources:
                shutil.copyfile(sources[name], stage / name)  # the file a symlink points to, under its SONAME
                todo.append(stage / name)
            else:
                missing.add(f"{name} (needed by {binary.name})")
    if missing:
        fail("libraries that are neither ours nor on the list of system ones: " + ", ".join(sorted(missing)))

    log("Stripping debug information, and pointing every file at its own folder ($ORIGIN)")
    for binary in sorted(stage.iterdir()):
        subprocess.run(["strip", "--strip-debug", str(binary)], check=True)
        subprocess.run([str(patchelf), "--set-rpath", "$ORIGIN", str(binary)], check=True)

    log("Checking the libraries")
    newest = (0, 0)
    for binary in sorted(stage.iterdir()):
        needed, runpath = elf_needed(binary)
        if runpath != "$ORIGIN":
            fail(f"{binary.name} has the run path {runpath!r}, not $ORIGIN")
        if any("/" in name for name in needed):
            fail(f"{binary.name} asks for a library by its path: {needed}")
        newest = max(newest, glibc_needed(binary))
        print(f"{binary.name}: {', '.join(needed)}")
    glibc = f"{newest[0]}.{newest[1]}"
    print(f"Needs glibc {glibc} or newer")

    # Dolphin looks for Sys next to the program (LINUX_LOCAL_DEV). Playback builds swap the netplay Gecko codes
    # for the playback ones.
    shutil.copytree(SRC / "Data" / "Sys", stage / "Sys")
    shutil.copy2(SRC / "Data" / "PlaybackGeckoCodes" / "GALE01r2.ini", stage / "Sys" / "GameSettings" / "GALE01r2.ini")
    for placeholder in (stage / "Sys" / "GameSettings").glob("Replace *.txt"):
        placeholder.unlink()
    shutil.copy2(SRC / "COPYING", stage / "COPYING")
    shutil.copytree(SRC / "LICENSES", stage / "Licenses")
    ffmpeg_source = CACHE / "src" / f"ffmpeg-{FFMPEG_VERSION}-{ARCH}"
    for name in ("COPYING.LGPLv2.1", "LICENSE.md"):
        if (ffmpeg_source / name).exists():
            shutil.copy2(ffmpeg_source / name, stage / "Licenses" / f"FFmpeg-{name}")

    log("Checking the program")
    env = {k: v for k, v in os.environ.items() if k != "LD_LIBRARY_PATH"}
    help_out = subprocess.run([str(stage / EXE), "--help"], capture_output=True, encoding="utf-8", errors="replace",
                              timeout=120, env=env)
    text = help_out.stdout + help_out.stderr
    for option in ("--cout", "--exit-on-end", "--hide-seekbar"):
        if option not in text:
            fail(f"{EXE} --help doesn't list {option} (exit code {help_out.returncode}): a patch is missing, or a "
                 f"library didn't load\n{text[-500:]}")

    gcc = subprocess.run(["gcc", "--version"], capture_output=True, encoding="utf-8").stdout.splitlines()[0]
    system = "Linux"
    os_release = Path("/etc/os-release")
    if os_release.exists():
        system = next((line.split("=", 1)[1].strip('"') for line in os_release.read_text().splitlines()
                       if line.startswith("PRETTY_NAME=")), system)
    tarball = CACHE / "src" / f"ffmpeg-{FFMPEG_VERSION}.tar.xz"
    (stage / "BUILD.txt").write_text("\n".join([
        f"Slippi mainline playback Dolphin, headless ({EXE}), for slp2alpha: Linux {ARCH}",
        f"source: {DOLPHIN_GIT} {COMMIT}",
        "patches: " + ", ".join(p.name for p in sorted(PATCHES.glob("*.patch"))),
        f"FFmpeg: {FFMPEG_VERSION}, built by tools/dolphin-build/build-ffmpeg.sh from {tarball.name}",
        f"compiler: {gcc}",
        f"built on: {system}",
        f"needs: glibc {glibc} or newer, libEGL.so.1, libasound.so.2; and for Vulkan, libvulkan.so.1 and a driver",
        f"built: {datetime.datetime.now().isoformat(timespec='seconds')}",
    ]) + "\n", encoding="utf-8")

    log(f"Copying to {OUT}")
    OUT.mkdir(parents=True, exist_ok=True)
    # Replace only what this step puts there: the folder can also hold another platform's build.
    ours = [EXE, "Sys", "Licenses", "COPYING", "BUILD.txt"]
    ours += [p.name for p in OUT.glob("lib*.so*")]
    for name in ours:
        target = OUT / name
        if target.is_dir() and not target.is_symlink():
            shutil.rmtree(target)
        elif target.exists() or target.is_symlink():
            target.unlink()
    for item in stage.iterdir():
        if item.is_dir():
            shutil.copytree(item, OUT / item.name)
        else:
            shutil.copy2(item, OUT / item.name)
    print(f"Done: {OUT / EXE}")


STEPS = {
    "fetch": [fetch],
    "configure": [fetch, configure],
    "build": [build],
    "bundle": [bundle],
    "all": [fetch, configure, build, bundle],
}


if __name__ == "__main__":
    sys.exit(run_steps(STEPS, sys.argv[1:], Path(__file__).name))
