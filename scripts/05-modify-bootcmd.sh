#!/bin/bash
set -euo pipefail

ENV_FILE="./imx-linux-builder/boards/imx93/frdm-imx93/uboot/default.env"
BOOTCMD_FILE="utils/boot.cmd.in"

# Check inputs
[[ -f "$ENV_FILE" ]] || {
  echo "[!] $ENV_FILE not found"
  exit 1
}
[[ -f "$BOOTCMD_FILE" ]] || {
  echo "[!] $BOOTCMD_FILE not found"
  exit 1
}

# Read and transform: newlines to semicolons, trim trailing semis
NEW_BOOTCMD=$(tr '\n' ';' <"$BOOTCMD_FILE" | sed 's/;*$//')

# Escape any sed-sensitive characters in the replacement string
ESCAPED_BOOTCMD=$(printf '%s' "$NEW_BOOTCMD" | sed 's/[\/&]/\\&/g')

# Do the replacement using a rare delimiter (e.g., §)
echo "[+] Updating bootcmd in $ENV_FILE"
sed -i "s/^bootcmd=.*/bootcmd=${ESCAPED_BOOTCMD}/" "$ENV_FILE"

echo "[✔] bootcmd updated to:"
echo "bootcmd=$NEW_BOOTCMD"
