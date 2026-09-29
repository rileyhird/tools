#!/usr/bin/env bash
# Run inside the Arch guest as root (or via sudo) to install Hyprland stack.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "[guest-setup] pacman -Syu"
pacman -Syu --noconfirm

PKGS=(
  hyprland
  xdg-desktop-portal-hyprland
  xdg-desktop-portal
  waybar
  kitty
  foot
  swaybg
  grim
  slurp
  wl-clipboard
  noto-fonts
  noto-fonts-emoji
  qt5-wayland
  qt6-wayland
  mesa
  vulkan-virtio
  seatd
  polkit
  brightnessctl
  networkmanager
  sudo
)

echo "[guest-setup] installing packages"
# vulkan-virtio may be named differently; try and continue
for p in "${PKGS[@]}"; do
  pacman -S --noconfirm --needed "$p" || echo "WARN: failed $p"
done

# Ensure arch user can use seatd / video
usermod -aG video,seat,input arch 2>/dev/null || true
systemctl enable --now seatd.service || true
systemctl enable NetworkManager.service || true

# Hyprland config for virtio-gpu: prefer GLES/GL, fall back to pixman via env
install -d -m 755 /home/arch/.config/hypr
cat > /home/arch/.config/hypr/hyprland.conf << 'EOF'
# Minimal Hyprland for QEMU virtio-gpu VM
monitor=,preferred,auto,1

exec-once = waybar
exec-once = swaybg -c '#1e1e2e'
exec-once = kitty

env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORM,wayland
# virtio-gpu: try gles first; if compositor fails, relaunch with WLR_RENDERER=pixman
# env = WLR_RENDERER,pixman
# env = WLR_RENDERER,vulkan

input {
  kb_layout = us
  follow_mouse = 1
}

general {
  gaps_in = 4
  gaps_out = 8
  border_size = 2
  layout = dwindle
}

decoration {
  rounding = 6
}

bind = SUPER, Return, exec, kitty
bind = SUPER, Q, killactive,
bind = SUPER, M, exit,
bind = SUPER, F, fullscreen,
bind = SUPER, E, exec, foot
bind = SUPER, V, togglefloating,
bind = SUPER, left, movefocus, l
bind = SUPER, right, movefocus, r
bind = SUPER, up, movefocus, u
bind = SUPER, down, movefocus, d
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER SHIFT, S, exec, grim -g "$(slurp)" - | wl-copy
EOF
chown -R arch:arch /home/arch/.config

# Start Hyprland on tty1 via bash_profile (no heavy greeter)
# Also provide a wrapper that falls back to pixman if needed.
install -d -o arch -g arch -m 755 /home/arch/.local/bin
cat > /home/arch/.local/bin/start-hyprland.sh << 'EOF'
#!/usr/bin/env bash
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
# Try default renderer first
if ! Hyprland "$@"; then
  echo "Hyprland failed; retrying with WLR_RENDERER=pixman" >&2
  export WLR_RENDERER=pixman
  exec Hyprland "$@"
fi
EOF
install -d -m 755 /home/arch/.local/bin
# rewrite properly
install -d -o arch -g arch -m 755 /home/arch/.local/bin
cat > /home/arch/.local/bin/start-hyprland.sh << 'EOF'
#!/usr/bin/env bash
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
if ! command -v Hyprland >/dev/null; then
  echo "Hyprland not installed" >&2
  exit 1
fi
# Prefer GLES/GL on virtio; fall back to pixman (software) if needed.
Hyprland "$@" || { export WLR_RENDERER=pixman; exec Hyprland "$@"; }
EOF
chmod 755 /home/arch/.local/bin/start-hyprland.sh
chown arch:arch /home/arch/.local/bin/start-hyprland.sh

# Autostart on tty1 login for user arch
if ! grep -q start-hyprland /home/arch/.bash_profile 2>/dev/null; then
  cat >> /home/arch/.bash_profile << 'EOF'

# Auto-start Hyprland on tty1
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" && "${XDG_VTNR:-}" == "1" ]]; then
  exec /home/arch/.local/bin/start-hyprland.sh
fi
EOF
  chown arch:arch /home/arch/.bash_profile
fi

# Autologin on tty1 via getty drop-in (optional, lightweight)
install -d /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin arch --noclear %I $TERM
EOF
systemctl daemon-reload

echo "[guest-setup] verifying packages"
pacman -Q hyprland waybar kitty seatd mesa 2>/dev/null || true
pacman -Q vulkan-virtio 2>/dev/null || pacman -Q vulkan-mesa-layers 2>/dev/null || true
echo "[guest-setup] DONE"
