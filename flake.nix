{
  description = "ai-cage: Landlock-based sandbox for AI coding agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      profiles = import ./lib/profiles.nix;
      tools = import ./lib/tools.nix;
      mkCage = import ./lib/cage.nix;
    in
    {
      lib = {
        inherit profiles tools;
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

          # Test: configDirs produces symlinks and --ro flags for host config paths.
          cage-test-configdirs = self.lib.cage { inherit pkgs; } {
            name = "cage-test-configdirs";
            profile = "aiAgent";
            argv = [ "${pkgs.bash}/bin/bash" "-lc" "echo configdirs OK" ];
            packages = with pkgs; [ bash coreutils ];
            workspace = { path = "$PWD"; };
            tools = [ "opencode" "claude-code" ];
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

          # Verify that the /lib64 nix-ld compatibility path and /proc access
          # are included in the generated wrapper script.
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

            if grep -qF '"--ro" "/proc"' "$script"; then
              echo "PASS: /proc access present in wrapper"
            else
              echo "FAIL: /proc access missing from wrapper"
              exit 1
            fi

            mkdir -p $out
            echo "all checks passed" > $out/result
          '';

          # Verify that configDirs produces the expected symlinks and --ro
          # Landlock rules in the generated wrapper script.
          configdirs = pkgs.runCommand "check-configdirs" { } ''
            script="${self.packages.${system}.cage-test-configdirs}/bin/cage-test-configdirs-cage"

            fail=0

            # 1. All tool configDirs must produce --ro flags pointing at $ORIG_HOME.
            for relpath in .config/opencode .config/claude .claude; do
              if grep -qF "\"--ro\" \"\$ORIG_HOME/$relpath\"" "$script"; then
                echo "PASS: --ro flag for $relpath present"
              else
                echo "FAIL: --ro flag for \$ORIG_HOME/$relpath missing"
                fail=1
              fi
            done

            # 2. .config/opencode must have a symlink into STATE/home/.config/
            if grep -qF 'ln -sfn "$ORIG_HOME/.config/opencode" "$STATE/home/.config/opencode"' "$script"; then
              echo "PASS: home symlink for .config/opencode present"
            else
              echo "FAIL: home symlink for .config/opencode missing"
              fail=1
            fi

            # 3. .config/opencode must ALSO have a symlink into STATE/config/ (XDG)
            if grep -qF 'ln -sfn "$ORIG_HOME/.config/opencode" "$STATE/config/opencode"' "$script"; then
              echo "PASS: XDG_CONFIG_HOME symlink for opencode present"
            else
              echo "FAIL: XDG_CONFIG_HOME symlink for opencode missing"
              fail=1
            fi

            # 4. .config/claude must ALSO have a symlink into STATE/config/ (XDG)
            if grep -qF 'ln -sfn "$ORIG_HOME/.config/claude" "$STATE/config/claude"' "$script"; then
              echo "PASS: XDG_CONFIG_HOME symlink for claude present"
            else
              echo "FAIL: XDG_CONFIG_HOME symlink for claude missing"
              fail=1
            fi

            # 5. .claude must have a home symlink but NOT an XDG symlink
            if grep -qF 'ln -sfn "$ORIG_HOME/.claude" "$STATE/home/.claude"' "$script"; then
              echo "PASS: home symlink for .claude present"
            else
              echo "FAIL: home symlink for .claude missing"
              fail=1
            fi

            if grep -qF '$STATE/config/.claude' "$script"; then
              echo "FAIL: .claude should not have XDG_CONFIG_HOME symlink"
              fail=1
            else
              echo "PASS: .claude correctly has no XDG symlink"
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
