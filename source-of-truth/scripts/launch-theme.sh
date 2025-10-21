#!/bin/bash
# This script is a simple wrapper to launch the main theme script
# in a new process session, ensuring it is not killed when Waybar restarts.
setsid "$HOME/.config/source-of-truth/scripts/pick-colors.sh" &
