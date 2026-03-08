{
  description = "ai-cage: Landlock-based sandbox for AI coding agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      profiles = import ./lib/profiles.nix;
      mkCage = import ./lib/cage.nix;
    in
    {
      lib = {
        inherit profiles;
        # Consumer usage:
        # ai-cage.lib.cage { inherit pkgs; } { name = "foo"; ... }
        cage = { pkgs }:
          mkCage {
            inherit pkgs;
            lib = pkgs.lib;
          };
      };

      overlays.default = final: prev: {
        landrun = final.callPackage ./pkgs/landrun.nix { };
      };
    }
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
      in
      {
        packages = {
          landrun = pkgs.landrun;

          # Example caged command for quick testing.
          cage-test = self.lib.cage { inherit pkgs; } {
            name = "cage-test";
            profile = "aiAgent";
            argv = [ "${pkgs.bash}/bin/bash" "-lc" "echo ai-cage OK" ];
            packages = with pkgs; [ bash coreutils ];
            workspace = { path = "$PWD"; };
          };

          default = pkgs.landrun;
        };

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.landrun pkgs.nixpkgs-fmt ];
        };
      });
}
