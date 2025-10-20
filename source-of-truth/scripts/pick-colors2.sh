#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="$HOME/.config/source-of-truth/logs"
LOG_FILE="$LOG_DIR/pick-colors.log"
mkdir -p "$LOG_DIR"

log() { echo "[$(date +'%F %T')] $1" | tee -a "$LOG_FILE"; }

log "[INFO] Starting wallpaper and color update process..."

WALLPAPER_DIR="$HOME/.config/source-of-truth/wallpapers"
WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" \) | shuf -n 1)

if [[ -z "$WALLPAPER" ]]; then
  log "[ERROR] No wallpaper found in $WALLPAPER_DIR"
  exit 1
fi

log "[INFO] Selected wallpaper: $WALLPAPER"

# Extract colors using ImageMagick (IMv7+)
log "[DEBUG] Extracting colors from $WALLPAPER..."
if COLORS=$(magick "$WALLPAPER" -resize 8x1! -depth 8 txt:- 2>/dev/null); then
  BG=$(echo "$COLORS" | awk 'NR==2 {print $3}')
  ACCENT=$(echo "$COLORS" | awk 'NR==3 {print $3}')
else
  log "[WARN] Color extraction failed, using fallback colors..."
  BG="#222222"
  ACCENT="#555555"
fi

log "[INFO] Colors extracted:"
log "BG=$BG"
log "ACCENT=$ACCENT"

# Save environment colors
COLORS_FILE="$HOME/.config/source-of-truth/colors.env"
cat > "$COLORS_FILE" <<EOF
BG=$BG
ACCENT=$ACCENT
FG=#FFFFFF
WARN=#F38BA8
SUCCESS=#A6E3A1
MAGIC=#EBCB8B
EOF

log "[INFO] Colors saved to $COLORS_FILE"

# --- SWWW WALLPAPER SETTING ---
log "[DEBUG] Checking if swww daemon is running..."
if ! pgrep -x swww >/dev/null 2>&1; then
  log "[WARN] swww daemon not running, starting..."
  swww init &
  sleep 1
fi

# Set wallpaper with transition
log "[INFO] Setting wallpaper via swww..."
swww img "$WALLPAPER" \
  --transition-type grow \
  --transition-pos 0.5,0.5 \
  --transition-fps 60 \
  --transition-bezier 0.4,0.0,0.2,1 \
  --transition-duration 1.5 \
  2>&1 | tee -a "$LOG_FILE"

log "[SUCCESS] Wallpaper set successfully with swww"
log "[DONE] Process completed successfully."
log "[LOG] Log saved to $LOG_FILE"
