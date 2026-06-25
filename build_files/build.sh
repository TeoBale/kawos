#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

if command -v dnf5.real >/dev/null 2>&1; then
    DNF="dnf5.real"
else
    DNF="dnf5"
fi

if ! "${DNF}" copr --help >/dev/null 2>&1; then
    "${DNF}" install -y dnf5-plugins
fi

"${DNF}" copr enable -y avengemedia/danklinux
"${DNF}" copr enable -y avengemedia/dms

KAWOS_DESKTOP_PACKAGES=(
    gdm
    gnome-shell
    gnome-session-wayland-session
    niri
    xwayland-satellite
    alacritty
    dms
    quickshell
    matugen
    dgop
    cliphist
    wl-clipboard
    cava
    qt6-qtmultimedia
    xdg-desktop-portal-gtk
    xdg-desktop-portal-gnome
    gnome-keyring
    pipewire
    wireplumber
)

"${DNF}" install -y "${KAWOS_DESKTOP_PACKAGES[@]}"

DANK_SEARCH_PACKAGE="danksearch"
if ! "${DNF}" install -y "${DANK_SEARCH_PACKAGE}"; then
    DANK_SEARCH_PACKAGE="dsearch"
    "${DNF}" install -y "${DANK_SEARCH_PACKAGE}"
fi

if [[ -f /usr/share/wayland-sessions/niri.desktop ]]; then
    mv -f /usr/share/wayland-sessions/niri.desktop /usr/share/wayland-sessions/niri.desktop.kawos-hidden
fi

if [[ -f /usr/lib/systemd/user/dms.service ]]; then
    mkdir -p /etc/systemd/user/niri.service.wants
    ln -sfr /usr/lib/systemd/user/dms.service /etc/systemd/user/niri.service.wants/dms.service
fi

systemctl enable gdm.service

PROTECTED_PACKAGES="/usr/share/rakuos/protected-packages.txt"
if [[ -f "${PROTECTED_PACKAGES}" ]]; then
    {
        echo
        echo "# KawOS GNOME and Dank Linux session packages"
        printf '%s\n' "${KAWOS_DESKTOP_PACKAGES[@]}"
        echo "${DANK_SEARCH_PACKAGE}"
    } >> "${PROTECTED_PACKAGES}"
fi

if [[ -x /usr/libexec/rakuos/generate-base-manifest ]]; then
    /usr/libexec/rakuos/generate-base-manifest
fi
