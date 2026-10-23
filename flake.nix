{
  description = "Personal site tools and Leaflet draft preview";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # Keep the layout used by preview-leaflet.py without bundling docs/.
          previewSource = pkgs.runCommand "leaflet-preview-source" { } ''
            mkdir -p "$out"
            cp -r ${./pandoc} "$out/pandoc"
            cp -r ${./css} "$out/css"
            cp -r ${./images} "$out/images"
          '';
          preview = pkgs.writeShellApplication {
            name = "preview-leaflet";
            runtimeInputs = [ pkgs.python3 pkgs.pandoc ];
            text = ''
              exec python3 ${previewSource}/pandoc/preview-leaflet.py "$@"
            '';
          };
        in {
          preview-leaflet = preview;
          default = preview;
        });

      apps = forAllSystems (system: {
        preview-leaflet = {
          type = "app";
          program = "${self.packages.${system}.preview-leaflet}/bin/preview-leaflet";
        };
        default = self.apps.${system}.preview-leaflet;
      });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [ pkgs.python3 pkgs.pandoc self.packages.${system}.preview-leaflet ];
          };
        });
    };
}
