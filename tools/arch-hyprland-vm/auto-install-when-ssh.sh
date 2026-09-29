#!/bin/bash
set -euo pipefail
DIR=/workspace/vms/arch-hyprland
LOG=$DIR/auto-install.log
SSH=(sshpass -p arch ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 2222 arch@127.0.0.1)
echo "$(date -u) waiting for SSH" | tee -a "$LOG"
for i in $(seq 1 180); do
  if timeout 30 "${SSH[@]}" 'echo ready' >/dev/null 2>&1; then
    echo "$(date -u) SSH up at try $i" | tee -a "$LOG"
    break
  fi
  sleep 20
  if (( i == 180 )); then echo TIMEOUT | tee -a "$LOG"; exit 1; fi
done
# Copy and run setup
"${SSH[@]}" 'mkdir -p ~/setup' 
sshpass -p arch scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 2222 "$DIR/guest-setup.sh" arch@127.0.0.1:~/setup/guest-setup.sh
echo "$(date -u) running guest-setup (long)" | tee -a "$LOG"
# Use sudo with password
timeout 3600 "${SSH[@]}" 'echo arch | sudo -S bash ~/setup/guest-setup.sh' 2>&1 | tee -a "$LOG"
echo "$(date -u) guest-setup finished exit=$?" | tee -a "$LOG"
"${SSH[@]}" 'pacman -Q hyprland waybar kitty seatd mesa 2>/dev/null; ls ~/.config/hypr/hyprland.conf' 2>&1 | tee -a "$LOG"
echo DONE | tee -a "$LOG"
