#!/usr/bin/env bash
set -euo pipefail

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw is not installed. Install or open equivalent firewall rules manually."
  exit 1
fi

for port in 2379 2380 5432 8008 5000 7000; do
  sudo ufw allow from 192.168.0.0/24 to any port "$port" proto tcp
done

sudo ufw status numbered
