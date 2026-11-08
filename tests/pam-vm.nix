{ pkgs ? import <nixpkgs> { } }:
pkgs.testers.runNixOSTest {
  name = "frost-greeter-pam";
  nodes.machine = { pkgs, ... }:
    let
      session = name: pkgs.writeShellScriptBin name ''
        set -eu
        test "$XDG_SESSION_TYPE" = wayland
        test "$XDG_SESSION_DESKTOP" = ${name}
        touch "$HOME/${name}-started"
        sleep 2
      '';
      mango = session "mango";
      plasma = session "plasma";
      desktops = pkgs.runCommand "test-desktops" { passthru.providedSessions = [ "mango" "plasma" ]; } ''
        mkdir -p "$out/share/wayland-sessions"
        cat > "$out/share/wayland-sessions/mango.desktop" <<'DESKTOP'
        [Desktop Entry]
        Name=Mango
        Exec=mango
        DesktopNames=mango;wlroots
        DESKTOP
        cat > "$out/share/wayland-sessions/plasma.desktop" <<DESKTOP
        [Desktop Entry]
        Name=Plasma
        Exec=${plasma}/bin/plasma
        DesktopNames=KDE
        DESKTOP
      '';
    in {
      imports = [ ../module.nix ];
      services.frostGreeter = {
        enable = true;
        username = "alice";
        wallpaper = pkgs.writeText "test-wallpaper.svg" ''
          <svg xmlns="http://www.w3.org/2000/svg" width="1280" height="800">
            <rect width="1280" height="800" fill="#adc9e3"/>
          </svg>
        '';
      };
      programs.mangowc.package = mango;
      services.displayManager.sessionPackages = [ desktops ];
      users.users.alice = {
        isNormalUser = true;
        initialPassword = "frosttest";
      };
      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      virtualisation.memorySize = 1536;
    };
  testScript = ''
    start_all()
    machine.wait_for_unit("greetd.service")
    machine.wait_until_succeeds("pgrep -u greeter -f '[f]rost-greeter/greeter.py'", timeout=45)
    machine.sleep(3)
    machine.send_chars("wrong\n")
    machine.wait_until_succeeds("journalctl -b -u greetd | grep -q 'authentication failure'", timeout=45)
    machine.sleep(3)
    machine.succeed("test ! -e /var/lib/frost-greeter/session")
    machine.send_chars("frosttest\n")
    machine.wait_for_file("/home/alice/mango-started", timeout=45)
    machine.succeed("grep -Fx mango /var/lib/frost-greeter/session")

    machine.wait_until_succeeds("pgrep -u greeter -f '[f]rost-greeter/greeter.py'", timeout=45)
    machine.sleep(3)
    machine.send_key("tab")
    machine.send_key("spc")
    machine.send_key("down")
    machine.send_key("ret")
    machine.send_key("shift-tab")
    machine.send_chars("frosttest\n")
    machine.wait_for_file("/home/alice/plasma-started", timeout=45)
    machine.succeed("grep -Fx plasma /var/lib/frost-greeter/session")
    machine.succeed("rm /home/alice/plasma-started")
    machine.wait_until_succeeds("pgrep -u greeter -f '[f]rost-greeter/greeter.py'", timeout=45)
    machine.sleep(3)
    machine.send_chars("frosttest\n")
    machine.wait_for_file("/home/alice/plasma-started", timeout=45)
  '';
}
