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
  # Cage 0.3.0 predates support for XCURSOR_THEME and XCURSOR_SIZE.
  cage = pkgs.cage.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ lib.optional (old.version == "0.3.0") (pkgs.fetchpatch {
      url = "https://github.com/cage-kiosk/cage/commit/79e1e0dfaad77f1ca096349a0f8b2666fbe3ee03.patch";
      hash = "sha256-dHqPYbi/AjdPmVyvzgLZl7aM/bs9UX6PyT11tqDXNCg=";
    });
  });
  cursorTheme = "Breeze_Light";
  cursorSize = "18";
  gtkConfig = pkgs.writeTextDir "gtk-4.0/settings.ini" ''
    [Settings]
    gtk-cursor-theme-name=${cursorTheme}
    gtk-cursor-theme-size=${cursorSize}
  '';
  client = pkgs.writeShellScript "frost-greeter-client" ''
    ${lib.optionalString (cfg.outputMode != null) ''
      if ! ${lib.getExe' pkgs.coreutils "timeout"} --kill-after=1s 2s \
        ${lib.getExe pkgs.wlr-randr} --output ${lib.escapeShellArg cfg.outputMode.output} \
        --mode ${lib.escapeShellArg cfg.outputMode.mode}; then
        echo "Frost: could not set the requested display mode" >&2
      fi
    ''}
    export XDG_CONFIG_HOME=${gtkConfig}
    exec ${lib.getExe greeter} --live --username ${lib.escapeShellArg cfg.username} \
      --wallpaper ${cfg.wallpaper} --sessions-dir ${lib.escapeShellArg sessions} \
      --session-path ${lib.escapeShellArg sessionPath}
  '';
  launcher = pkgs.writeShellScript "frost-greeter-launcher" ''
    # Keep the greeter's rendering options separate from the user session.
    export GDK_BACKEND=wayland GSK_RENDERER=cairo WLR_RENDERER=pixman
    export XCURSOR_THEME=${cursorTheme} XCURSOR_SIZE=${cursorSize}
    export XCURSOR_PATH=${pkgs.kdePackages.breeze}/share/icons
    export XKB_DEFAULT_LAYOUT=${lib.escapeShellArg xkb.layout}
    export XKB_DEFAULT_VARIANT=${lib.escapeShellArg xkb.variant}
    export XKB_DEFAULT_OPTIONS=${lib.escapeShellArg xkb.options}
    test -r ${checkedSessions}
    exec ${lib.getExe cage} -s -d -- ${client}
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
    outputMode = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          output = lib.mkOption {
            type = lib.types.str;
            description = "Wayland output name.";
          };
          mode = lib.mkOption {
            type = lib.types.str;
            description = "Advertised mode in wlr-randr format.";
          };
        };
      });
      default = null;
      description = "Output mode to request before displaying the login form.";
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
