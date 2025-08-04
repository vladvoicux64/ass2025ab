#!/bin/bash
set -e

SCRIPTS_DIR="./scripts"

echo "[+] Looking for scripts in: $SCRIPTS_DIR"

if [[ ! -d "$SCRIPTS_DIR" ]]; then
    echo "[!] Directory not found: $SCRIPTS_DIR"
    exit 1
fi


for script in "$SCRIPTS_DIR"/*.sh; do
    if [[ -f "$script" && -x "$script" ]]; then
        echo "[+] Executing: $(basename "$script")"
        "$script"
    elif [[ -f "$script" ]]; then
        echo "[*] Making executable: $(basename "$script")"
        chmod +x "$script"
        "$script"
    fi
done

echo "[✔] All scripts executed."

