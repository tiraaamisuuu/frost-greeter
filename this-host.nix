{
  imports = [ ./module.nix ];
  services.frostGreeter = {
    enable = true;
    username = "tiramisu";
    wallpaper = /etc/nixos/frost-wall.jpg;
  };
}
