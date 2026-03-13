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

          # Test: ro path under rox parent should be promoted to rox.
          # This reproduces the bug where filesystem.ro = [ "$HOME/.cache/npm/lib" ]
          # silently strips execute from a parent filesystem.rox = [ "$HOME/.cache/npm" ].
          cage-test-ro-rox-overlap = self.lib.cage { inherit pkgs; } {
            name = "cage-test-ro-rox";
            profile = "aiAgent";
            argv = [ "${pkgs.bash}/bin/bash" "-lc" "echo ro-rox-overlap OK" ];
            packages = with pkgs; [ bash coreutils ];
            workspace = { path = "$PWD"; };
            filesystem = {
              rox = [ "$HOME/.cache/npm" ];
              ro = [ "$HOME/.cache/npm/lib" ];
            };
          };

          # Test: profile ro paths must survive when user also supplies filesystem.ro.
          # This reproduces the DNS resolution bug where aiAgent's /etc/resolv.conf
          # was silently dropped when the user set filesystem.ro for their own paths.
          cage-test-profile-ro-merge = self.lib.cage { inherit pkgs; } {
            name = "cage-test-profile-merge";
            profile = "aiAgent";
            argv = [ "${pkgs.bash}/bin/bash" "-lc" "echo profile-merge OK" ];
            packages = with pkgs; [ bash coreutils ];
            workspace = { path = "$PWD"; };
            filesystem = {
              ro = [ "$HOME/.cache/npm/lib" ];
            };
          };

          default = pkgs.landrun;
        };

        checks = {
          # Verify that ro paths under rox parents are promoted to --rox
          # in the generated wrapper script (not emitted as --ro).
          ro-rox-promotion = pkgs.runCommand "check-ro-rox-promotion" { } ''
            script="${self.packages.${system}.cage-test-ro-rox-overlap}/bin/cage-test-ro-rox-cage"

            # The script must contain --rox for the npm/lib path (promoted),
            # not --ro.  grep -F for the literal flag + path combo.
            if grep -qF '"--rox" "$HOME/.cache/npm/lib"' "$script"; then
              echo "PASS: ro path under rox parent was promoted to rox"
            else
              echo "FAIL: expected --rox for \$HOME/.cache/npm/lib but found:"
              grep 'npm/lib' "$script" || true
              exit 1
            fi

            # Also verify the parent rox is still present.
            if grep -qF '"--rox" "$HOME/.cache/npm"' "$script"; then
              echo "PASS: parent rox path preserved"
            else
              echo "FAIL: parent rox path missing"
              exit 1
            fi

            mkdir -p $out
            echo "all checks passed" > $out/result
          '';

          # Verify that the /lib64 nix-ld compatibility path is included in
          # the generated wrapper script (conditional on /lib64 existing).
          nix-ld-compat = pkgs.runCommand "check-nix-ld-compat" { } ''
            script="${self.packages.${system}.cage-test}/bin/cage-test-cage"

            if grep -qF '/lib64' "$script"; then
              echo "PASS: /lib64 nix-ld compatibility path present in wrapper"
            else
              echo "FAIL: /lib64 nix-ld compatibility path missing from wrapper"
              echo "--- relevant section ---"
              grep -n 'lib64\|nix-ld\|Essential' "$script" || true
              exit 1
            fi

            mkdir -p $out
            echo "all checks passed" > $out/result
          '';

          # Verify that profile-provided ro paths (like /etc/resolv.conf from
          # aiAgent) are preserved when the user also provides filesystem.ro.
          profile-ro-merge = pkgs.runCommand "check-profile-ro-merge" { } ''
            script="${self.packages.${system}.cage-test-profile-ro-merge}/bin/cage-test-profile-merge-cage"

            fail=0

            # The aiAgent profile contributes /etc/resolv.conf — it must survive.
            for path in /etc/resolv.conf /etc/hosts /etc/nsswitch.conf /etc/passwd /etc/group; do
              if grep -qF "\"$path\"" "$script"; then
                echo "PASS: profile ro path $path preserved"
              else
                echo "FAIL: profile ro path $path missing from generated script"
                fail=1
              fi
            done

            # The user's own ro path must also be present.
            if grep -q 'npm/lib' "$script"; then
              echo "PASS: user ro path \$HOME/.cache/npm/lib present"
            else
              echo "FAIL: user ro path \$HOME/.cache/npm/lib missing"
              fail=1
            fi

            if [[ "$fail" -ne 0 ]]; then
              echo ""
              echo "--- full script for debugging ---"
              cat "$script"
              exit 1
            fi

            mkdir -p $out
            echo "all checks passed" > $out/result
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.landrun pkgs.nixpkgs-fmt ];
        };
      });
}
