#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "$0")" && pwd)
config_dir=/etc/nixos
config="$config_dir/configuration.nix"
backup="$config.pre-frost-greeter"
destination="$config_dir/frost-greeter"
import_line='      ./frost-greeter/this-host.nix'

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
cp -- "$config" "$scratch/original"

if rg -Fxq "$import_line" "$scratch/original"; then
    printf 'Frost is already configured. Rebuilding the boot generation.\n'
else
    if rg -q 'frostGreeter|\./frost-greeter/' "$scratch/original"; then
        printf 'A Frost configuration already exists. Review %s before continuing.\n' "$config" >&2
        exit 1
    fi
    if ! awk -v line="$import_line" '
        { print }
        /^      \.\/frost-login\.nix$/ { print line; count++ }
        END { if (count != 1) exit 1 }
    ' "$scratch/original" > "$scratch/next"; then
        printf 'Could not locate the expected SDDM theme import in %s.\n' "$config" >&2
        exit 1
    fi
    diff -u --label "$config" --label "$config (staged)" \
        "$scratch/original" "$scratch/next" || test "$?" -eq 1
fi

test -r "$config_dir/frost-wall.jpg"
sudo -v
if [[ -f "$scratch/next" ]]; then
    sudo cmp -s -- "$config" "$scratch/original"
    sudo cp --update=none -- "$config" "$backup"
    if ! sudo cmp -s -- "$backup" "$scratch/original"; then
        printf 'Existing backup differs from the current config. Review %s.\n' "$backup" >&2
        exit 1
    fi
fi

sudo install -d -m 0755 -- "$destination"
for file in default.nix module.nix greeter.py backend.py this-host.nix; do
    sudo install -m 0644 -- "$repo/$file" "$destination/$file"
done

if [[ -f "$scratch/next" ]]; then
    sudo cmp -s -- "$config" "$scratch/original"
    sudo install -m 0644 -- "$scratch/next" "$config.frost-next"
    sudo mv -T -- "$config.frost-next" "$config"
fi

sudo nixos-rebuild boot -I "nixos-config=$config"
printf 'Frost is staged for the next boot. Run sudo reboot when ready.\n'
