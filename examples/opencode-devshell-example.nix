# Example: cage opencode in a development shell with full plugin support
#
# This example demonstrates:
# 1. Using globally-installed opencode (from npm) instead of nixpkgs
# 2. Proper argv setup using appendPath instead of absolute paths
# 3. Advanced plugin isolation with oh-my-opencode
# 4. shellHook for plugin shim fixes and BUN_TMPDIR setup
# 5. Integration into a devShell for project development
#
# Usage:
#   nix develop      # Enter devShell with caged opencode available
#   opencode-cage    # Launch landlocked opencode
{
  description = "Example devShell with landlocked opencode";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    ai-cage.url = "github:rolfst/ai-cage";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ai-cage,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ ai-cage.overlays.default ];
        };

        # Caged opencode that's landlocked via ai-cage
        #
        # IMPORTANT: OpenCode uses plugin systems (npm/bun packages) that require
        # special configuration to work inside ai-cage. See ai-cage documentation:
        # https://github.com/rolfst/ai-cage/blob/main/docs/AI_CAGE_PLUGIN_SETUP.md
        #
        # Key points:
        #   - Plugins MUST be installed in: ~/.local/state/ai-cage/opencode/cache/opencode/
        #   - Versions MUST match host cache: ~/.cache/opencode/
        #   - Update command: cd ~/.local/state/ai-cage/opencode/cache/opencode && bun add <plugin>@<version>
        #
        opencode-caged = ai-cage.lib.cage { inherit pkgs; } {
          name = "opencode";
          profile = "aiAgent";

          # Use globally installed opencode from npm
          # Note: $HOME in argv gets single-quoted by lib.escapeShellArg,
          # preventing expansion. Use just the binary name and let
          # env.appendPath (which does expand $HOME) handle PATH resolution.
          argv = [ "opencode" ];

          packages = with pkgs; [
            # Core development tools
            git
            coreutils
            findutils
            gnugrep
            ripgrep
            fd
            bash

            # Node runtime (opencode needs it for plugins)
            nodejs
            bun
          ];

          filesystem = {
            # OpenCode plugin isolation configuration
            # See ai-cage docs for complete explanation.
            #
            # Key principle: Plugins run from CAGED cache for isolation, but read
            # config and provider data from HOST for functionality.

            # Read+execute access to bun/npm bin directories and opencode tools.
            # /usr needed for shebang resolution (#!/usr/bin/env node)
            rox = [
              "$HOME/.cache/npm"
              "$HOME/.local/share/bun"
              "$HOME/.local/share/opencode"
              "/usr"
            ];

            # Read-only access to npm modules, config, and oh-my-opencode cache.
            # XDG_CONFIG_HOME points to real config for oh-my-opencode plugin list.
            # oh-my-opencode cache contains connected-providers.json and provider-models.json
            # needed for agent functionality.
            ro = [
              "$HOME/.cache/npm/lib"
              "$HOME/.config/opencode/"
              "$HOME/.cache/oh-my-opencode"
            ];

            # Allow npx to write and execute downloaded binaries
            # Allow bun to write its cache and install directory
            # Allow opencode to install plugins into the cage-isolated cache
            rwx = [
              "$HOME/.npm/_npx"
              "$HOME/.bun"
              # ai-cage remaps HOME to $STATE/home inside the cage.
              # opencode installs npm plugins (e.g. oh-my-opencode) via bun into
              # $HOME/.cache/opencode/node_modules/ (hardcoded to HOME, not
              # XDG_CACHE_HOME). Inside the cage that resolves to
              # $STATE/home/.cache/opencode/node_modules/, which needs rwx so
              # bun can write and opencode can execute the installed modules.
              # The blanket --rw $STATE from ai-cage does NOT grant execute.
              "$HOME/.local/state/ai-cage/opencode/home/.cache"
              # bun writes to its cage-home dir ($STATE/home/.bun) which is
              # covered by --rw $STATE, but needs execute for bun internals.
              "$HOME/.local/state/ai-cage/opencode/home/.bun"
              # XDG_CACHE_HOME=$STATE/cache — keep rwx here too for any other
              # opencode/bun paths that do respect XDG_CACHE_HOME.
              "$HOME/.local/state/ai-cage/opencode/cache"
              # BUN_TMPDIR: same-filesystem temp dir to avoid cross-mount rename.
              # Created in shellHook; must be rwx so bun can write and execute.
              "$HOME/.local/state/ai-cage/opencode/tmp"
            ];
          };

          env = {
            pass = [
              "TERM"
              "LANG"
              "ANTHROPIC_API_KEY"
              "OPENAI_API_KEY"
              "GEMINI_API_KEY"
            ];

            # CRITICAL: Plugin cache isolation
            # See ai-cage docs for why this matters.
            #
            # Override XDG_CONFIG_HOME to point to real config (for plugin list).
            # XDG_CACHE_HOME points to caged cache ($STATE/cache) where
            # oh-my-opencode plugins are installed in isolation.
            #
            # This means:
            #   - OpenCode reads config from: ~/.config/opencode/opencode.json (host)
            #   - OpenCode loads plugins from: ~/.local/state/ai-cage/opencode/cache/opencode/node_modules/ (cage)
            #   - Plugins MUST be installed in caged cache with matching versions
            #
            # To install/update plugins in caged cache:
            #   cd ~/.local/state/ai-cage/opencode/cache/opencode
            #   bun add oh-my-opencode@<version> opencode-anthropic-auth@<version>
            #
            # $ORIG_HOME is set by ai-cage to the real HOME before remapping.
            # ai-cage merges env.set XDG keys at Nix evaluation time, so only
            # one --env flag per key is passed to landrun (no duplicate issue).
            #
            # BUN_TMPDIR: Bun defaults to /tmp for staging downloaded packages,
            # then renames them into XDG_CACHE_HOME. Since /tmp is tmpfs and
            # the cache dir is on /dev/mapper/cryptroot (different mount),
            # cross-mount rename fails with RenameAcrossMountPoints. Setting
            # BUN_TMPDIR to a path on the same filesystem as the cache fixes
            # this. The directory is created in shellHook before cage launch.
            set = {
              XDG_CONFIG_HOME = "$ORIG_HOME/.config";
              XDG_CACHE_HOME = "$STATE/cache";
              BUN_TMPDIR = "$ORIG_HOME/.local/state/ai-cage/opencode/tmp";
            };

            # Add bun and npm bin to PATH
            # This allows argv = ["opencode"] to work without absolute paths
            appendPath = [
              "$HOME/.cache/npm/bin"
              "$HOME/.local/share/bun/bin"
            ];
          };

          # Declare which AI tool runs in this cage.
          # The tool registry (lib/tools.nix in ai-cage) automatically exposes
          # the correct host config directories read-only inside the sandbox.
          tools = [ "opencode" ];
        };
      in
      {
        # Landlocked opencode as app
        apps.default = {
          type = "app";
          program = "${opencode-caged}/bin/opencode-cage";
        };

        packages = {
          # Landlocked opencode wrapper
          opencode-caged = opencode-caged;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            # Your project tools here (example: Go toolchain)
            # pkgs.go_1_24

            # Git and version control
            pkgs.git

            # Landlocked opencode
            opencode-caged
            pkgs.bun
          ];

          shellHook = ''
            echo "Development environment with landlocked OpenCode"
            echo "================================================="
            echo ""
            echo "Landlocked OpenCode: opencode-cage (via ai-cage)"
            echo "  - Workspace access: current directory only"
            echo "  - Network: HTTPS (443) and SSH (22) only"
            echo "  - Home: isolated at ~/.local/state/ai-cage/opencode/"
            echo ""
            echo "Start landlocked OpenCode:"
            echo "  opencode-cage          (directly, available in devshell)"
            echo "  nix run .#             (via flake app)"
            echo ""

            # Create BUN_TMPDIR on the same filesystem as the cage cache to
            # avoid cross-mount rename failures when bun installs packages.
            mkdir -p "$HOME/.local/state/ai-cage/opencode/tmp"

            # Shim fix: Bun's compiled binary (opencode) cannot resolve
            # directory imports via package.json exports/main fields for paths
            # outside the bundle. When opencode does `await import(pluginDir)`,
            # bun needs an index.js at the directory root. oh-my-opencode ships
            # only dist/index.js (declared via "main"/"exports"), so we drop a
            # thin re-export shim at the package root. This is re-written on
            # every shell entry to survive bun reinstalls.
            OMC_DIR="$HOME/.local/state/ai-cage/opencode/cache/opencode/node_modules/oh-my-opencode"
            if [[ -d "$OMC_DIR/dist" ]]; then
              cat > "$OMC_DIR/index.js" <<'SHIM'
export * from './dist/index.js';
SHIM
              echo "oh-my-opencode shim written to $OMC_DIR/index.js"
            fi
          '';
        };
      }
    );
}
