#!/usr/bin/env bash
set -euo pipefail

# hypr-workspaces-json.sh
# - Emits a JSON array of objects for Waybar (return-type: "json")
# - Each object: { "text": "<label>", "class": "workspace [focused] [occupied] [urgent]" }
# - Requires hyprctl -j workspaces and jq (jq is now installed per your message)
# - Falls back to a safe numbered array if hyprctl output is unavailable.

if ! command -v jq >/dev/null 2>&1; then
  echo '[{"text":"1","class":"workspace focused"},{"text":"2","class":"workspace"},{"text":"3","class":"workspace"},{"text":"4","class":"workspace"},{"text":"5","class":"workspace"}]'
  exit 0
fi

if ! command -v hyprctl >/dev/null 2>&1; then
  # hyprctl not available — return safe default
  jq -n '[range(1;6) | {text: (.|tostring), class: "workspace" + (if .==1 then " focused" else "" end)}]'
  exit 0
fi

# Try to get hyprctl JSON. If hyprctl fails, fall back.
raw=$(hyprctl -j workspaces 2>/dev/null || true)
if [[ -z "$raw" ]]; then
  jq -n '[range(1;6) | {text: (.|tostring), class: "workspace" + (if .==1 then " focused" else "" end)}]'
  exit 0
fi

# Use jq to transform Hyprland workspaces into the array Waybar expects.
# For each workspace we emit:
# { "text": <name-or-id>, "class": "workspace[ focused][ occupied][ urgent]" }
printf '%s' "$raw" \
  | jq -c 'map(
      { text: ( .name // ( .id | tostring ) ),
        class:
          ("workspace"
           + (if (.focused==true) or (.active==true) or (.isActive==true) then " focused" else "" end)
           + (if ((.windows // .clients // []) | length) > 0 then " occupied" else "" end)
           + (if (.urgent == true) then " urgent" else "" end)
          )
      }
  )' \
  || jq -n '[{"text":"1","class":"workspace focused"},{"text":"2","class":"workspace"},{"text":"3","class":"workspace"}]'
