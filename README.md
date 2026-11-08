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

After reviewing the preview, run these commands from the repo checkout:

```sh
sudo cp --no-clobber /etc/nixos/configuration.nix /etc/nixos/configuration.nix.pre-frost-greeter
sudo install -d -m 0755 /etc/nixos/frost-greeter
sudo install -m 0644 default.nix module.nix greeter.py backend.py /etc/nixos/frost-greeter/
sudoedit /etc/nixos/configuration.nix
```

Add this entry inside the existing `imports` list:

```nix
./frost-greeter/module.nix
```

Add these settings in the same file's top-level attribute set:

```nix
services.frostGreeter = {
  enable = true;
  username = "tiramisu";
  wallpaper = /etc/nixos/frost-wall.jpg;
};
```

Build first, then make the generation the next boot target. The live desktop continues using SDDM until reboot.

```sh
sudo nixos-rebuild build
sudo nixos-rebuild boot
sudo reboot
```

After reboot, try a Mango login, log out, then try Plasma. Log out again and check that Plasma is selected. The staging build and nested preview do not exercise physical VT ownership, PAM against your real account, or launching either desktop on the RTX 3070.

## Return to SDDM

If the greeter fails, switch to a text console with Ctrl+Alt+F2 and sign in. If the VT is unreachable, reboot and choose the previous NixOS generation in the Miku GRUB menu. That generation uses SDDM.

To restore SDDM for subsequent boots, run `sudoedit /etc/nixos/configuration.nix` and remove the Frost module import and the `services.frostGreeter` block. If you just installed Frost and made no other edits, you can restore the backup instead:

```sh
sudo cp /etc/nixos/configuration.nix.pre-frost-greeter /etc/nixos/configuration.nix
```

Then rebuild the boot generation and reboot:

```sh
sudo nixos-rebuild boot
sudo reboot
```

For diagnostics from the text console, use `sudo journalctl -b -u greetd`. After rebooting into the previous generation, use `sudo journalctl -b -1 -u greetd` if the failed boot's journal is available.
