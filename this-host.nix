{
  imports = [ ./module.nix ];
  services.frostGreeter = {
    enable = true;
    username = "tiramisu";
    wallpaper = /etc/nixos/frost-wall.jpg;
    outputMode = {
      output = "HDMI-A-1";
      mode = "1920x1080@239.998Hz";
    };
  };
}
