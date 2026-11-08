# Frost Greeter

A compact GTK 4 greeter for NixOS. Cage hosts the greeter on Wayland. greetd handles PAM authentication and starts the selected desktop.

## Preview in your current desktop

From the repo checkout:

```sh
nix-build
./result/bin/frost-greeter --preview --fullscreen
```

The preview opens with the password field focused and Mango selected. Enter any wrong value to see the retry state, then use the demo password `frost`. Tab moves from the password to the session picker and the sign-in button, then wraps to the account field. Shift+Tab moves back to the account field. Use Space and the arrow keys in the session picker. Esc closes the preview. Leave out `--fullscreen` for a window. The preview reads `~/Pictures/mango-wall.jpg` by default and runs independently of greetd.

## Install on this NixOS 26.05 host

The system already provides `mango.desktop` and `plasma.desktop` and has an exact copy of the wallpaper at `/etc/nixos/frost-wall.jpg`. The module checks both Wayland entries and their launch commands during the build. Mango is the first-boot default. After greetd accepts a session launch, the greeter stores only the session ID in `/var/lib/frost-greeter/session`. Cage uses software rendering for the login screen and allows switching to another VT.

Frost uses an 18 px Breeze Light cursor. The host config requests 1920×1080 at 239.998 Hz on HDMI-A-1. If that mode is unavailable, Cage keeps its default mode and the login form still opens.

After reviewing the preview, stage Frost from the repo checkout:

```sh
./stage-this-host.sh
```

The script shows the import it will add, prompts for sudo, backs up `/etc/nixos/configuration.nix` to `configuration.nix.pre-frost-greeter`, installs the module and the host settings under `/etc/nixos/frost-greeter`, and runs `nixos-rebuild boot`. Your current desktop continues using SDDM while it builds. When the script reports success, reboot:

```sh
sudo reboot
```

Try a Mango login, log out, then try Plasma. Log out again and check that Plasma is selected.

## VM test

```sh
nix-build tests/pam-vm.nix
```

The VM boots Cage and greetd on a virtual GPU, checks the configured display mode, and exercises both launch commands and the saved selection using a disposable PAM account and small fixture sessions. The staged host build verifies the actual Mango and Plasma entries. The monitor mode and session startup on physical hardware can be checked after reboot.

## Return to SDDM

If the greeter fails, switch to a text console with Ctrl+Alt+F2 and sign in. If the VT is unreachable, reboot and choose the previous NixOS generation in the Miku GRUB menu. That generation uses SDDM.

To restore SDDM for subsequent boots, run `sudoedit /etc/nixos/configuration.nix` and remove `./frost-greeter/this-host.nix` from the imports list. If you just installed Frost and made no other edits, you can restore the backup instead:

```sh
sudo cp /etc/nixos/configuration.nix.pre-frost-greeter /etc/nixos/configuration.nix
```

Then rebuild the boot generation and reboot:

```sh
sudo nixos-rebuild boot
sudo reboot
```

For diagnostics from the text console, use `sudo journalctl -b -u greetd`. After rebooting into the previous generation, use `sudo journalctl -b -1 -u greetd` if the failed boot's journal is available.
