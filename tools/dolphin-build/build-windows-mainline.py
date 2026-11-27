#!/usr/bin/env python3
"""Windows build of Slippi's mainline playback Dolphin: headless (NoGUI), with frame dumping and this repo's
patches. The Windows counterpart of build-mac-mainline.sh; docs/plan-windows-mainline.md has the reasoning.

    python tools\\dolphin-build\\build-windows-mainline.py [fetch|configure|build|bundle|all]   (default: all)

Needs Git, Python 3.9 or newer, Rust (rustup), and Visual Studio 2022 or its Build Tools with the "Desktop
development with C++" workload. Any shell works: the script loads the x64 compiler environment (vcvars64.bat)
itself unless cl.exe is already on the PATH. CMake 3.31 and Ninja come from pip, into a venv in the work folder.

The result goes to packages\\slippi-playback-mainline\\ (dolphin-emu-nogui.exe, its DLLs and Sys\\), where
slp2alpha looks for it. The GitHub Actions workflow .github/workflows/dolphin-windows.yml runs this script.

Environment:
  ALPHASOLVE_CACHE   work folder (default %LOCALAPPDATA%\\AlphaSolveVideo). A short one such as C:\\asv keeps the
                     Rust build's paths under Windows' 260-character limit.
  OUTPUT_DIR         where the package goes (default <repo>\\packages\\slippi-playback-mainline)
  JOBS               build parallelism (default: all cores)
"""

from __future__ import annotations

import datetime
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Dict, List, Optional

from mainline_common import (BUILD, CACHE, COMMIT, DOLPHIN_GIT, PATCHES, REPO, RUST, SRC, download, fail, fetch,
                             ensure_rust, log, run_steps, sha256, tee, venv_tools)

# Dolphin's own Windows FFmpeg (the Externals/FFmpeg-bin submodule) can't write Matroska, which slp2alpha records
# in. This is FFmpeg 8.1, as in the macOS build, from BtbN's builds: a month-end one, which they keep for two years.
FFMPEG_URL = ("https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-10-31-12-59/"
              "ffmpeg-n8.1.3-27-g8dca1586f4-win64-lgpl-shared-8.1.zip")
FFMPEG_SHA256 = "5cef7bc48e513f3cee7c881e8b2999d835541edb1846c3e89443a67f8f8556ab"
FFMPEG_LIBS = ("avcodec", "avformat", "avutil", "swresample", "swscale")  # what Dolphin links

OUT = Path(os.environ.get("OUTPUT_DIR") or REPO / "packages" / "slippi-playback-mainline")
FFMPEG_ZIP = CACHE / "downloads" / FFMPEG_URL.rsplit("/", 1)[1]
FFMPEG = CACHE / "ffmpeg-windows" / FFMPEG_ZIP.stem  # the zip's own top folder: bin\, include\, lib\
EXE = "dolphin-emu-nogui.exe"
RUST_DLL = "slippi_rust_extensions.dll"
CMAKE_ARGS = [
    "-G", "Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
    "-DCMAKE_C_COMPILER=cl", "-DCMAKE_CXX_COMPILER=cl",
    "-DSLIPPI_PLAYBACK=ON",
    "-DENABLE_QT=OFF",
    "-DENABLE_NOGUI=ON",
    "-DENABLE_SDL=OFF",
    "-DENABLE_TESTS=OFF",
    "-DENABLE_LLVM=OFF",
    "-DENABLE_ANALYTICS=OFF",
    "-DENABLE_AUTOUPDATE=OFF",
    "-DUSE_DISCORD_PRESENCE=OFF",
    "-DUSE_SYSTEM_LIBS=OFF",
    f"-DRust_TOOLCHAIN={RUST}",
]  # Vulkan stays on (the default): a second backend that runs without a window, besides Direct3D


# ---------------------------------------------------------------- tools
def require_windows() -> None:
    if os.name != "nt":
        fail("this builds the Windows package; on macOS use tools/dolphin-build/build-mac-mainline.sh, "
             "on Linux tools/dolphin-build/build-linux-mainline.py")


def ensure_ffmpeg() -> Path:
    """FFmpeg's headers, import libraries (lib\\*.lib) and DLLs (bin\\), checked against the pinned SHA-256."""
    if all((FFMPEG / "lib" / f"{name}.lib").exists() for name in FFMPEG_LIBS):
        return FFMPEG
    if not FFMPEG_ZIP.exists():
        log(f"Downloading {FFMPEG_ZIP.name}")
        download(FFMPEG_URL, FFMPEG_ZIP)
    digest = sha256(FFMPEG_ZIP)
    if digest != FFMPEG_SHA256:
        FFMPEG_ZIP.unlink()
        fail(f"{FFMPEG_ZIP.name} has SHA-256 {digest}, not {FFMPEG_SHA256}; deleted it, run this again")
    shutil.rmtree(FFMPEG.parent, ignore_errors=True)
    with zipfile.ZipFile(FFMPEG_ZIP) as z:
        z.extractall(FFMPEG.parent)
    if not (FFMPEG / "lib" / "avcodec.lib").exists():
        fail(f"{FFMPEG_ZIP.name} doesn't have the expected lib\\avcodec.lib")
    return FFMPEG


def msvc_env() -> Dict[str, str]:
    """This environment if cl.exe is already on the PATH (a developer prompt, or vs-shell in CI); otherwise the one
    vcvars64.bat sets up, as an "x64 Native Tools Command Prompt" would."""
    env = {k.upper(): v for k, v in os.environ.items()}
    if shutil.which("cl"):
        return env
    installer = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio"
    vswhere = installer / "Installer" / "vswhere.exe"
    install = ""
    if vswhere.exists():
        install = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires",
                                  "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"],
                                 capture_output=True, encoding="utf-8", errors="replace").stdout.strip()
    vcvars = Path(install) / "VC" / "Auxiliary" / "Build" / "vcvars64.bat"
    if not install or not vcvars.exists():
        fail("no Visual Studio C++ compiler found. Install Visual Studio 2022 or its Build Tools with the "
             "\"Desktop development with C++\" workload, or run this from an x64 Native Tools Command Prompt.")
    # As setuptools does: run the batch file, then print the environment it leaves (/u: as UTF-16).
    out = subprocess.check_output(f'cmd /u /c "{vcvars}" && set', stderr=subprocess.STDOUT)
    for line in out.decode("utf-16le", errors="replace").splitlines():
        key, sep, value = line.partition("=")
        if sep and key and " " not in key:
            env[key.upper()] = value
    if not shutil.which("cl", path=env.get("PATH")):
        fail(f"{vcvars} didn't put cl.exe on the PATH")
    return env


def build_env() -> Dict[str, str]:
    env = msvc_env()
    env["PATH"] = str(venv_tools()) + os.pathsep + env.get("PATH", "")
    # CMakeLists.txt points FFMPEG_DIR at the bundled FFmpeg on Windows, which hides -DFFMPEG_DIR; FindFFmpeg.cmake
    # takes this environment variable instead.
    env["FFMPEG_DIR"] = str(ensure_ffmpeg())
    return env


# ---------------------------------------------------------------- configure, build
def configure() -> None:
    require_windows()
    ensure_rust()
    env = build_env()
    log(f"Configuring (playback, NoGUI only, FFmpeg from {env['FFMPEG_DIR']})")
    out = tee(["cmake", "-S", SRC, "-B", BUILD, *CMAKE_ARGS], CACHE / "mainline-configure.log", env)
    if "libav/ffmpeg found, enabling AVI frame dumps" not in out:
        fail("CMake did not find FFmpeg, so frame dumping would be disabled")
    found = [line for line in out.splitlines() if "Found avcodec:" in line]
    if not found or Path(env["FFMPEG_DIR"]).as_posix().lower() not in found[0].replace("\\", "/").lower():
        fail(f"CMake found another FFmpeg than {env['FFMPEG_DIR']}: {found[:1]}")


def build() -> None:
    require_windows()
    env = build_env()
    jobs = os.environ.get("JOBS") or str(os.cpu_count() or 4)
    log(f"Building dolphin-nogui with {jobs} parallel jobs")
    tee(["cmake", "--build", BUILD, "--target", "dolphin-nogui", "-j", jobs], CACHE / "mainline-build.log", env)


# ---------------------------------------------------------------- bundle
def dependents(binary: Path, env: Dict[str, str]) -> List[str]:
    """The DLLs a program or DLL loads, from dumpbin /dependents."""
    out = subprocess.run(["dumpbin", "/nologo", "/dependents", str(binary)], capture_output=True, env=env,
                         encoding="utf-8", errors="replace", check=True).stdout
    return parse_dependents(out)


def parse_dependents(dumpbin_output: str) -> List[str]:
    names = []
    for line in dumpbin_output.splitlines():
        name = line.strip()
        if line.startswith("    ") and name.lower().endswith(".dll") and " " not in name:
            names.append(name)
    return names


def vc_redist(env: Dict[str, str]) -> Optional[Path]:
    """The Visual C++ runtime DLLs that come with the compiler, to ship next to the program."""
    root = env.get("VCTOOLSREDISTDIR")
    folders = sorted(Path(root).glob("x64/Microsoft.VC*.CRT")) if root else []
    return folders[-1] if folders else None


def bundle() -> None:
    require_windows()
    env = msvc_env()
    exe = SRC / "Binary" / "x64" / EXE  # Windows builds put their programs in the source tree (CMakeLists.txt)
    rust_dll = BUILD / "cargo" / "build" / "x86_64-pc-windows-msvc" / "release" / RUST_DLL
    for f in (exe, rust_dll):
        if not f.exists():
            fail(f"{f} isn't built")
    stage = BUILD / "AlphaSolvePackage"
    log(f"Assembling {stage}")
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir(parents=True)
    shutil.copy2(exe, stage)
    shutil.copy2(rust_dll, stage)
    ffmpeg = ensure_ffmpeg()
    for name in FFMPEG_LIBS:
        dlls = sorted((ffmpeg / "bin").glob(f"{name}-*.dll"))
        if len(dlls) != 1:
            fail(f"expected one {name}-*.dll in {ffmpeg / 'bin'}, found {[d.name for d in dlls]}")
        shutil.copy2(dlls[0], stage)
    if b"matroska" not in next(stage.glob("avformat-*.dll")).read_bytes():
        fail("this FFmpeg's avformat has no Matroska muxer, which slp2alpha records in")

    # Dolphin looks for Sys next to the program. Playback builds swap the netplay Gecko codes for the playback ones.
    shutil.copytree(SRC / "Data" / "Sys", stage / "Sys")
    shutil.copy2(SRC / "Data" / "PlaybackGeckoCodes" / "GALE01r2.ini", stage / "Sys" / "GameSettings" / "GALE01r2.ini")
    for placeholder in (stage / "Sys" / "GameSettings").glob("Replace *.txt"):
        placeholder.unlink()
    shutil.copy2(SRC / "COPYING", stage / "COPYING")
    shutil.copytree(SRC / "LICENSES", stage / "Licenses")
    if (ffmpeg / "LICENSE.txt").exists():
        shutil.copy2(ffmpeg / "LICENSE.txt", stage / "Licenses" / "FFmpeg-LICENSE.txt")

    log("Checking the DLLs")
    system32 = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
    redist = vc_redist(env)
    missing = set()
    for binary in sorted(stage.glob("*.exe")) + sorted(stage.glob("*.dll")):
        for dll in dependents(binary, env):
            low = dll.lower()
            if (stage / dll).exists() or low.startswith(("api-ms-win-", "ext-ms-")):
                continue
            if redist and (redist / dll).exists():  # the VC++ runtime: ship it, so it needn't be installed
                shutil.copy2(redist / dll, stage / dll)
                continue
            if not (system32 / dll).exists():
                missing.add(f"{dll} (needed by {binary.name})")
    if missing:
        fail("DLLs that are neither in the package nor in Windows: " + ", ".join(sorted(missing)))
    print("\n".join(sorted(p.name for p in stage.iterdir())))

    log("Checking the program")
    help_out = subprocess.run([str(stage / EXE), "--help"], capture_output=True, encoding="utf-8", errors="replace",
                              timeout=120)
    text = help_out.stdout + help_out.stderr
    for option in ("--cout", "--exit-on-end", "--hide-seekbar"):
        if option not in text:
            fail(f"{EXE} --help doesn't list {option} (exit code {help_out.returncode}): a patch is missing, or a "
                 f"DLL didn't load\n{text[-500:]}")

    cl = subprocess.run(["cl"], capture_output=True, env=env, encoding="utf-8", errors="replace")
    compiler = next((line.strip() for line in (cl.stderr + cl.stdout).splitlines() if "Version" in line), "cl")
    (stage / "BUILD.txt").write_text("\n".join([
        "Slippi mainline playback Dolphin, headless (dolphin-emu-nogui), for slp2alpha",
        f"source: {DOLPHIN_GIT} {COMMIT}",
        "patches: " + ", ".join(p.name for p in sorted(PATCHES.glob("*.patch"))),
        f"FFmpeg: {FFMPEG_ZIP.name} (SHA-256 {FFMPEG_SHA256})",
        f"compiler: {compiler}",
        f"built: {datetime.datetime.now().isoformat(timespec='seconds')}",
    ]) + "\n", encoding="utf-8")

    log(f"Copying to {OUT}")
    shutil.rmtree(OUT, ignore_errors=True)
    shutil.copytree(stage, OUT)
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
