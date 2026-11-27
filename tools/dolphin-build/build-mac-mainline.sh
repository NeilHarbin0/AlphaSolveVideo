#!/bin/bash
# Native macOS build of Slippi's mainline-based playback Dolphin, headless (NoGUI) with frame dumping.
#
# On Apple Silicon this runs as arm64 with Dolphin's ARM64 JIT and the Metal backend, instead of the
# x86_64 Ishiiruka build under Rosetta (where every PowerPC instruction is translated twice). It has
# no window at all (-p headless), so renders happen in the background.
#
# Source: project-slippi/dolphin, branch fix/mainline-playback (PR #40), pinned below, plus
# tools/dolphin-build/patches-mainline/*.patch (--cout progress markers, frame-dump gating, clang fix,
# --camera-out for the camera export, and Windows fixes: a clean stop on Ctrl+Break, no system zlib).
# build-windows-mainline.py is the Windows counterpart.
#
# Usage: build-mac-mainline.sh [fetch|configure|build|bundle|all]   (default: all)
# Environment:
#   ALPHASOLVE_CACHE   work folder (default ~/Library/Caches/AlphaSolveVideo)
#   OUTPUT_APP         where the finished app is copied
#                      (default <repo>/packages/slippi-playback-mainline/Slippi Dolphin.app)
#   JOBS, NICE         build parallelism and niceness (defaults: all cores, 0)
set -euo pipefail

STEP="${1:-all}"
COMMIT=c5f635948ed43f4d14a72069343e0cecdc117391   # fix/mainline-playback, 2026-06-15
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="${ALPHASOLVE_CACHE:-$HOME/Library/Caches/AlphaSolveVideo}"
SRC="$CACHE/mainline"
BUILD="$SRC/build"
ARCH="$(uname -m)"
FFMPEG_VERSION=8.1.3
FFMPEG="$CACHE/ffmpeg8-$ARCH"
OUTPUT_APP="${OUTPUT_APP:-$REPO_ROOT/packages/slippi-playback-mainline/Slippi Dolphin.app}"
PATCHES="$REPO_ROOT/tools/dolphin-build/patches-mainline"
EXE_NAME=dolphin-emu-nogui
export PATH="$HOME/.cargo/bin:$PATH"

# CMake 4 drops compatibility with the cmake_minimum_required() of several submodules; use the same
# private CMake 3.31 as build-mac-local.sh.
CMAKE="$CACHE/venv-cmake3/bin/cmake"
ensure_cmake3() {
  if [ ! -x "$CMAKE" ]; then
    log "Installing CMake 3.31 into $CACHE/venv-cmake3"
    python3 -m venv "$CACHE/venv-cmake3"
    "$CACHE/venv-cmake3/bin/pip" install -q --disable-pip-version-check "cmake>=3.31,<3.32"
  fi
}

log() { printf '\n== %s\n' "$*"; }

fetch() {
  if [ ! -d "$SRC/.git" ]; then
    log "Fetching Slippi mainline Dolphin $COMMIT"
    git init -q "$SRC"
    git -C "$SRC" remote add origin https://github.com/project-slippi/dolphin.git
  fi
  if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)" != "$COMMIT" ]; then
    git -C "$SRC" fetch -q --depth 1 origin "$COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
  fi
  git -C "$SRC" submodule update --init --recursive --depth 1 --jobs 4
}

apply_patches() {
  # Patches go on in order, so the tree has the first k of them. The last of those has nothing on top, so
  # it reverse-checks on its own (an earlier one may not, once a later patch edits lines next to its own).
  # The rest go on one by one.
  local patches=() p i k=0
  for p in "$PATCHES"/*.patch; do [ -e "$p" ] && patches+=("$p"); done
  for (( i = ${#patches[@]}; i > 0; i-- )); do
    if git -C "$SRC" apply --reverse --check "${patches[i - 1]}" 2>/dev/null; then k=$i; break; fi
  done
  for (( i = 0; i < k; i++ )); do echo "already applied: $(basename "${patches[i]}")"; done
  for p in ${patches[@]+"${patches[@]:k}"}; do
    log "Applying $(basename "$p")"
    git -C "$SRC" apply "$p" || {
      echo "ERROR: $(basename "$p") doesn't apply to $SRC: it has changes the patches don't expect"
      echo "(an older version of a patch, or edits). Undo them, then run this again:"
      echo "  git -C \"$SRC\" checkout -- . && git -C \"$SRC\" clean -fd Source && git -C \"$SRC\" submodule foreach --recursive git checkout -- ."
      exit 1
    }
  done
}

configure() {
  [ -f "$FFMPEG/lib/pkgconfig/libavcodec.pc" ] || \
    "$REPO_ROOT/tools/dolphin-build/build-ffmpeg.sh" "$FFMPEG_VERSION" "$ARCH" "$FFMPEG"
  command -v pkg-config >/dev/null || { echo "pkg-config is required (brew install pkgconf)"; exit 1; }
  local rust_target="$ARCH-apple-darwin"
  [ "$ARCH" = arm64 ] && rust_target=aarch64-apple-darwin
  rustup toolchain list | grep -q '^1\.88\.0' || \
    rustup toolchain install 1.88.0 --profile minimal --component rustfmt --target "$rust_target"
  ensure_cmake3

  log "Configuring ($ARCH, playback, NoGUI only, FFmpeg $FFMPEG_VERSION from $FFMPEG)"
  local gen=()
  command -v ninja >/dev/null && gen=(-G Ninja)
  # Only our FFmpeg is visible to pkg-config, and Homebrew prefixes are ignored, so the app links
  # Dolphin's bundled copies of its dependencies instead of whatever happens to be installed.
  PKG_CONFIG_LIBDIR="$FFMPEG/lib/pkgconfig" PKG_CONFIG_PATH="" \
  "$CMAKE" -S "$SRC" -B "$BUILD" ${gen[@]+"${gen[@]}"} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" \
    -DFFMPEG_DIR="$FFMPEG" \
    -DSLIPPI_PLAYBACK=ON \
    -DENABLE_QT=OFF \
    -DENABLE_NOGUI=ON \
    -DENABLE_VULKAN=OFF \
    -DENABLE_SDL=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_LLVM=OFF \
    -DENABLE_ANALYTICS=OFF \
    -DENABLE_AUTOUPDATE=OFF \
    -DUSE_DISCORD_PRESENCE=OFF \
    -DUSE_SYSTEM_LIBS=OFF \
    -DMACOS_CODE_SIGNING=OFF \
    -DSKIP_POSTPROCESS_BUNDLE=ON \
    -DRust_TOOLCHAIN=1.88.0 \
    2>&1 | tee "$CACHE/mainline-configure.log"
  grep -q "libav/ffmpeg found, enabling AVI frame dumps" "$CACHE/mainline-configure.log" || {
    echo "ERROR: CMake did not find FFmpeg; frame dumping would be disabled."; exit 1; }
}

build() {
  local jobs="${JOBS:-$(sysctl -n hw.ncpu)}"
  log "Building dolphin-nogui with $jobs parallel jobs"
  PKG_CONFIG_LIBDIR="$FFMPEG/lib/pkgconfig" PKG_CONFIG_PATH="" \
    nice -n "${NICE:-0}" "$CMAKE" --build "$BUILD" --target dolphin-nogui -j "$jobs" 2>&1 \
    | tee "$CACHE/mainline-build.log"
}

# Copy every non-system dylib the binary needs into Contents/Frameworks and point the binary at it.
bundle_dylibs() {
  local fw="$1"; shift
  local todo=("$@") bin dep name src
  while [ ${#todo[@]} -gt 0 ]; do
    bin="${todo[0]}"
    todo=(${todo[@]+"${todo[@]:1}"})
    for dep in $(otool -L "$bin" | tail -n +2 | awk '{print $1}'); do
      case "$dep" in /usr/lib/*|/System/*|@executable_path/*|@loader_path/*) continue ;; esac
      name="$(basename "$dep")"
      [ "$(otool -D "$bin" | tail -n +2)" = "$dep" ] && continue   # the library's own id
      if [ ! -f "$fw/$name" ]; then
        src="$dep"
        if [[ "$dep" == @rpath/* ]]; then
          src="$(find "$BUILD" "$FFMPEG/lib" -name "$name" \( -type f -o -type l \) | head -1)"
        fi
        [ -n "$src" ] && [ -e "$src" ] || { echo "ERROR: cannot find $dep (needed by $bin)"; exit 1; }
        cp -L "$src" "$fw/$name"
        chmod u+w "$fw/$name"
        install_name_tool -id "@executable_path/../Frameworks/$name" "$fw/$name" 2>/dev/null
        todo+=("$fw/$name")
      fi
      install_name_tool -change "$dep" "@executable_path/../Frameworks/$name" "$bin" 2>/dev/null
    done
  done
}

bundle() {
  local exe="$BUILD/Binaries/$EXE_NAME"
  [ -x "$exe" ] || { echo "ERROR: $exe not built"; exit 1; }
  local stage="$BUILD/AlphaSolveBundle/Slippi Dolphin.app"
  local contents="$stage/Contents"
  log "Assembling $stage"
  rm -rf "$stage"
  mkdir -p "$contents/MacOS" "$contents/Frameworks" "$contents/Resources"
  cp "$exe" "$contents/MacOS/$EXE_NAME"

  # Dolphin looks for Sys at <bundle>/Contents/Resources/Sys. Playback builds swap the netplay
  # Gecko codes for the playback ones.
  cp -R "$SRC/Data/Sys" "$contents/Resources/Sys"
  cp "$SRC/Data/PlaybackGeckoCodes/GALE01r2.ini" "$contents/Resources/Sys/GameSettings/GALE01r2.ini"
  rm -f "$contents/Resources/Sys/GameSettings/Replace "*.txt

  # LSUIElement: never a Dock icon or menu bar, even if something initialises AppKit.
  cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$EXE_NAME</string>
  <key>CFBundleIdentifier</key><string>com.alphasolvevideo.slippi-playback-mainline</string>
  <key>CFBundleName</key><string>Slippi Dolphin (playback, headless)</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${COMMIT:0:7}</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

  log "Bundling dylibs"
  bundle_dylibs "$contents/Frameworks" "$contents/MacOS/$EXE_NAME"
  ls "$contents/Frameworks"

  log "Checking the result"
  lipo -archs "$contents/MacOS/$EXE_NAME"
  otool -L "$contents/MacOS/$EXE_NAME" | grep -E "libav(codec|format)|libswscale" || {
    echo "ERROR: FFmpeg not linked; frame dumping would be disabled."; exit 1; }
  if otool -L "$contents/MacOS/$EXE_NAME" "$contents/Frameworks/"*.dylib | grep -E "^\s+(/opt/homebrew|/usr/local|$CACHE)"; then
    echo "ERROR: the app still references libraries outside the bundle (above)."; exit 1
  fi
  local help_out
  help_out="$("$contents/MacOS/$EXE_NAME" --help 2>&1 || true)"
  for opt in --cout --exit-on-end --hide-seekbar; do
    echo "$help_out" | grep -q -- "$opt" || {
      echo "ERROR: $EXE_NAME --help does not list $opt"; echo "$help_out"; exit 1; }
  done

  log "Signing (ad hoc) and copying to $OUTPUT_APP"
  for f in "$contents/Frameworks/"*.dylib; do codesign --force --sign - "$f"; done
  codesign --force --sign - "$stage"
  rm -rf "$OUTPUT_APP"
  mkdir -p "$(dirname "$OUTPUT_APP")"
  ditto "$stage" "$OUTPUT_APP"
  echo "Done: $OUTPUT_APP"
}

case "$STEP" in
  fetch)     fetch; apply_patches ;;
  configure) fetch; apply_patches; configure ;;
  build)     build ;;
  bundle)    bundle ;;
  all)       fetch; apply_patches; configure; build; bundle ;;
  *) echo "usage: $0 [fetch|configure|build|bundle|all]"; exit 2 ;;
esac
