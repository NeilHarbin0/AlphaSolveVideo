#!/bin/bash
# Solve a black/white flicker recording into a transparent video and an alpha map.
# Pure shell + ffmpeg (bash 3.2+ compatible for macOS and Linux).
#
# Usage: alphasolve.sh <video> [format]
#   format: png (default, APNG), mov / prores (ProRes 4444), mkv, avi, webm, gif
# Environment:
#   ASV_FFMPEG / ALPHASOLVE_FFMPEG   path to ffmpeg executable
#   ASV_OUT_DIR                      output directory (default: next to input video)
#   ASV_OUT_NAME                     output base name (default: input file stem)
#   ASV_RATE                         output frame rate (default: 60000/1001)
set -euo pipefail

if [ "$#" -lt 1 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "Usage: $(basename "$0") <video> [png|mov|prores|mkv|avi|webm|gif]" >&2
  exit 2
fi

INPUT_FILE="$1"
[ -f "$INPUT_FILE" ] || { echo "ERROR: File not found: $INPUT_FILE" >&2; exit 1; }

FMT="$(printf '%s' "${2:-png}" | tr '[:upper:]' '[:lower:]')"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RATE="${ASV_RATE:-60000/1001}"

INPUT_DIR="$(cd "$(dirname "$INPUT_FILE")" && pwd)"
INPUT_BASE="$(basename "$INPUT_FILE")"
INPUT_STEM="${INPUT_BASE%.*}"
OUT_DIR="${ASV_OUT_DIR:-$INPUT_DIR}"
OUT_NAME="${ASV_OUT_NAME:-$INPUT_STEM}"
mkdir -p "$OUT_DIR"

find_ffmpeg() {
  local cand
  for cand in "${ASV_FFMPEG:-}" "${ALPHASOLVE_FFMPEG:-}" \
      "$REPO_ROOT/ffmpeg" "$REPO_ROOT/packages/ffmpeg/ffmpeg" "$REPO_ROOT/packages/ffmpeg/bin/ffmpeg"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then
      printf '%s\n' "$cand"; return 0
    fi
  done
  if command -v ffmpeg >/dev/null 2>&1; then
    command -v ffmpeg; return 0
  fi
  for cand in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
    if [ -x "$cand" ]; then
      printf '%s\n' "$cand"; return 0
    fi
  done
  return 1
}

FFMPEG="$(find_ffmpeg)" || { echo "ERROR: Could not find ffmpeg" >&2; exit 1; }

# 1. Detect whether frame 0 is black or white from mean luma of the first 2 frames.
LUMA_OUT="$("$FFMPEG" -nostdin -v error -i "$INPUT_FILE" -frames:v 2 \
  -vf "scale=iw/4:ih/4,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" -f null -)"
FIRST_COLOR="$(printf '%s\n' "$LUMA_OUT" | awk -F= '
  /lavfi\.signalstats\.YAVG=/ { vals[n++] = $2 + 0 }
  END {
    if (n < 2) { print "black"; exit }
    if (vals[0] > vals[1]) print "white"; else print "black"
  }')"

# 2. Detect pair alignment (offset 0 vs offset 1) by checking black>white pixel violations.
select_exprs() {
  local color="$1" off="$2"
  local even='mod(n-1\,2)' odd='mod(n\,2)' blk wht
  if [ "$color" = "black" ]; then blk="$even"; wht="$odd"; else blk="$odd"; wht="$even"; fi
  if [ "$off" = "1" ]; then blk="gt(n\\,0)*$blk"; wht="gt(n\\,0)*$wht"; fi
  SEL_BLK="$blk"
  SEL_WHT="$wht"
}

score_offset() {
  local off="$1"
  select_exprs "$FIRST_COLOR" "$off"
  local graph="[0:v]format=gbrp,split[a][b];[a]select=$SEL_BLK,setpts=N/TB/60[blk];[b]select=$SEL_WHT,setpts=N/TB/60[wht];[blk][wht]blend=all_mode=subtract:shortest=1,format=gray,lut=y='if(gt(val\,16)\,255\,0)',signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-[o]"
  "$FFMPEG" -nostdin -v error -i "$INPUT_FILE" -filter_complex "$graph" -map "[o]" -frames:v 300 -f null - | \
    awk -F= '/lavfi\.signalstats\.YAVG=/ { sum += $2; n++ } END { if (n > 0) printf "%.6f\n", sum / n; else print "999999" }'
}

SCORE0="$(score_offset 0)"
SCORE1="$(score_offset 1)"
OFFSET="$(awk -v s0="$SCORE0" -v s1="$SCORE1" 'BEGIN { if (s1 + 0 < s0 + 0) print 1; else print 0 }')"
select_exprs "$FIRST_COLOR" "$OFFSET"
echo "Detected start=$FIRST_COLOR, pair_offset=$OFFSET (scores: 0=$SCORE0, 1=$SCORE1)"

NUM="${RATE%/*}"
DEN="${RATE#*/}"
[ "$NUM" = "$DEN" ] && DEN=1
RETIME="settb=$DEN/$NUM,setpts=N"

BASE_GRAPH="[0]split=3[a][b][c];[a]select=$SEL_BLK,$RETIME[blk];[b]select=$SEL_WHT,$RETIME[wht];[c]select=$SEL_BLK,$RETIME[blk2];[blk]format=gbrp[v1];[wht]format=gbrp[v2];[v1][v2]blend=all_mode=difference:shortest=1,negate,format=yuv420p[map];[map]split=2[alphaMapUse][mapOut];[alphaMapUse]format=gbrp,extractplanes=r+g+b[ar][ag][ab];[ar][ag]blend=all_mode=lighten[arg];[arg][ab]blend=all_mode=lighten,split=2[am1][am2];[blk2]format=gbrp[dg];"

if [ "$FMT" = "gif" ]; then
  GRAPH="${BASE_GRAPH}[am2]nullsink;[dg][am1]alphamerge,split[g1][g2];[g1]palettegen=reserve_transparent=1[pal1];[g2][pal1]paletteuse=dither=none:alpha_threshold=64[fg];[mapOut]split[m1][m2];[m1]palettegen[pal2];[m2][pal2]paletteuse=dither=none[mapGif]"
  "$FFMPEG" -nostdin -y -v error -stats -i "$INPUT_FILE" -filter_complex "$GRAPH" \
    -map "[fg]" -r 50 "$OUT_DIR/fullTransparent - $OUT_NAME.gif" \
    -map "[mapGif]" -r 50 "$OUT_DIR/alphaMap - $OUT_NAME.gif"
  exit 0
fi

GRAPH="${BASE_GRAPH}[am2]format=gbrp[ag3];[dg][ag3]lut2=c0='if(y,min(255,x*255/y),0)':c1='if(y,min(255,x*255/y),0)':c2='if(y,min(255,x*255/y),0)'[unp];[unp][am1]alphamerge,format=argb[fg]"

has_encoder() {
  "$FFMPEG" -hide_banner -encoders 2>/dev/null | grep -qE "^[[:space:]]*[VAS].*[[:space:]]+$1([[:space:]]|$)"
}

case "$FMT" in
  mov|prores)
    OUT_FG="$OUT_DIR/fullTransparent - $OUT_NAME.mov"
    OUT_MAP="$OUT_DIR/alphaMap - $OUT_NAME.mov"
    if has_encoder prores_videotoolbox; then
      V_ARGS=(-c:v prores_videotoolbox -allow_sw 1 -profile:v 4444 -pix_fmt bgra)
      M_ARGS=(-c:v prores_videotoolbox -allow_sw 1 -profile:v hq -pix_fmt p210le)
    elif has_encoder prores_aw; then
      V_ARGS=(-c:v prores_aw -profile:v 4 -pix_fmt yuva444p10le -vendor apl0)
      M_ARGS=(-c:v prores_aw -profile:v 3 -pix_fmt yuv422p10le -vendor apl0)
    else
      V_ARGS=(-c:v prores_ks -profile:v 4444 -pix_fmt yuva444p10le -alpha_bits 16 -vendor apl0)
      M_ARGS=(-c:v prores_ks -profile:v 4444 -pix_fmt yuv444p10le -vendor apl0)
    fi
    ;;
  mkv)
    OUT_FG="$OUT_DIR/fullTransparent - $OUT_NAME.mkv"
    OUT_MAP="$OUT_DIR/alphaMap - $OUT_NAME.mkv"
    V_ARGS=(-c:v ffv1 -pix_fmt bgra)
    M_ARGS=(-c:v ffv1 -pix_fmt gray)
    ;;
  avi)
    OUT_FG="$OUT_DIR/fullTransparent - $OUT_NAME.avi"
    OUT_MAP="$OUT_DIR/alphaMap - $OUT_NAME.avi"
    V_ARGS=(-c:v ffv1 -pix_fmt yuva420p)
    M_ARGS=(-c:v ffv1 -pix_fmt yuva420p)
    ;;
  webm)
    OUT_FG="$OUT_DIR/fullTransparent - $OUT_NAME.webm"
    OUT_MAP="$OUT_DIR/alphaMap - $OUT_NAME.webm"
    V_ARGS=(-c:v libvpx-vp9 -lossless 1 -pix_fmt yuva420p)
    M_ARGS=(-c:v libvpx-vp9 -lossless 1 -pix_fmt yuv420p)
    ;;
  png|apng)
    OUT_FG="$OUT_DIR/fullTransparent - $OUT_NAME.png"
    OUT_MAP="$OUT_DIR/alphaMap - $OUT_NAME.png"
    V_ARGS=(-f apng -plays 0)
    M_ARGS=(-f apng -plays 0)
    ;;
  *)
    echo "ERROR: Unknown format '$FMT' (choose png, mov, prores, mkv, avi, webm, gif)" >&2
    exit 2
    ;;
esac

"$FFMPEG" -nostdin -y -v error -stats -i "$INPUT_FILE" -filter_complex "$GRAPH" \
  -map "[fg]" "${V_ARGS[@]}" "$OUT_FG" \
  -map "[mapOut]" "${M_ARGS[@]}" "$OUT_MAP"
