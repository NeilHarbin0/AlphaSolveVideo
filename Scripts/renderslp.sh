#!/bin/bash
# Headlessly render a Slippi replay (.slp) on macOS or Linux using pure shell + headless Dolphin + FFmpeg.
#
# Usage: renderslp.sh <replay.slp> [options]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OS="$(uname -s)"

REPLAY=""
STAGE_MODE="nostage"
HUD_MODE="nohud"
OPAQUE_MODE=0
NO_GECKO=0
HIDE_ITEMS=0
HIDE_EFFECTS=0
FORMAT="png"
SCALE=1
RAW_RES=0
ISO_PATH="${MELEE_ISO:-${SLP2ALPHA_ISO:-}}"
DOLPHIN_BIN="${ASV_DOLPHIN:-}"
FFMPEG_BIN="${ASV_FFMPEG:-${ALPHASOLVE_FFMPEG:-}}"
OUT_DIR=""
BACKEND="${ASV_BACKEND:-}"
KEEP_TEMP=0

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <replay.slp> [options]

Options:
  --no-stage       Hide stage and particles; works on all stages (default)
  --stage          Keep stage geometry; removes background on Dream Land and Battlefield
  --no-hud         Hide percents, stocks, timer, name tags, and overlays (default)
  --hud            Keep HUD and overlays
  --opaque         Keep background (no flicker/alpha solve; opaque video on all stages)
  --no-gecko       No AlphaSolve Gecko codes (Slippi playback codes only; opaque video)
  --hide-items     With --no-stage: also hide items and projectiles
  --hide-effects   With --no-stage: also hide effects (sparks, dust, KO blasts...)
  --format EXT     png (default), mov / prores (ProRes 4444), mkv, avi, webm, gif, mp4 (opaque only)
  --scale N        Internal resolution multiplier 1..4 (default: 1)
  --raw            Dump unstretched 640x480*scale instead of aspect-corrected 640x528
  --iso PATH       Melee NTSC 1.02 ISO (or set MELEE_ISO / Slippi Launcher Settings)
  --dolphin PATH   Path to Slippi Dolphin.app or dolphin-emu-nogui
  --ffmpeg PATH    Path to ffmpeg
  --backend NAME   Dolphin backend (default: Metal on macOS, Vulkan on Linux)
  --out DIR        Output directory (default: next to replay)
  --keep           Keep temporary work folder
EOF
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stage)        STAGE_MODE="stage"; shift ;;
    --no-stage)     STAGE_MODE="nostage"; shift ;;
    --hud)          HUD_MODE="hud"; shift ;;
    --no-hud)       HUD_MODE="nohud"; shift ;;
    --opaque)       OPAQUE_MODE=1; shift ;;
    --no-gecko)     OPAQUE_MODE=1; NO_GECKO=1; shift ;;
    --hide-items)   HIDE_ITEMS=1; shift ;;
    --hide-effects) HIDE_EFFECTS=1; shift ;;
    --raw)          RAW_RES=1; shift ;;
    --keep)         KEEP_TEMP=1; shift ;;
    --format)       FORMAT="${2:?--format needs a value}"; shift 2 ;;
    --scale)        SCALE="${2:?--scale needs a value}"; shift 2 ;;
    --iso)          ISO_PATH="${2:?--iso needs a value}"; shift 2 ;;
    --dolphin)      DOLPHIN_BIN="${2:?--dolphin needs a value}"; shift 2 ;;
    --ffmpeg)       FFMPEG_BIN="${2:?--ffmpeg needs a value}"; shift 2 ;;
    --backend)      BACKEND="${2:?--backend needs a value}"; shift 2 ;;
    --out)          OUT_DIR="${2:?--out needs a value}"; shift 2 ;;
    -h|--help)      usage ;;
    -*)             echo "ERROR: Unknown option: $1" >&2; usage ;;
    *)              [ -z "$REPLAY" ] && REPLAY="$1" || { echo "ERROR: Unexpected argument: $1" >&2; usage; }; shift ;;
  esac
done

[ -n "$REPLAY" ] || usage
[ -f "$REPLAY" ] || { echo "ERROR: Replay not found: $REPLAY" >&2; exit 1; }
REPLAY="$(cd "$(dirname "$REPLAY")" && pwd)/$(basename "$REPLAY")"
REPLAY_DIR="$(dirname "$REPLAY")"
REPLAY_STEM="$(basename "$REPLAY")"
REPLAY_STEM="${REPLAY_STEM%.*}"
OUT_DIR="${OUT_DIR:-$REPLAY_DIR}"
mkdir -p "$OUT_DIR"

# Resolve Dolphin executable (supports passing a macOS .app bundle or the binary directly).
resolve_dolphin() {
  local p="$1"
  if [ -d "$p" ] && [ -d "$p/Contents/MacOS" ]; then
    if [ -x "$p/Contents/MacOS/dolphin-emu-nogui" ]; then
      printf '%s\n' "$p/Contents/MacOS/dolphin-emu-nogui"; return 0
    fi
    local first
    first="$(find "$p/Contents/MacOS" -maxdepth 1 -type f -perm -111 | head -1)"
    [ -n "$first" ] && { printf '%s\n' "$first"; return 0; }
  elif [ -x "$p" ]; then
    printf '%s\n' "$p"; return 0
  fi
  return 1
}

if [ -n "$DOLPHIN_BIN" ]; then
  DOLPHIN_EXE="$(resolve_dolphin "$DOLPHIN_BIN")" || { echo "ERROR: Invalid --dolphin: $DOLPHIN_BIN" >&2; exit 1; }
else
  DOLPHIN_EXE=""
  for cand in \
      "$REPO_ROOT/packages/slippi-playback-mainline/Slippi Dolphin.app" \
      "$REPO_ROOT/packages/slippi-playback-mainline/dolphin-emu-nogui" \
      "$REPO_ROOT/dolphin-emu-nogui"; do
    if [ -e "$cand" ] && DOLPHIN_EXE="$(resolve_dolphin "$cand")"; then
      break
    fi
  done
  if [ -z "$DOLPHIN_EXE" ] && command -v dolphin-emu-nogui >/dev/null 2>&1; then
    DOLPHIN_EXE="$(command -v dolphin-emu-nogui)"
  fi
  [ -n "$DOLPHIN_EXE" ] || {
    echo "ERROR: Could not find headless dolphin-emu-nogui in packages/slippi-playback-mainline/" >&2
    exit 1
  }
fi

find_ffmpeg() {
  local cand
  for cand in "$FFMPEG_BIN" "$REPO_ROOT/ffmpeg" "$REPO_ROOT/packages/ffmpeg/ffmpeg" "$REPO_ROOT/packages/ffmpeg/bin/ffmpeg"; do
    [ -n "$cand" ] && [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
  done
  command -v ffmpeg >/dev/null 2>&1 && { command -v ffmpeg; return 0; }
  for cand in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
    [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}
FFMPEG_EXE="$(find_ffmpeg)" || { echo "ERROR: Could not find ffmpeg" >&2; exit 1; }

if [ -z "$ISO_PATH" ]; then
  if [ "$OS" = "Darwin" ]; then
    SETTINGS="$HOME/Library/Application Support/Slippi Launcher/Settings"
  else
    SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/Slippi Launcher/Settings"
  fi
  if [ -f "$SETTINGS" ]; then
    ISO_PATH="$(sed -n 's/.*"isoPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SETTINGS" | head -1)"
  fi
fi
[ -n "$ISO_PATH" ] && [ -f "$ISO_PATH" ] || {
  echo "ERROR: Melee NTSC 1.02 ISO not found. Pass --iso PATH or set MELEE_ISO." >&2
  exit 1
}

if [ -z "$BACKEND" ]; then
  [ "$OS" = "Darwin" ] && BACKEND="Metal" || BACKEND="Vulkan"
fi

if [ "$OPAQUE_MODE" -eq 1 ]; then
  if [ "$NO_GECKO" -eq 1 ]; then
    LABEL="no gecko"
  else
    LABEL="with background"
    [ "$HUD_MODE" = "nohud" ] && LABEL="$LABEL, no HUD"
  fi
else
  [ "$STAGE_MODE" = "nostage" ] && LABEL="no stage" || LABEL="with stage"
  [ "$HUD_MODE" = "nohud" ] && LABEL="$LABEL, no HUD" || LABEL="$LABEL, with HUD"
fi
OUT_NAME="$REPLAY_STEM ($LABEL)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/asv-render-XXXXXX")"
cleanup() {
  if [ "$KEEP_TEMP" -eq 0 ]; then
    rm -rf "$WORK"
  else
    echo "Work folder kept: $WORK"
  fi
}
trap cleanup EXIT

USER_DIR="$WORK/user"
mkdir -p "$USER_DIR/Config" "$USER_DIR/GameSettings"

ENABLE_CHEATS="True"
RES_TYPE=1
[ "$RAW_RES" -eq 1 ] && RES_TYPE=2

cat > "$USER_DIR/Config/Dolphin.ini" <<EOF
[Core]
GFXBackend = $BACKEND
EmulationSpeed = 0
EnableCheats = $ENABLE_CHEATS
[Slippi]
EnableSpectator = False
EnableJukebox = False
SaveReplays = False
[Movie]
DumpFrames = True
DumpFramesSilent = True
[DSP]
Backend = No Audio Output
DumpAudio = False
[Interface]
ConfirmStop = False
UsePanicHandlers = False
OnScreenDisplayMessages = False
[Analytics]
Enabled = False
PermissionAsked = True
EOF

cat > "$USER_DIR/Config/GFX.ini" <<EOF
[Settings]
InternalResolution = $SCALE
AspectRatio = 0
FrameDumpsResolutionType = $RES_TYPE
DumpFormat = mkv
DumpCodec = ffv1
ShowFPS = False
[Hacks]
ImmediateXFBEnable = False
[Hardware]
VSync = False
EOF

{
  echo "[Gecko]"
  for f in "$REPO_ROOT/Resources/Required Codes.txt" "$REPO_ROOT/Resources/Characters Only Codes.txt"; do
    [ -f "$f" ] && tr -d '\r' < "$f" | grep -E '^(\$|[*#]|[0-9A-Fa-f]{8})' || true
  done
  echo "[Gecko_Enabled]"
  if [ "$NO_GECKO" -eq 0 ]; then
    echo '$Increase Input Timing Accuracy'
    if [ "$OPAQUE_MODE" -eq 0 ]; then
      echo '$(EPILEPSY WARNING) Flicker Background Black/White asm v5'
      if [ "$STAGE_MODE" = "nostage" ]; then
        echo '$Hide Stage - Characters Only'
        echo '$Hide Stage Particles'
        echo '$Hide Screen Flash'
        echo "\$Hide Shy Guys (Yoshi's Story)"
        [ "$HIDE_ITEMS" -eq 1 ] && echo '$Hide Items and Projectiles'
        [ "$HIDE_EFFECTS" -eq 1 ] && echo '$Hide Effects'
      else
        echo '$Disable Dreamland Background'
        echo '$Disable Battlefield Background + Particles'
      fi
    fi
    [ "$HUD_MODE" = "nohud" ] && echo '$Hide HUD and Overlays'
  fi
  echo "[Gecko_Disabled]"
  echo '$Optional: Show Player Names'
} > "$USER_DIR/GameSettings/GALE01.ini"

REPLAY_JSON="$(printf '%s' "$REPLAY" | sed 's/\\/\\\\/g; s/"/\\"/g')"
cat > "$WORK/comm.json" <<EOF
{
  "mode": "normal",
  "replay": "$REPLAY_JSON",
  "startFrame": -124,
  "isRealTimeMode": false,
  "shouldResync": true,
  "rollbackDisplayMethod": "off",
  "commandId": "asv-$$"
}
EOF

if [ "$OS" = "Linux" ] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  export EGL_PLATFORM="${EGL_PLATFORM:-surfaceless}"
fi

echo "Rendering $REPLAY_STEM [$LABEL]..."
"$DOLPHIN_EXE" -p headless -e "$ISO_PATH" -i "$WORK/comm.json" -u "$USER_DIR" --hide-seekbar --exit-on-end

DUMP_FILE="$(find "$USER_DIR/Dump/Frames" -maxdepth 1 -type f \( -name '*.mkv' -o -name '*.avi' \) | sort | head -1)"
[ -n "$DUMP_FILE" ] || { echo "ERROR: No frame dump written in $USER_DIR/Dump/Frames" >&2; KEEP_TEMP=1; exit 1; }

if [ "$OPAQUE_MODE" -eq 1 ]; then
  FMT_LOW="$(printf '%s' "$FORMAT" | tr '[:upper:]' '[:lower:]')"
  OUT_EXT="$FMT_LOW"
  [ "$FMT_LOW" = "prores" ] && OUT_EXT="mov"
  [ "$FMT_LOW" = "apng" ] && OUT_EXT="png"
  OUT_FILE="$OUT_DIR/fullOpaque - $OUT_NAME.$OUT_EXT"
  case "$FMT_LOW" in
    mp4)
      "$FFMPEG_EXE" -nostdin -y -v error -stats -i "$DUMP_FILE" -vf "settb=1001/60000,setpts=N" -c:v libx264 -crf 16 -pix_fmt yuv420p "$OUT_FILE" ;;
    mov|prores)
      "$FFMPEG_EXE" -nostdin -y -v error -stats -i "$DUMP_FILE" -vf "settb=1001/60000,setpts=N" -c:v prores_ks -profile:v 4444 -pix_fmt yuv444p10le -vendor apl0 "$OUT_FILE" ;;
    webm)
      "$FFMPEG_EXE" -nostdin -y -v error -stats -i "$DUMP_FILE" -vf "settb=1001/60000,setpts=N" -c:v libvpx-vp9 -crf 10 -b:v 0 -pix_fmt yuv420p "$OUT_FILE" ;;
    gif)
      "$FFMPEG_EXE" -nostdin -y -v error -stats -i "$DUMP_FILE" -vf "settb=1001/60000,setpts=N,split[g1][g2];[g1]palettegen[pal];[g2][pal]paletteuse=dither=none" -r 50 "$OUT_FILE" ;;
    png|apng)
      "$FFMPEG_EXE" -nostdin -y -v error -stats -i "$DUMP_FILE" -vf "settb=1001/60000,setpts=N" -f apng -plays 0 "$OUT_FILE" ;;
    mkv|avi)
      "$FFMPEG_EXE" -nostdin -y -v error -stats -i "$DUMP_FILE" -vf "settb=1001/60000,setpts=N" -c:v ffv1 -pix_fmt bgr0 "$OUT_FILE" ;;
    *)
      echo "ERROR: Unknown format '$FORMAT'" >&2; exit 2 ;;
  esac
else
  ASV_FFMPEG="$FFMPEG_EXE" ASV_OUT_DIR="$OUT_DIR" ASV_OUT_NAME="$OUT_NAME" \
    "$SCRIPT_DIR/alphasolve.sh" "$DUMP_FILE" "$FORMAT"
fi

echo "Done! Output saved in $OUT_DIR"
