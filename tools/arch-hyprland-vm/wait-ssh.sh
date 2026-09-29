#!/bin/bash
for i in $(seq 1 120); do
  pid=$(cat /workspace/vms/arch-hyprland/qemu.pid 2>/dev/null)
  rss=$(ps -p "$pid" -o rss= 2>/dev/null | tr -d ' ' || echo dead)
  echo "$(date -u +%H:%M:%S) i=$i rss=$rss" >> /workspace/vms/arch-hyprland/ssh-poll.log
  if [ "$rss" = "dead" ]; then echo DEAD >> /workspace/vms/arch-hyprland/ssh-poll.log; exit 1; fi
  if timeout 40 sshpass -p arch ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 2222 arch@127.0.0.1 "echo SSH_OK; uname -a" >> /workspace/vms/arch-hyprland/ssh-poll.log 2>&1; then
    echo SUCCESS >> /workspace/vms/arch-hyprland/ssh-poll.log
    exit 0
  fi
  sleep 20
done
echo TIMEOUT >> /workspace/vms/arch-hyprland/ssh-poll.log
