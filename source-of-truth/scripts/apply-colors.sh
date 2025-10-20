#!/bin/bash
source ~/.config/source-of-truth/colors.env

export WAYBAR_BG="$BG"
export WAYBAR_FG="$FG"
export WAYBAR_ACCENT="$ACCENT"
export WAYBAR_WARN="$WARN"
export WAYBAR_SUCCESS="$SUCCESS"
export WAYBAR_MAGIC="$MAGIC"

# Reload Waybar safely
pkill -SIGUSR1 waybar

notify-send "Colors Applied" "Source of Truth updated"
