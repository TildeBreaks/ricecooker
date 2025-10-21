# Automated Hyprland Theming

This repository contains a set of scripts and configuration files to create a dynamic, wallpaper-based desktop theme for a Hyprland environment. The system automatically extracts colors from a chosen wallpaper and applies them to Waybar, Rofi, Qt5/Qt6 applications, and Hyprland's own window decorations.

## Features

- **Dynamic Theming:** Run a single script to generate and apply a new theme.
- **Wallpaper-Based:** Colors are intelligently extracted from any wallpaper.
- **Comprehensive:** Themes Waybar, Rofi, Qt applications, and Hyprland.
- **Customizable:** All configurations are easily editable.

## Dependencies

This setup assumes you have the following software installed:

- **Hyprland:** The Wayland compositor.
- **Waybar:** The status bar.
- **Rofi:** The application launcher.
- **`qt5ct` & `qt6ct`:** For theming Qt applications.
- **ImageMagick:** For extracting colors from wallpapers (`magick` command).
- **`swww`:** For setting wallpapers.

## Manual Setup

After cloning this repository, you must perform a few manual steps to get everything working correctly.

### 1. Copy Configuration Files

The configuration files in this repository need to be placed in your `~/.config/` directory.

```bash
# From the root of this repository
cp -r hypr rofi systemd waybar ~/.config/
```

### 2. Reload the Systemd Daemon

The theme-changing script is triggered by a `systemd` user service. After copying the service file, you must tell `systemd` to scan for new files.

```bash
systemctl --user daemon-reload
```

### 3. Set the Qt Platform Theme

For Qt applications to use your new dynamic themes, you must set an environment variable.

1.  **Open your shell's startup file.** This is usually `~/.bash_profile`, `~/.bashrc`, or `~/.zshenv` (for Zsh).
2.  **Add the following line** to the file:

    ```bash
    export QT_QPA_PLATFORMTHEME=qt6ct
    ```
    *(Note: `qt6ct` can also manage Qt5 applications, so you typically only need to set this one variable).*

3.  **Log out and log back in** for the change to take effect.

### 4. Select a Theme in `qt5ct`/`qt6ct`

After running the theme script for the first time, you will need to open `qt5ct` and `qt6ct` and select "GeneratedTheme" from the list of color schemes.

Once these steps are complete, you can click the magic wand icon (🪄) on Waybar to change your theme at any time.
