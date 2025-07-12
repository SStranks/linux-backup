#!/usr/bin/env bash
set -euo pipefail

# Directory variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/.secret.yaml"
SECRETS_RAM_DIR="/run/user/$(id -u)/secrets"
ENV_FILE="$SCRIPT_DIR/.env"

# Update .env file (in-place)
if grep -q '^SECRET_PATH=' "$ENV_FILE"; then
  sed -i "s|^SECRET_PATH=.*|SECRET_PATH=$SECRETS_RAM_DIR|" "$ENV_FILE"
else
  printf "\n\n# Docker Secret Path \nSECRET_PATH=%s\n" "$SECRETS_RAM_DIR" >> "$ENV_FILE"
fi

# Mount secrets folder to RAM
mkdir -p "$SECRETS_RAM_DIR"

# Decrypt secrets yaml; output each value in own .txt with key as filename
# YAML Version
sops exec-file "$SECRETS_FILE" 'bash -c "
  SECRETS_RAM_DIR=\"'"$SECRETS_RAM_DIR"'\"

  while IFS= read -r line; do
    # Remove comments and empty lines
    [[ \"\$line\" =~ ^#.*$ || -z \"\$line\" ]] && continue

    # Extract key and value, trimming spaces
    key=\$(echo \"\${line%%:*}\" | xargs)
    val=\$(echo \"\${line#*:}\" | xargs)

    echo -n \"\$val\" > \"\$SECRETS_RAM_DIR/.secret.\${key}.txt\"
  done < \"{}\"
"'
