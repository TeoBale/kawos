#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

if command -v dnf5.real >/dev/null 2>&1; then
    DNF="dnf5.real"
else
    DNF="dnf5"
fi

NIRI_PACKAGES=(
    gdm
    niri
    xwayland-satellite
    alacritty
    fuzzel
    waybar
    mako
    xdg-desktop-portal-gtk
    xdg-desktop-portal-gnome
    gnome-keyring
    lxpolkit
    pipewire
    wireplumber
)

"${DNF}" install -y "${NIRI_PACKAGES[@]}"

systemctl enable gdm.service

PROTECTED_PACKAGES="/usr/share/rakuos/protected-packages.txt"
if [[ -f "${PROTECTED_PACKAGES}" ]]; then
    {
        echo
        echo "# KawOS niri session packages"
        printf '%s\n' "${NIRI_PACKAGES[@]}"
    } >> "${PROTECTED_PACKAGES}"
fi

if [[ -x /usr/libexec/rakuos/generate-base-manifest ]]; then
    /usr/libexec/rakuos/generate-base-manifest
fi
