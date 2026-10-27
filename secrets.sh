#!/usr/bin/env bash
set -euo pipefail

# directory variables
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
secrets_file="$script_dir/.secret.yaml"
secrets_ram_dir="/run/user/$(id -u)/secrets"
env_file="$script_dir/.env"

# update .env file (in-place)
if grep -q '^SECRET_PATH=' "$env_file"; then
  sed -i "s|^SECRET_PATH=.*|SECRET_PATH=$secrets_ram_dir|" "$env_file"
else
  printf "\n\n# Docker Secret Path \nSECRET_PATH=%s\n" "$secrets_ram_dir" >> "$env_file"
fi

# mount secrets folder to RAM
mkdir -p "$secrets_ram_dir"

# decrypt secrets yaml; output each value in own .txt with key as filename
# YAML version
sops exec-file "$secrets_file" 'bash -c "
  secrets_ram_dir=\"'"$secrets_ram_dir"'\"

  while IFS= read -r line; do
    # Remove comments and empty lines
    [[ \"\$line\" =~ ^#.*$ || -z \"\$line\" ]] && continue

    # Extract key and value, trimming spaces
    key=\$(echo \"\${line%%:*}\" | xargs)
    val=\$(echo \"\${line#*:}\" | xargs)

    echo -n \"\$val\" > \"\$secrets_ram_dir/.secret.\${key}.txt\"
  done < \"{}\"
"'
