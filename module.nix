{ config, lib, pkgs, ... }:

let
  cfg = config.services.frostGreeter;
  greeter = import ./default.nix { inherit pkgs; };
  sessions = "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
  sessionPath = lib.makeBinPath [ config.programs.mangowc.package ];
  checkedSessions = pkgs.runCommand "frost-greeter-sessions" { } ''
    ${lib.getExe greeter} --check-sessions --sessions-dir ${lib.escapeShellArg sessions} \
      --session-path ${lib.escapeShellArg sessionPath} > "$out"
  '';
  xkb = config.services.xserver.xkb;
  launcher = pkgs.writeShellScript "frost-greeter-launcher" ''
    # Keep the greeter's rendering options separate from the user session.
    export GDK_BACKEND=wayland GSK_RENDERER=cairo WLR_RENDERER=pixman
    export XKB_DEFAULT_LAYOUT=${lib.escapeShellArg xkb.layout}
    export XKB_DEFAULT_VARIANT=${lib.escapeShellArg xkb.variant}
    export XKB_DEFAULT_OPTIONS=${lib.escapeShellArg xkb.options}
    test -r ${checkedSessions}
    exec ${lib.getExe pkgs.cage} -s -d -- \
      ${lib.getExe greeter} --live --username ${lib.escapeShellArg cfg.username} \
      --wallpaper ${cfg.wallpaper} --sessions-dir ${lib.escapeShellArg sessions} \
      --session-path ${lib.escapeShellArg sessionPath}
  '';
in
{
  options.services.frostGreeter = {
    enable = lib.mkEnableOption "the Frost graphical greetd greeter";
    username = lib.mkOption {
      type = lib.types.str;
      default = "tiramisu";
      description = "Initial account name in the greeter.";
    };
    wallpaper = lib.mkOption {
      type = lib.types.path;
      description = "Wallpaper copied into the Nix store for the greeter.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = lib.all (name: lib.elem name config.services.displayManager.sessionData.sessionNames)
        [ "mango" "plasma" ];
      message = "Frost Greeter requires the Mango and Plasma NixOS sessions.";
    }];

    services.displayManager.sddm.enable = lib.mkForce false;
    services.greetd = {
      enable = true;
      settings.default_session.command = toString launcher;
    };
    systemd.tmpfiles.rules = [ "d /var/lib/frost-greeter 0700 greeter greeter - -" ];
    fonts.packages = [ pkgs.nerd-fonts.mononoki ];
  };
}
