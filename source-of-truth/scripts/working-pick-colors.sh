#!/usr/bin/env bash
set -euo pipefail

# Paths
WALLPAPER_DIR="$HOME/.config/source-of-truth/wallpapers"
COLOR_FILE="$HOME/.config/source-of-truth/colors.env"
WAYBAR_CSS="$HOME/.config/waybar/style.css"

# Pick a random wallpaper
WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) | shuf -n1)
echo "[INFO] Selected wallpaper: $WALLPAPER"

# Start swww daemon if needed
if ! pgrep -x swww-daemon >/dev/null; then
    echo "[INFO] swww daemon not running, starting..."
    swww-daemon &
    sleep 0.5
else
    echo "[INFO] swww daemon already running."
fi

# Extract dominant color
echo "[INFO] Extracting colors..."
if command -v magick >/dev/null; then
    BG=$(magick "$WALLPAPER" -scale 1x1! -format "%[hex:p{0,0}]" info:)
    BG=$(echo "$BG" | tr 'a-f' 'A-F' | grep -oE '[0-9A-F]{6}' | head -n1)
else
    BG="222222"
fi
ACCENT="$BG"

echo "[INFO] Colors extracted: BG=$BG ACCENT=$ACCENT"

# Save colors
echo "BG=$BG" > "$COLOR_FILE"
echo "ACCENT=$ACCENT" >> "$COLOR_FILE"
echo "[INFO] Colors saved to $COLOR_FILE"

# Update Waybar CSS
echo "[INFO] Updating Waybar CSS..."
cat > "$WAYBAR_CSS" <<EOF
#waybar {
    background-color: #$BG;
    color: #$ACCENT;
    padding: 5px 10px;
    font-family: monospace;
    font-size: 12px;
}

#workspaces { color: #$ACCENT; }
#clock { color: #$ACCENT; }
#pulseaudio { color: #$ACCENT; }
#wp-button { color: #$ACCENT; }
EOF

# Restart Waybar
echo "[INFO] Restarting Waybar..."
pkill -x waybar || true
waybar &

# Set wallpaper
echo "[INFO] Setting wallpaper via swww..."
if swww img "$WALLPAPER"; then
    echo "[SUCCESS] Wallpaper set successfully."
else
    echo "[ERROR] Failed to set wallpaper."
fi

echo "[INFO] Wallpaper and color update process completed."
