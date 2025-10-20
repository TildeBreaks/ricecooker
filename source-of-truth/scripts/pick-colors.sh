#!/usr/bin/env bash
set -euo pipefail

# pick-colors.sh (palette-aware with workspace accents + rune hints)
# - Picks wallpaper, extracts palette (ImageMagick optional)
# - Writes colors.env + palette.json
# - Generates Waybar-safe CSS that:
#     * sets a readable bar overlay
#     * creates module pill backgrounds
#     * emits workspace-child selectors with two distinct palette-derived colors:
#         - focused workspace accent (ACCENT_ACTIVE)
#         - inactive workspace accent (ACCENT_INACTIVE)
#     * includes decorative rune glyphs using pseudo-elements (best-effort — harmless if unsupported)
# - Validates CSS against a conservative blacklist to avoid Waybar parser crashes
# - Atomically installs style.css, restarts waybar.service, applies wallpaper via swww/feh
#
# Install:
#   Save to ~/.config/source-of-truth/scripts/pick-colors.sh
#   chmod +x ~/.config/source-of-truth/scripts/pick-colors.sh
#   ~/.config/source-of-truth/scripts/pick-colors.sh

WALLPAPER_DIR="${HOME}/.config/source-of-truth/wallpapers"
OUT_DIR="${HOME}/.config/source-of-truth"
SCRIPTS_DIR="${OUT_DIR}/scripts"
COLOR_FILE="${OUT_DIR}/colors.env"
PALETTE_JSON="${OUT_DIR}/palette.json"
WAYBAR_CSS_DIR="${HOME}/.config/waybar"
WAYBAR_CSS="${WAYBAR_CSS_DIR}/style.css"
TMP_CSS="${WAYBAR_CSS_DIR}/style.css.tmp"
BACKUP_DIR="${OUT_DIR}/backups"
PALETTE_COUNT=8
MIN_CONTRAST_TEXT=4.5
MODULE_BG_ALPHA=0.14
MODULE_HOVER_ALPHA=0.24
BAR_OVERLAY_ALPHA_DARK=0.62
BAR_OVERLAY_ALPHA_LIGHT=0.18

mkdir -p "$OUT_DIR" "$WAYBAR_CSS_DIR" "$BACKUP_DIR" "$SCRIPTS_DIR"

# ---------- helpers ----------
sanitize_hex() {
  local h="${1##\#}"; h="${h,,}"
  if [[ ${#h} -eq 3 ]]; then
    printf "%s%s%s%s%s%s" "${h:0:1}" "${h:0:1}" "${h:1:1}" "${h:1:1}" "${h:2:1}" "${h:2:1}"
  else
    printf "%s" "$h"
  fi
}

hex_to_rgb() {
  local h; h=$(sanitize_hex "$1")
  printf "%d,%d,%d" "$((16#${h:0:2}))" "$((16#${h:2:2}))" "$((16#${h:4:2}))"
}

mix_hex() {
  awk -v a="$1" -v b="$2" -v w="$3" 'BEGIN{
    if (substr(a,1,1)=="#") a=substr(a,2);
    if (substr(b,1,1)=="#") b=substr(b,2);
    r1=strtonum("0x"substr(a,1,2)); g1=strtonum("0x"substr(a,3,2)); b1=strtonum("0x"substr(a,5,2));
    r2=strtonum("0x"substr(b,1,2)); g2=strtonum("0x"substr(b,3,2)); b2=strtonum("0x"substr(b,5,2));
    rf=(w*r1 + (1-w)*r2); gf=(w*g1 + (1-w)*g2); bf=(w*b1 + (1-w)*b2);
    printf "%02x%02x%02x", int(rf+0.5), int(gf+0.5), int(bf+0.5);
  }'
}

invert_hex() {
  awk -v h="$1" 'BEGIN{
    if (substr(h,1,1)=="#") h=substr(h,2);
    r=255-strtonum("0x"substr(h,1,2));
    g=255-strtonum("0x"substr(h,3,2));
    b=255-strtonum("0x"substr(h,5,2));
    printf "%02x%02x%02x", r, g, b;
  }'
}

brightness() {
  local h; h=$(sanitize_hex "$1")
  local r g b
  r=$((16#${h:0:2})); g=$((16#${h:2:2})); b=$((16#${h:4:2}))
  awk -v R="$r" -v G="$g" -v B="$b" 'BEGIN{printf "%.0f", (0.299*R + 0.587*G + 0.114*B)}'
}

contrast_ratio() {
  local h1="${1##\#}" h2="${2##\#}"
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<PY "$h1" "$h2"
import sys
h1=sys.argv[1]; h2=sys.argv[2]
def to_lin(h):
    r=int(h[0:2],16)/255.0; g=int(h[2:4],16)/255.0; b=int(h[4:6],16)/255.0
    def lin(c): return c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*lin(r)+0.7152*lin(g)+0.0722*lin(b)
L1=to_lin(h1); L2=to_lin(h2)
if L1 < L2: L1, L2 = L2, L1
print("{:.4f}".format((L1+0.05)/(L2+0.05)))
PY
    return
  fi
  awk -v h1="$h1" -v h2="$h2" 'BEGIN{
    function lin_comp(c){ return (c <= 0.03928) ? c/12.92 : exp(2.4*log((c+0.055)/1.055)) }
    r1=strtonum("0x"substr(h1,1,2))/255; g1=strtonum("0x"substr(h1,3,2))/255; b1=strtonum("0x"substr(h1,5,2))/255;
    r2=strtonum("0x"substr(h2,1,2))/255; g2=strtonum("0x"substr(h2,3,2))/255; b2=strtonum("0x"substr(h2,5,2))/255;
    L1=0.2126*lin_comp(r1) + 0.7152*lin_comp(g1) + 0.0722*lin_comp(b1);
    L2=0.2126*lin_comp(r2) + 0.7152*lin_comp(g2) + 0.0722*lin_comp(b2);
    if (L1 < L2) { tmp=L1; L1=L2; L2=tmp }
    printf "%.4f\n", (L1+0.05)/(L2+0.05)
  }'
}

# ---------- pick wallpaper ----------
WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0 | shuf -z -n1 | tr -d '\0' || true)
if [[ -z "$WALLPAPER" ]]; then
  echo "[ERROR] No wallpapers in $WALLPAPER_DIR"
  exit 1
fi
echo "[INFO] Selected wallpaper: $WALLPAPER"

# ---------- ImageMagick palette extraction ----------
IMAGEMAGICK=""
if command -v magick >/dev/null 2>&1; then IMAGEMAGICK="magick"
elif command -v convert >/dev/null 2>&1; then IMAGEMAGICK="convert"; fi

BG="222222"; FG="ffffff"; ACCENT1="ffffff"; ACCENT2="000000"; SUBTLE="777777"; HIGHLIGHT="ffffff"
declare -a uniq_palette=()

if [[ -n "$IMAGEMAGICK" ]]; then
  palette_raw=$("$IMAGEMAGICK" "$WALLPAPER" -scale 200x200\! +dither -colors "$PALETTE_COUNT" -colorspace RGB -format "%c" histogram:info:- 2>/dev/null || true)
  if [[ -n "$palette_raw" ]]; then
    mapfile -t palette_lines < <(printf "%s\n" "$palette_raw" | sed -nE 's/^[[:space:]]*([0-9]+):.*#([0-9A-Fa-f]{3,6}).*$/\1 #\2/p' | sort -nr)
    declare -A seen
    for ln in "${palette_lines[@]:-}"; do
      hex=$(awk '{print $2}' <<<"$ln")
      hex=$(sanitize_hex "$hex")
      if [[ -z "${seen[$hex]:-}" ]]; then
        uniq_palette+=("$hex")
        seen[$hex]=1
      fi
    done
  fi
fi

# choose BG
if [[ ${#uniq_palette[@]} -ge 1 ]]; then
  BG="${uniq_palette[0]}"
else
  if [[ -n "$IMAGEMAGICK" ]]; then
    raw=$("$IMAGEMAGICK" "$WALLPAPER" -scale 1x1\! -format "%[hex:p{0,0}]" info: 2>/dev/null || true)
    BG=$(sanitize_hex "${raw##\#}")
  fi
fi
if ! [[ "$BG" =~ ^[0-9a-f]{6}$ ]]; then BG="222222"; fi

# choose FG (contrast)
r_white=$(contrast_ratio "$BG" "ffffff")
r_black=$(contrast_ratio "$BG" "000000")
if awk -v a="$r_white" -v b="$r_black" 'BEGIN{print (a>=b?1:0)}' | grep -q 1; then
  FG="ffffff"; FG_CONTRAST="$r_white"
else
  FG="000000"; FG_CONTRAST="$r_black"
fi

if awk -v c="$FG_CONTRAST" -v t="$MIN_CONTRAST_TEXT" 'BEGIN{print (c < t ? 1 : 0)}' | grep -q 1; then
  inv=$(invert_hex "$BG")
  inv_contrast=$(contrast_ratio "$BG" "$inv")
  if awk -v a="$inv_contrast" -v b="$FG_CONTRAST" 'BEGIN{print (a>b?1:0)}' | grep -q 1; then
    FG="$inv"; FG_CONTRAST="$inv_contrast"
  else
    blended_white=$(mix_hex "$BG" "ffffff" 0.7)
    blended_black=$(mix_hex "$BG" "000000" 0.7)
    bw_contrast=$(contrast_ratio "$BG" "$blended_white")
    bb_contrast=$(contrast_ratio "$BG" "$blended_black")
    if awk -v a="$bw_contrast" -v b="$bb_contrast" 'BEGIN{print (a>=b?1:0)}' | grep -q 1; then
      FG="$blended_white"; FG_CONTRAST="$bw_contrast"
    else
      FG="$blended_black"; FG_CONTRAST="$bb_contrast"
    fi
  fi
fi

# choose accents from palette
ACCENT1=""; ACCENT2=""; BEST_ACC1_RATIO=0; BEST_ACC2_RATIO=0
if [[ ${#uniq_palette[@]} -gt 0 ]]; then
  for c in "${uniq_palette[@]}"; do
    [[ "$c" == "$BG" ]] && continue
    r=$(contrast_ratio "$BG" "$c")
    if awk -v val="$r" -v th="$MIN_CONTRAST_TEXT" 'BEGIN{print (val>=th?1:0)}' | grep -q 1; then
      if awk -v a="$r" -v b="$BEST_ACC1_RATIO" 'BEGIN{print (a>b?1:0)}' | grep -q 1; then
        ACCENT2="$ACCENT1"; BEST_ACC2_RATIO="$BEST_ACC1_RATIO"
        ACCENT1="$c"; BEST_ACC1_RATIO="$r"
      fi
    else
      if awk -v a="$r" -v b="$BEST_ACC2_RATIO" 'BEGIN{print (a>b?1:0)}' | grep -q 1; then
        if [[ -z "$ACCENT1" ]]; then ACCENT1="$c"; BEST_ACC1_RATIO="$r"; else ACCENT2="$c"; BEST_ACC2_RATIO="$r"; fi
      fi
    fi
  done
fi

if [[ -z "$ACCENT1" ]]; then
  if awk -v a="$r_white" -v b="$r_black" 'BEGIN{print (a>=b?1:0)}' | grep -q 1; then ACCENT1="ffffff"; else ACCENT1="000000"; fi
fi
if [[ -z "$ACCENT2" ]]; then ACCENT2=$([[ "$ACCENT1" == "ffffff" ]] && echo "000000" || echo "ffffff"); fi
if [[ "$ACCENT1" == "$BG" ]]; then ACCENT1=$(invert_hex "$BG"); fi
if [[ "$ACCENT2" == "$BG" ]]; then ACCENT2=$(mix_hex "$BG" "ffffff" 0.6); fi

SUBTLE=$(mix_hex "$BG" "$ACCENT1" 0.2)
HIGHLIGHT=$(mix_hex "$ACCENT1" "$FG" 0.6)

BG=$(sanitize_hex "$BG"); FG=$(sanitize_hex "$FG"); ACCENT1=$(sanitize_hex "$ACCENT1")
ACCENT2=$(sanitize_hex "$ACCENT2"); SUBTLE=$(sanitize_hex "$SUBTLE"); HIGHLIGHT=$(sanitize_hex "$HIGHLIGHT")

echo "[INFO] Palette chosen: BG=#${BG}, FG=#${FG}, ACCENT1=#${ACCENT1}, ACCENT2=#${ACCENT2}"

# write colors
cat > "$COLOR_FILE" <<EOF
# Auto-generated by pick-colors.sh
# Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
export BG="${BG}"
export FG="${FG}"
export ACCENT1="${ACCENT1}"
export ACCENT2="${ACCENT2}"
export SUBTLE="${SUBTLE}"
export HIGHLIGHT="${HIGHLIGHT}"
EOF
echo "[INFO] Wrote $COLOR_FILE"

# write palette.json
cat > "$PALETTE_JSON" <<EOF
{
  "bg": "#${BG}",
  "fg": "#${FG}",
  "accent1": "#${ACCENT1}",
  "accent2": "#${ACCENT2}",
  "subtle": "#${SUBTLE}",
  "highlight": "#${HIGHLIGHT}",
  "source": "$(basename "$WALLPAPER")"
}
EOF
echo "[INFO] Wrote $PALETTE_JSON"

# ---------- workspace accent colors ----------
# ACCENT_ACTIVE: solid-ish accent for focused workspace
# ACCENT_INACTIVE: muted accent for non-focused workspaces
ACCENT_ACTIVE="#${ACCENT1}"
# Create a slightly darker/muted inactive color by mixing ACCENT2 and BG
ACCENT_INACTIVE="$(mix_hex "$ACCENT2" "$BG" 0.55)"

ACCENT_ACTIVE_RGB=$(hex_to_rgb "${ACCENT1}")
ACCENT_INACTIVE_RGB=$(hex_to_rgb "${ACCENT_INACTIVE}")

MODULE_BG="rgba(${ACCENT_ACTIVE_RGB},${MODULE_BG_ALPHA})"
MODULE_HOVER_BG="rgba(${ACCENT_ACTIVE_RGB},${MODULE_HOVER_ALPHA})"
SUBTLE_RGB=$(hex_to_rgb "$SUBTLE")
SUBTLE_BG="rgba(${SUBTLE_RGB},${MODULE_BG_ALPHA})"

# choose bar overlay
BRIGHTNESS=$(brightness "$BG")
if [[ "$BRIGHTNESS" -lt 128 ]]; then
  BAR_OVERLAY="rgba(0,0,0,${BAR_OVERLAY_ALPHA_DARK})"
else
  BAR_OVERLAY="rgba(255,255,255,${BAR_OVERLAY_ALPHA_LIGHT})"
fi

# ---------- generate CSS ----------
cat > "$TMP_CSS" <<EOF
/* AUTO-GENERATED by pick-colors.sh - palette aware (rune theme) */
#waybar {
    background: ${BAR_OVERLAY};
    color: #${FG};
    font-family: "JetBrains Mono", monospace;
    font-size: 14px;
    padding: 6px 10px;
}

/* default color for all descendants */
#waybar, #waybar * {
    color: #${FG};
    background: transparent;
}

/* workspace container */
#custom-hypr-workspaces {
    padding-left: 6px;
    margin-right: 8px;
}

/* workspace child elements (JSON-mode) */
#custom-hypr-workspaces > .workspace {
    color: #${ACCENT2};
    background: rgba(${ACCENT_INACTIVE_RGB},0.14);
    padding: 4px 10px;
    border-radius: 10px;
    font-weight: 700;
    margin-right: 8px;
    border: none;
    letter-spacing: 0.6px;
}

/* focused workspace accent */
#custom-hypr-workspaces > .workspace.focused {
    color: #${BG};
    background-color: ${ACCENT_ACTIVE};
}

/* occupied but not focused */
#custom-hypr-workspaces > .workspace.occupied {
    background: rgba(${ACCENT_INACTIVE_RGB},0.22);
}

/* urgent */
#custom-hypr-workspaces > .workspace.urgent {
    color: #ffffff;
    background-color: rgba(200,60,60,0.95);
}

/* decorative runes (best-effort). If pseudo-elements are unsupported you will simply not see them. */
#custom-hypr-workspaces > .workspace::before {
    content: "᚛";
    margin-right: 6px;
    opacity: 0.9;
    color: #${SUBTLE};
}

/* focused rune variant */
#custom-hypr-workspaces > .workspace.focused::before {
    content: "᚜";
    color: #${HIGHLIGHT};
}

/* hover */
#custom-hypr-workspaces > .workspace:hover {
    color: #${BG};
    background-color: rgba(${ACCENT_ACTIVE_RGB},0.26);
}

/* module pills */
.module, .modules-left > .module, .modules-center > .module, .modules-right > .module {
    background: ${MODULE_BG};
    color: #${FG};
    padding: 6px 10px;
    border-radius: 8px;
    margin-left: 6px;
    margin-right: 6px;
}
.module * { color: inherit; background: transparent; }

/* icons/text accent */
#clock, #pulseaudio, #wp-button, .module .icon {
    color: #${ACCENT2};
}

/* hover states for modules */
#wp-button:hover, .module:hover {
    color: #${BG};
    background-color: ${MODULE_HOVER_BG};
}

/* rune-like separators using subtle color */
.separator {
    border-left: 1px solid #${SUBTLE};
    margin: 0 6px;
}

/* small "engraving" lines near left/right edges to hint at a carved bar look */
#waybar::before, #waybar::after {
    /* best-effort; harmless if unsupported */
    content: "";
    display: inline-block;
}
EOF

# sanitize tmp CSS (BOM/CRLF/utf-8 control chars)
if head -c 3 "$TMP_CSS" | hexdump -v -e '3/1 "%02x" "\n"' | grep -qi '^efbbbf'; then
  tail -c +4 "$TMP_CSS" > "${TMP_CSS}.nobom" && mv "${TMP_CSS}.nobom" "$TMP_CSS"
fi
if grep -U $'\r' -q "$TMP_CSS" 2>/dev/null || file -bi "$TMP_CSS" | grep -qi "crlf"; then
  sed -i 's/\r$//' "$TMP_CSS"
fi
if command -v iconv >/dev/null 2>&1; then
  iconv -f utf-8 -t utf-8 -c "$TMP_CSS" -o "${TMP_CSS}.clean" && mv "${TMP_CSS}.clean" "$TMP_CSS"
fi
perl -0777 -pe 's/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]//g' -i "$TMP_CSS" >/dev/null 2>&1 || true

# ---------- conservative blacklist check ----------
DISALLOWED_REGEX='(^|[:space])(display|gap|width|height|min-height|vertical-align|align-items|justify-content|float|position|left:|right:|top:|bottom:|overflow|flex|grid)[:space]*:'
if grep -Eiq "$DISALLOWED_REGEX" "$TMP_CSS"; then
  echo "[ERROR] Generated CSS contains properties Waybar rejects; aborting install."
  echo "[INFO] Offending lines:"
  grep -niE "$DISALLOWED_REGEX" "$TMP_CSS" || true
  echo "[INFO] Tmp CSS preserved at $TMP_CSS for inspection."
  exit 1
fi

# basic validation
open_braces=$(grep -o '{' "$TMP_CSS" | wc -l || true)
close_braces=$(grep -o '}' "$TMP_CSS" | wc -l || true)
if [[ "$open_braces" -ne "$close_braces" ]]; then
  echo "[ERROR] Unbalanced braces in generated CSS; aborting."
  exit 1
fi
if ! grep -q '#waybar[[:space:]]*{' "$TMP_CSS"; then
  echo "[ERROR] Generated CSS missing '#waybar {' at top; aborting."
  exit 1
fi

# atomic install
if [[ -f "$WAYBAR_CSS" ]]; then
  ts=$(date -u +"%Y%m%dT%H%M%SZ")
  cp -v "$WAYBAR_CSS" "${BACKUP_DIR}/style.css.${ts}.bak"
fi
mv -v "$TMP_CSS" "$WAYBAR_CSS"
echo "[INFO] Installed new Waybar CSS at $WAYBAR_CSS"

# compatibility symlink for underscored script name
SCRIPT_ABS=$(realpath "$0" 2>/dev/null || printf "%s" "$0")
ln -sf "$SCRIPT_ABS" "${SCRIPTS_DIR}/pick_colors.sh" || true

# restart waybar (systemd --user preferred)
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  if systemctl --user is-active --quiet waybar.service; then
    systemctl --user restart waybar.service || echo "[WARN] systemctl restart failed"
  else
    systemctl --user start waybar.service || echo "[WARN] systemctl start failed"
  fi
else
  if pgrep -x waybar >/dev/null 2>&1; then
    pkill -USR1 -x waybar || true
  else
    if command -v waybar >/dev/null 2>&1; then
      : "${XDG_RUNTIME_DIR:="/run/user/$(id -u)"}"
      export XDG_RUNTIME_DIR
      : "${WAYLAND_DISPLAY:="wayland-0"}"
      export WAYLAND_DISPLAY
      setsid waybar >"${HOME}/.cache/pick-colors-waybar.log" 2>&1 </dev/null &
      sleep 0.5
    fi
  fi
fi

# apply wallpaper via swww or feh
if command -v swww >/dev/null 2>&1; then
  swww img "$WALLPAPER" --transition-type any --transition-duration 1 >/dev/null 2>&1 || echo "[WARN] swww failed"
elif command -v feh >/dev/null 2>&1; then
  feh --bg-scale "$WALLPAPER" >/dev/null 2>&1 || echo "[WARN] feh failed"
fi

echo "[INFO] pick-colors operation complete."
