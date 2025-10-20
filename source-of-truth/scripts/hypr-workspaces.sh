#!/usr/bin/env bash
set -euo pipefail

# hypr-workspaces.sh - plain text workspace list with focused marker
# Outputs e.g.:
# 1 [2] 3 4
# Requires hyprctl -j workspaces for best results; jq improves reliability.

if command -v hyprctl >/dev/null 2>&1; then
  out=$(hyprctl -j workspaces 2>/dev/null || true)
  if [[ -n "$out" ]]; then
    if command -v jq >/dev/null 2>&1; then
      # Mark focused/active workspaces with brackets [] for visibility
      printf "%s\n" "$(printf '%s' "$out" | jq -r '.[] | if (.focused==true or .active==true or .isActive==true) then "[" + (.name//(.id|tostring)) + "]" else (.name//(.id|tostring)) end' | paste -sd ' ' -)"
      exit 0
    else
      # crude fallback: try to map lines with "name" and keep order (may be lossy)
      names=$(printf '%s' "$out" | sed -nE 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | paste -sd ' ' -)
      if [[ -n "$names" ]]; then
        printf "%s\n" "$names"
        exit 0
      fi
    fi
  fi
fi

# Fallback: basic numbered list (1..5)
printf "1 2 3 4 5\n"
