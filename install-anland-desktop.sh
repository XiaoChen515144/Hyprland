#!/bin/sh
# Configure the official AvengeMedia Ubuntu PPAs and install a downloaded
# Anland Hyprland artifact set. Run from the artifact directory, or pass it as
# the first argument:
#   ./install-anland-desktop.sh /path/to/anland-ubuntu-packages-arm64
# The artifact contains the locally built Hyprland/Aquamarine/Xwayland packages.
# DMS and Quickshell are resolved from the Ubuntu-native AvengeMedia PPAs.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
artifact_dir=${1:-$script_dir}
artifact_dir=$(CDPATH= cd -- "$artifact_dir" && pwd)

if [ "$(dpkg --print-architecture)" != arm64 ]; then
    echo "install-anland-desktop: this artifact set requires an arm64 Ubuntu system" >&2
    exit 2
fi

if [ "${ID:-}" = "" ] && [ -r /etc/os-release ]; then
    . /etc/os-release
fi
if [ "${ID:-}" != ubuntu ] || [ "${VERSION_CODENAME:-}" != resolute ]; then
    echo "install-anland-desktop: this installer requires Ubuntu 26.04 (resolute) arm64" >&2
    exit 2
fi

# Never mix Debian/OBS repositories into the Droidspaces Ubuntu rootfs. This
# also catches the old Debian_Unstable sources created by earlier revisions of
# this installer before apt is allowed to resolve DMS dependencies.
if grep -RqsE '(^|[[:space:]/])debian([./:]|$)|Debian_Unstable' \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    echo "install-anland-desktop: Debian repositories detected; remove them before continuing" >&2
    exit 2
fi

find_one() {
    pattern=$1
    matches=$(find "$artifact_dir" -maxdepth 1 -type f -name "$pattern" -print)
    count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)
    if [ "$count" -ne 1 ]; then
        echo "install-anland-desktop: expected exactly one $pattern in $artifact_dir (found $count)" >&2
        exit 2
    fi
    printf '%s\n' "$matches"
}
hyprland_deb=$(find_one 'hyprland_*_arm64.deb')
desktop_deb=$(find_one 'hyprland-anland-desktop_*_arm64.deb')
aquamarine_deb=$(find_one 'libaquamarine13_*_arm64.deb')
hyprutils_deb=$(find_one 'libhyprutils13_*_arm64.deb')
hyprutils_dev_deb=$(find_one 'libhyprutils-dev_*_arm64.deb')
hyprgraphics_deb=$(find_one 'libhyprgraphics4_*_arm64.deb')
hyprgraphics_dev_deb=$(find_one 'libhyprgraphics-dev_*_arm64.deb')
xwayland_deb=$(find_one 'xwayland_*_arm64.deb')


if [ -f "$artifact_dir/SHA256SUMS" ]; then
    (
        cd "$artifact_dir"
        sha256sum -c SHA256SUMS
    )
fi

# DMS itself is from the Ubuntu dms PPA; its DankLinux runtime components
# (including Quickshell, danksearch and matugen) are from the Ubuntu
# danklinux PPA. Do not use the Debian_Unstable OBS repositories.
sudo env DEBIAN_FRONTEND=noninteractive apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates software-properties-common
sudo add-apt-repository -y ppa:avengemedia/dms
sudo add-apt-repository -y ppa:avengemedia/danklinux

sudo env DEBIAN_FRONTEND=noninteractive apt-get update
for ubuntu_ppa_package in dms quickshell; do
    if ! apt-cache policy "$ubuntu_ppa_package" | grep -Fq 'ppa.launchpadcontent.net/avengemedia/'; then
        echo "install-anland-desktop: $ubuntu_ppa_package is not available from the AvengeMedia Ubuntu PPA" >&2
        exit 2
    fi
done
# Install the locally built compositor stack and the complete set of Ubuntu
# DMS session components. The explicit dms/quickshell packages ensure that the
# launcher can start the shell instead of silently falling back to compositor
# only. Match DMS's defaults too: Ghostty is optional; git,
# AccountsService and the GTK portal are its standard desktop prerequisites.
# Only artifacts produced by this test tree are reinstalled.  Repository packages
# must retain apt's normal upgrade/dependency resolution behaviour.
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades \
    "$hyprutils_deb" \
    "$hyprutils_dev_deb" \
    "$hyprgraphics_deb" \
    "$hyprgraphics_dev_deb" \
    "$aquamarine_deb" \
    "$hyprland_deb" \
    "$xwayland_deb" \
    "$desktop_deb"
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    dms \
    quickshell \
    matugen \
    danksearch \
    hypridle \
    hyprlock \
    hyprpaper \
    hyprpicker \
    hyprpolkitagent \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-gtk \
    git \
    kitty \
    alacritty \
    accountsservice \
    power-profiles-daemon \
    cups-pk-helper \
    fonts-noto-cjk \
    fonts-noto-cjk-extra \
    fonts-noto-color-emoji \
    pipewire \
    pipewire-pulse \
    wireplumber \
    pulseaudio-utils \
    python3

# Ghostty is DMS's default terminal. Keep it optional so Kitty/Alacritty remain
# available if the PPA has not published a compatible ARM64 build yet.
if ! sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ghostty; then
    echo "install-anland-desktop: Ghostty is unavailable for this rootfs; Kitty and Alacritty were installed instead." >&2
fi

for required_command in dms; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "install-anland-desktop: $required_command is missing after Ubuntu PPA installation" >&2
        exit 2
    fi
done
if ! command -v quickshell >/dev/null 2>&1 && ! command -v qs >/dev/null 2>&1; then
    echo "install-anland-desktop: Quickshell is missing after Ubuntu PPA installation" >&2
    exit 2
fi
if ! dms --help >/dev/null 2>&1; then
    echo "install-anland-desktop: the installed DMS binary failed its startup check" >&2
    exit 2
fi

# DMS defaults for the Anland tablet profile.
dms_settings="$HOME/.config/DankMaterialShell/settings.json"
if command -v python3 >/dev/null 2>&1; then
    mkdir -p "$(dirname "$dms_settings")"
    DMS_SETTINGS="$dms_settings" python3 - <<'PY'
import json, os
p = os.environ["DMS_SETTINGS"]
try:
    try:
        with open(p, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        data = {}
    data["workspaceFollowFocus"] = True
    # QtMultimedia playback for every volume step can stall the single Anland
    # remote audio sink. Keep other DMS sounds enabled, but disable this noisy
    # high-frequency feedback path for the tablet profile.
    data["soundVolumeChanged"] = False
    bars = data.setdefault("barConfigs", [])
    target = next((bar for bar in bars if bar.get("id") == "default" or bar.get("name") == "Main Bar"), None)
    if target is None:
        target = {"id": "default", "name": "Main Bar", "enabled": True,
                  "screenPreferences": ["all"], "showOnLastDisplay": True}
        bars.append(target)
    # DMS enum: 0 top, 1 bottom, 2 left, 3 right.
    target["position"] = 2
    target["leftWidgets"] = ["launcherButton", "workspaceSwitcher"]
    target["centerWidgets"] = ["focusedWindow"]
    target["rightWidgets"] = ["clock", "controlCenterButton"]
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, p)
except (OSError, ValueError, KeyError) as e:
    print("install-anland-desktop: DMS settings migration skipped: " + str(e))
PY
fi

# DMS reads evdev devices for input integration.  Make this idempotent and use
# the original caller when this script itself was invoked through sudo.
install_user=${SUDO_USER:-$(id -un)}

# Start the complete Anland Hyprland+DMS session on container boot.  Keeping it
# as one system service gives systemd a single cgroup, so stopping the service
# also stops DMS, Quickshell, and all DMS helper processes.
sudo tee /etc/systemd/system/hyprland-anland.service >/dev/null <<EOF
[Unit]
Description=Start Anland Hyprland with Dank Material Shell
After=network.target

[Service]
Type=simple
User=$install_user
Group=$install_user
PAMName=login
EnvironmentFile=-/etc/environment
ExecStart=/bin/sh -lc 'exec start-hyprland-anland'
# power-profiles-daemon is enabled only for this tablet desktop profile; stop
# it after DMS logout too, rather than leaving a visible container service.
ExecStopPost=-/usr/bin/systemctl stop power-profiles-daemon.service
Restart=no
KillMode=control-group
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable hyprland-anland.service

echo "install-anland-desktop: enabled hyprland-anland.service for container boot"


if getent group input >/dev/null 2>&1; then
    if id -nG "$install_user" | tr ' ' '\n' | grep -Fx input >/dev/null 2>&1; then
        echo "install-anland-desktop: $install_user is already in the input group"
    else
        sudo usermod -aG input "$install_user"
        echo "install-anland-desktop: added $install_user to the input group; log out and log in again before starting DMS"
    fi
else
    echo "install-anland-desktop: input group does not exist; skipping DMS evdev permission setup" >&2
fi

# Hyprgrass is shipped inside the ABI-matched hyprland Debian package. Inject
# only a marked, replaceable Lua block; existing user configuration is preserved.
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
hypr_config_dir="$config_home/hypr"
hypr_config="$hypr_config_dir/hyprland.lua"
if command -v dpkg-architecture >/dev/null 2>&1; then
    plugin_multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
elif [ "$(dpkg --print-architecture 2>/dev/null)" = "arm64" ]; then
    plugin_multiarch=aarch64-linux-gnu
else
    echo "install-anland-desktop: dpkg-architecture is required to locate the Hyprgrass plugin" >&2
    exit 2
fi
hyprgrass_target="/usr/lib/$plugin_multiarch/hyprland/plugins/libhyprgrass.so"

if [ ! -r "$hyprgrass_target" ]; then
    echo "install-anland-desktop: Hyprgrass is missing from the installed hyprland package: $hyprgrass_target" >&2
    exit 2
fi

if [ ! -e "$hypr_config" ]; then
    mkdir -p "$hypr_config_dir"
    # Do not pass a missing file with --config: Hyprland 0.56.2 validates an
    # explicit path with filesystem::canonical() before config generation.  With
    # no explicit path it uses the normal XDG location above and generates its
    # embedded default Lua configuration when that file is absent.  A private
    # runtime directory prevents creation or use of a real compositor socket.
    runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/anland-hyprland-runtime.XXXXXX")
    if XDG_RUNTIME_DIR="$runtime_dir" Hyprland --verify-config; then
        :
    else
        rc=$?
        rm -rf "$runtime_dir"
        echo "install-anland-desktop: Hyprland could not generate $hypr_config (exit $rc)" >&2
        exit "$rc"
    fi
    rm -rf "$runtime_dir"

    if [ ! -f "$hypr_config" ]; then
        echo "install-anland-desktop: Hyprland reported success but did not create $hypr_config" >&2
        exit 1
    fi

    echo "install-anland-desktop: created Anland Lua configuration: $hypr_config"
else
    echo "install-anland-desktop: preserving existing Hyprland configuration: $hypr_config"
fi

# Apply the basic Anland profile on every run, not just configuration creation.
# Only our marked blocks are replaced; all user-owned Lua stays untouched.
sed -i '/^[[:space:]]*hl\.config({ autogenerated = true })/d' "$hypr_config"
sed -i 's/local mainMod = "SUPER"/local mainMod = "ALT"/' "$hypr_config"
sed -i '/^-- BEGIN ANLAND BASE/,/^-- END ANLAND BASE/d' "$hypr_config"
cat >>"$hypr_config" <<'EOF'

-- BEGIN ANLAND BASE
-- Anland desktop defaults / Anland 桌面默认设置
-- Keep three initial workspaces available / 保持三个初始工作区可用。
hl.workspace_rule({ workspace = "1", persistent = true, default = true })
hl.workspace_rule({ workspace = "2", persistent = true })
hl.workspace_rule({ workspace = "3", persistent = true })
-- Native Hyprland touch gestures are intentionally omitted here. Hyprgrass
-- owns touchscreen gestures below to avoid duplicate dispatch on reconnect.
-- END ANLAND BASE
EOF

sed -i '/^-- BEGIN ANLAND HYPRGRASS/,/^-- END ANLAND HYPRGRASS/d' "$hypr_config"
cat >>"$hypr_config" <<EOF

-- BEGIN ANLAND HYPRGRASS
-- Bundled Hyprgrass touchscreen profile / 随附 Hyprgrass 触屏配置
hl.plugin.load("$hyprgrass_target")

-- Plugin functions/config values become available after the first config pass.
-- Hyprgrass reloads the config after registering them, so this guard makes the
-- initial startup valid and activates the profile on that automatic reload.
if hl.plugin.hyprgrass then
    -- Tablet defaults recommended by Hyprgrass / Hyprgrass 推荐的平板默认值
    hl.config({
        plugin = {
            hyprgrass = {
                sensitivity = 4.0,
                long_press_delay = 400,
                resize_on_border_long_press = true,
                edge_margin = 10,
            },
        },
        gestures = {
            workspace_swipe_touch = true,
            workspace_swipe_cancel_ratio = 0.15,
        },
    })

    -- Hyprgrass touchscreen gestures / Hyprgrass 触屏手势
    -- 三指水平滑动：切换工作区；三指上：全屏；三指下：浮动。
    -- Use one continuous horizontal workspace gesture. Hyprgrass passes it to
    -- Hyprland's workspace swipe state machine, rather than selecting one
    -- directional completion early and allowing a short release to become tap.
    hl.plugin.hyprgrass.gesture { pattern = {kind = "swipe", fingers = 3, direction = "horizontal"}, action = "workspace" }
    hl.plugin.hyprgrass.gesture { pattern = {kind = "swipe", fingers = 3, direction = "up"}, action = "fullscreen", mode = "toggle" }
    hl.plugin.hyprgrass.gesture { pattern = {kind = "swipe", fingers = 3, direction = "down"}, action = "float", mode = "toggle" }
    -- 四指下：切换 magic 特殊工作区；四指上：关闭焦点窗口。
    hl.plugin.hyprgrass.gesture { pattern = {kind = "swipe", fingers = 4, direction = "down"}, action = "special", workspace_name = "magic" }
    hl.plugin.hyprgrass.gesture { pattern = {kind = "swipe", fingers = 4, direction = "up"}, action = "close" }
    -- 从左/右屏幕边缘向内单指滑动：下一个/上一个工作区。
    -- No one-finger long-press drag is installed: normal touch holds must not
    -- capture the pointer or leave the gesture state stuck.
    hl.plugin.hyprgrass.bind { pattern = {kind = "edge", origin = "left", direction = "right"}, action = hl.dsp.focus({workspace = "+1"}) }
    hl.plugin.hyprgrass.bind { pattern = {kind = "edge", origin = "right", direction = "left"}, action = hl.dsp.focus({workspace = "-1"}) }
end
-- END ANLAND HYPRGRASS
EOF

echo "install-anland-desktop: installed Hyprgrass plugin: $hyprgrass_target"

# Do not retain downloaded package archives inside the constrained container.
sudo apt clean

cat <<'EOF'

Anland Hyprland desktop installed.

Touch gestures / 触屏手势:
  • 3-finger swipe left or right: switch workspaces.
    三指左滑或右滑：切换工作区。
  • 3-finger swipe up: toggle fullscreen for the focused window.
    三指上滑：切换当前焦点窗口的全屏状态。
  • 3-finger swipe down: toggle floating for the focused window.
    三指下滑：切换当前焦点窗口的浮动状态。
  • 4-finger swipe down: open the "magic" special workspace.
    四指下滑：打开“magic”特殊工作区。
  • 4-finger swipe up: close the focused window.
    四指上滑：关闭当前焦点窗口。
  • Swipe inward from the left/right screen edge: next/previous workspace.
    从屏幕左/右边缘向内滑动：下一个/上一个工作区。

Tip / 提示:
  In Anland app settings, Relative Mouse Mode can also trigger these gestures
  with a mouse.
  在 Anland 软件设置中开启“相对模式鼠标”后，也可以用鼠标触发上述手势。

Start command / 启动命令:
  start-hyprland-anland
  Run this command to start the Anland Hyprland desktop session.
  运行此命令即可启动 Anland Hyprland 桌面会话。
EOF
