#!/bin/bash
# Builds a minimal FFmpeg (shared libraries) with just what Dolphin's frame dumper needs.
#
# Usage: build-ffmpeg.sh VERSION ARCH PREFIX
#   VERSION  e.g. 4.4.8 (Ishiiruka) or 8.1.3 (Slippi mainline Dolphin)
#   ARCH     x86_64 or arm64 on macOS; on Linux the machine's own (x86_64 or aarch64)
#   PREFIX   install folder
set -euo pipefail

VERSION="${1:?version}"
ARCH="${2:?arch}"
PREFIX="${3:?prefix}"
OS="$(uname -s)"
if [ "$OS" = Darwin ]; then
  CACHE="${ALPHASOLVE_CACHE:-$HOME/Library/Caches/AlphaSolveVideo}"
  JOBS="$(sysctl -n hw.ncpu)"
else
  CACHE="${ALPHASOLVE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/AlphaSolveVideo}"
  JOBS="$(nproc)"
fi
MIN_MACOS="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
MAJOR="${VERSION%%.*}"

# SHA-256 of ffmpeg.org's release tarballs, for the versions the build scripts use.
case "$VERSION" in
  4.4.8) SHA256=c73848c4ae283d9eaee7be3b276affbc3543380483555500d0dd2c9b7e1c39c3 ;;
  8.1.3) SHA256=7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3 ;;
  *) SHA256= ;;
esac
sha256_of() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

mkdir -p "$CACHE/src"
cd "$CACHE/src"
if [ ! -f "ffmpeg-$VERSION.tar.xz" ]; then
  curl -fL --retry 3 -o "ffmpeg-$VERSION.tar.xz.part" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
  mv "ffmpeg-$VERSION.tar.xz.part" "ffmpeg-$VERSION.tar.xz"
fi
GOT="$(sha256_of "ffmpeg-$VERSION.tar.xz")"
if [ -z "$SHA256" ]; then
  echo "Note: no SHA-256 is pinned for FFmpeg $VERSION; this tarball's is $GOT"
elif [ "$GOT" != "$SHA256" ]; then
  rm -f "ffmpeg-$VERSION.tar.xz"
  echo "ERROR: ffmpeg-$VERSION.tar.xz has SHA-256 $GOT, not $SHA256; deleted it, run this again"
  exit 1
fi
rm -rf "ffmpeg-$VERSION-$ARCH"
mkdir "ffmpeg-$VERSION-$ARCH"
tar xf "ffmpeg-$VERSION.tar.xz" -C "ffmpeg-$VERSION-$ARCH" --strip-components 1
cd "ffmpeg-$VERSION-$ARCH"

CROSS=()
FLAGS=()
ASM=()
if [ "$OS" = Darwin ]; then
  if [ "$(uname -m)" != "$ARCH" ]; then
    CROSS=(--arch="$ARCH" --target-os=darwin --enable-cross-compile --cc="clang -arch $ARCH" --cxx="clang++ -arch $ARCH")
  fi
  FLAGS=(--extra-cflags="-arch $ARCH -mmacosx-version-min=$MIN_MACOS"
         --extra-ldflags="-arch $ARCH -mmacosx-version-min=$MIN_MACOS")
  if [ "$ARCH" = "x86_64" ]; then ASM=(--disable-x86asm); fi   # avoids needing nasm; the dump path barely uses SIMD
elif [ "$(uname -m)" != "$ARCH" ]; then
  echo "ERROR: this builds FFmpeg for the machine's own architecture ($(uname -m)) on Linux, not $ARCH"
  exit 1
elif [ "$ARCH" = "x86_64" ] && ! command -v nasm >/dev/null; then
  echo "Note: nasm isn't installed, so FFmpeg's x86 assembly is left out (sudo apt install nasm keeps it)"
  ASM=(--disable-x86asm)
fi

# Ishiiruka (FFmpeg 4.4) doesn't need swresample; mainline Dolphin's CMake requires it.
RESAMPLE=(--disable-swresample)
if [ "$MAJOR" -ge 5 ]; then RESAMPLE=(--enable-swresample); fi
POSTPROC=(--disable-postproc)
if [ "$MAJOR" -ge 8 ]; then POSTPROC=(); fi   # libpostproc was removed from FFmpeg 8

# ${arr[@]+"${arr[@]}"} keeps bash 3.2 (macOS /bin/bash) happy with empty arrays under set -u
./configure --prefix="$PREFIX" ${CROSS[@]+"${CROSS[@]}"} ${ASM[@]+"${ASM[@]}"} ${FLAGS[@]+"${FLAGS[@]}"} \
  --enable-shared --disable-static --enable-pic \
  --disable-programs --disable-doc --disable-autodetect \
  --disable-avdevice --disable-avfilter ${POSTPROC[@]+"${POSTPROC[@]}"} "${RESAMPLE[@]}" \
  --disable-everything \
  --enable-encoder=ffv1,utvideo,mpeg4 \
  --enable-muxer=avi,matroska,mov \
  --enable-protocol=file

make -j"$JOBS"
make install

echo "Installed FFmpeg $VERSION ($ARCH) to $PREFIX"
if [ "$OS" = Darwin ]; then
  lipo -archs "$PREFIX/lib/libavcodec.dylib"
else
  ls "$PREFIX/lib/"*.so.*
fi
