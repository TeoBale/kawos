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

source /usr/lib/os-release
COPR_CHROOT="fedora-${VERSION_ID}-$(uname -m)"

"${DNF}" copr enable -y avengemedia/danklinux "${COPR_CHROOT}"
"${DNF}" copr enable -y avengemedia/dms "${COPR_CHROOT}"
"${DNF}" copr enable -y imput/helium "${COPR_CHROOT}"

KAWOS_DESKTOP_PACKAGES=(
    gdm
    gnome-shell
    gnome-session-wayland-session
    niri
    xwayland-satellite
    ghostty
    helium-bin
    neovim
    xdg-terminal-exec
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

install_zed() {
    local arch asset_name release_json zed_archive
    local -a zed_release=()
    arch="$(uname -m)"

    case "${arch}" in
        x86_64|aarch64)
            asset_name="zed-linux-${arch}.tar.gz"
            ;;
        *)
            echo "Unsupported architecture for Zed: ${arch}" >&2
            return 1
            ;;
    esac

    release_json="$(mktemp)"
    zed_archive="$(mktemp --suffix=.tar.gz)"

    curl --fail --location --retry 3 --retry-all-errors \
        --output "${release_json}" \
        https://api.github.com/repos/zed-industries/zed/releases/latest

    mapfile -t zed_release < <(
        python3 - "${release_json}" "${asset_name}" <<'PY'
import json
import sys

release_path, asset_name = sys.argv[1:]
with open(release_path, encoding="utf-8") as release_file:
    release = json.load(release_file)

for asset in release.get("assets", []):
    if asset.get("name") != asset_name:
        continue

    digest = asset.get("digest", "")
    if not digest.startswith("sha256:"):
        raise SystemExit(f"Missing SHA-256 digest for {asset_name}")

    print(release["tag_name"].removeprefix("v"))
    print(asset["browser_download_url"])
    print(digest.removeprefix("sha256:"))
    break
else:
    raise SystemExit(f"Release asset not found: {asset_name}")
PY
    )

    if [[ "${#zed_release[@]}" -ne 3 ]]; then
        echo "Invalid Zed release metadata" >&2
        return 1
    fi

    local zed_version="${zed_release[0]}"
    local zed_url="${zed_release[1]}"
    local zed_sha256="${zed_release[2]}"

    curl --fail --location --retry 3 --retry-all-errors \
        --output "${zed_archive}" \
        "${zed_url}"
    printf '%s  %s\n' "${zed_sha256}" "${zed_archive}" | sha256sum --check --strict -

    rm -rf /usr/lib/zed.app
    tar -xzf "${zed_archive}" -C /usr/lib

    test -x /usr/lib/zed.app/bin/zed
    test -f /usr/lib/zed.app/share/applications/dev.zed.Zed.desktop

    ln -sfn /usr/lib/zed.app/bin/zed /usr/bin/zed
    install -Dm0644 \
        /usr/lib/zed.app/share/applications/dev.zed.Zed.desktop \
        /usr/share/applications/dev.zed.Zed.desktop
    sed -i \
        -e 's|Icon=zed|Icon=/usr/lib/zed.app/share/icons/hicolor/512x512/apps/zed.png|g' \
        -e 's|Exec=zed|Exec=/usr/lib/zed.app/bin/zed|g' \
        /usr/share/applications/dev.zed.Zed.desktop

    install -d /usr/share/kawos/app-versions
    printf 'version=%s\nsha256=%s\n' "${zed_version}" "${zed_sha256}" \
        > /usr/share/kawos/app-versions/zed

    rm -f "${release_json}" "${zed_archive}"
}

install_zed

DANK_SEARCH_PACKAGE="danksearch"
if ! "${DNF}" install -y "${DANK_SEARCH_PACKAGE}"; then
    DANK_SEARCH_PACKAGE="dsearch"
    "${DNF}" install -y "${DANK_SEARCH_PACKAGE}"
fi

# DMS currently pulls Alacritty back in through a weak dependency. Remove the
# RPM explicitly, then restore KawOS's compatibility command backed by Ghostty.
"${DNF}" --setopt=clean_requirements_on_remove=False remove -y alacritty
install -Dm0755 /ctx/system_files/usr/bin/alacritty /usr/bin/alacritty

if [[ -f /usr/share/wayland-sessions/niri.desktop ]]; then
    mv -f /usr/share/wayland-sessions/niri.desktop /usr/share/wayland-sessions/niri.desktop.kawos-hidden
fi

if [[ -f /usr/lib/systemd/user/dms.service ]]; then
    mkdir -p /etc/systemd/user/niri.service.wants
    ln -sfr /usr/lib/systemd/user/dms.service /etc/systemd/user/niri.service.wants/dms.service
fi

systemctl enable gdm.service

verify_kawos_apps() {
    rpm -q ghostty helium-bin neovim xdg-terminal-exec

    if rpm -q alacritty >/dev/null 2>&1; then
        echo "Alacritty must not be installed in the KawOS image" >&2
        return 1
    fi

    test ! -L /opt
    test -d /opt/helium
    test -x /usr/bin/ghostty
    test -x /usr/bin/helium
    test -x /usr/bin/nvim
    test -x /usr/bin/zed
    test -x /usr/bin/alacritty
    test -f /usr/share/applications/com.mitchellh.ghostty.desktop
    test -f /usr/share/applications/helium.desktop
    test -f /usr/share/applications/dev.zed.Zed.desktop
    grep -Fqx 'com.mitchellh.ghostty.desktop' /etc/xdg/xdg-terminals.list
    grep -Fqx 'x-scheme-handler/https=helium.desktop;' /etc/xdg/mimeapps.list
}

verify_kawos_apps

PROTECTED_PACKAGES="/usr/share/rakuos/protected-packages.txt"
if [[ -f "${PROTECTED_PACKAGES}" ]]; then
    {
        echo
        echo "# KawOS desktop and essential application packages"
        printf '%s\n' "${KAWOS_DESKTOP_PACKAGES[@]}"
        echo "zed"
        echo "${DANK_SEARCH_PACKAGE}"
    } >> "${PROTECTED_PACKAGES}"
fi

if [[ -x /usr/libexec/rakuos/generate-base-manifest ]]; then
    /usr/libexec/rakuos/generate-base-manifest

    KAWOS_BASE_MANIFEST="/usr/share/rakuos/base-manifest.txt"
    if [[ -f "${KAWOS_BASE_MANIFEST}" ]]; then
        {
            find /usr/lib/zed.app -xdev -print
            printf '%s\n' \
                /usr/bin/zed \
                /usr/bin/alacritty \
                /usr/share/applications/dev.zed.Zed.desktop \
                /usr/share/kawos/app-versions/zed
        } >> "${KAWOS_BASE_MANIFEST}"
        sort -u -o "${KAWOS_BASE_MANIFEST}" "${KAWOS_BASE_MANIFEST}"
    fi
fi
