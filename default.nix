{ pkgs ? import <nixpkgs> { } }:

let
  python = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
in
pkgs.runCommand "frost-greeter" {
  nativeBuildInputs = [ pkgs.makeWrapper ];
  meta.mainProgram = "frost-greeter";
} ''
  mkdir -p "$out/bin" "$out/share/frost-greeter"
  cp ${./greeter.py} "$out/share/frost-greeter/greeter.py"
  cp ${./backend.py} "$out/share/frost-greeter/backend.py"
  makeWrapper ${python}/bin/python3 "$out/bin/frost-greeter" \
    --add-flags "-E -s $out/share/frost-greeter/greeter.py" \
    --prefix GI_TYPELIB_PATH : ${pkgs.lib.makeSearchPath "lib/girepository-1.0" [
      pkgs.gtk4 pkgs.glib.out pkgs.pango.out pkgs.gdk-pixbuf pkgs.harfbuzz pkgs.graphene pkgs.gobject-introspection
    ]}
''
