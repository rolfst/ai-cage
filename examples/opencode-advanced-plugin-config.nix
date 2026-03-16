# Example: cage globally-installed opencode with advanced plugin support and devShell integration
#
# This example demonstrates best practices for caging opencode when:
# - Using globally-installed opencode via npm (not nixpkgs)
# - Working with oh-my-opencode plugins that require special setup
# - Integrating into a development workflow with devShell
# - Handling bun/npm binary resolution without absolute paths
#
# Key improvements over basic examples:
# 1. argv uses binary name instead of absolute path (cleaner, more portable)
# 2. Comprehensive plugin isolation setup for oh-my-opencode
# 3. shellHook handles plugin shim fixes and BUN_TMPDIR creation
# 4. Production-ready configuration used in real projects
#
# Prerequisites:
#   - opencode installed globally: npm i -g opencode-ai
#   - Plugins installed in host: cd ~/.cache/opencode && bun add oh-my-opencode opencode-anthropic-auth
#   - Plugins synced to cage: cd ~/.local/state/ai-cage/opencode/cache/opencode && bun add oh-my-opencode@<version> opencode-anthropic-auth@<version>
#
# Usage:
#   nix develop      # Enter devShell with caged opencode available
#   opencode-cage    # Launch landlocked opencode
#
# For detailed plugin setup instructions, see:
# https://github.com/rolfst/ai-cage/blob/main/docs/AI_CAGE_PLUGIN_SETUP.md

{
  description = "Advanced opencode cage with plugin support";

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

        # Caged opencode with advanced plugin configuration
        #
        # This configuration assumes opencode is installed globally via:
        #   npm i -g opencode-ai
        #
        # The binary will be at ~/.cache/npm/bin/opencode or ~/.local/share/bun/bin/opencode
        # depending on your package manager choice.
        opencode-caged = ai-cage.lib.cage { inherit pkgs; } {
          name = "opencode";
          profile = "aiAgent";

          # Use globally installed opencode from npm/bun
          #
          # IMPORTANT: Don't use absolute paths like "$HOME/.cache/npm/bin/opencode"
          # because $HOME gets single-quoted by lib.escapeShellArg, preventing expansion.
          #
          # Instead, use just the binary name and let env.appendPath handle resolution.
          # The appendPath option DOES expand $HOME correctly.
          argv = [ "opencode" ];

          # Packages serve two purposes inside the cage:
          # 1. Their store paths get --rox (execute permission) in Landlock sandbox
          # 2. Their bin/ dirs are concatenated into PATH
          #
          # Only include packages the agent actually shells out to.
          # opencode itself is NOT in this list - it's installed globally.
          packages = with pkgs; [
            # Core development tools
            git # version control
            coreutils # ls, cat, mkdir, etc.
            findutils # find, xargs
            gnugrep # grep
            ripgrep # fast grep (used by many agents)
            fd # fast find (used by many agents)
            bash # shell for subprocesses

            # Node runtime (opencode plugins need this)
            nodejs
            bun
          ];

          filesystem = {
            # OpenCode plugin isolation configuration
            #
            # Key principle: Plugins run from CAGED cache for isolation, but read
            # config and provider data from HOST for functionality.
            #
            # See AI_CAGE_PLUGIN_SETUP.md for detailed explanation:
            # https://github.com/rolfst/ai-cage/blob/main/docs/AI_CAGE_PLUGIN_SETUP.md

            # Read+execute access for binaries and shebang resolution
            rox = [
              "$HOME/.cache/npm" # npm global binaries
              "$HOME/.local/share/bun" # bun global binaries
              "$HOME/.local/share/opencode" # opencode data
              "/usr" # Required for #!/usr/bin/env node
            ];

            # Read-only access to config and plugin data
            ro = [
              "$HOME/.cache/npm/lib" # npm modules
              "$HOME/.config/opencode/" # OpenCode config (plugin list, agent definitions)
              "$HOME/.cache/oh-my-opencode" # oh-my-opencode provider data
            ];

            # Read+write+execute in caged directories
            rwx = [
              "$HOME/.npm/_npx" # npx downloads
              "$HOME/.bun" # bun cache

              # ai-cage remaps HOME to $STATE/home inside the cage.
              # opencode installs plugins to $HOME/.cache/opencode/node_modules/
              # (hardcoded to HOME, not XDG_CACHE_HOME).
              # Inside cage: $STATE/home/.cache/opencode/node_modules/
              # Needs rwx so bun can write and opencode can execute plugins.
              "$HOME/.local/state/ai-cage/opencode/home/.cache"

              # bun writes to $STATE/home/.bun (covered by --rw $STATE from ai-cage)
              # but needs execute permission for bun internals
              "$HOME/.local/state/ai-cage/opencode/home/.bun"

              # XDG_CACHE_HOME=$STATE/cache - keep rwx for opencode/bun paths
              # that respect XDG_CACHE_HOME
              "$HOME/.local/state/ai-cage/opencode/cache"

              # BUN_TMPDIR: same-filesystem temp dir to avoid cross-mount rename errors
              # Created in shellHook; must be rwx for bun package installs
              "$HOME/.local/state/ai-cage/opencode/tmp"
            ];
          };

          env = {
            # Pass through API keys and essential env vars
            pass = [
              "TERM"
              "LANG"
              "ANTHROPIC_API_KEY"
              "OPENAI_API_KEY"
              "GEMINI_API_KEY"
            ];

            # CRITICAL: Plugin cache isolation
            #
            # Override XDG_CONFIG_HOME to read host config (for plugin list).
            # XDG_CACHE_HOME points to caged cache where plugins are installed.
            #
            # This means:
            #   - OpenCode reads config: ~/.config/opencode/opencode.json (host)
            #   - OpenCode loads plugins: ~/.local/state/ai-cage/opencode/cache/opencode/node_modules/ (cage)
            #   - Plugins MUST be installed in caged cache with matching versions
            #
            # To install/update plugins in caged cache:
            #   cd ~/.local/state/ai-cage/opencode/cache/opencode
            #   bun add oh-my-opencode@<version> opencode-anthropic-auth@<version>
            #
            # $ORIG_HOME is set by ai-cage to real HOME before remapping.
            #
            # BUN_TMPDIR: Bun defaults to /tmp for staging packages, then renames
            # to XDG_CACHE_HOME. Since /tmp is tmpfs and cache is on disk (different
            # filesystem), rename fails with RenameAcrossMountPoints. Setting
            # BUN_TMPDIR to same filesystem as cache fixes this.
            set = {
              XDG_CONFIG_HOME = "$ORIG_HOME/.config";
              XDG_CACHE_HOME = "$STATE/cache";
              BUN_TMPDIR = "$ORIG_HOME/.local/state/ai-cage/opencode/tmp";
            };

            # Add npm/bun bin directories to PATH
            # This allows argv = ["opencode"] to work without absolute paths
            # env.appendPath DOES expand $HOME (unlike argv which doesn't)
            appendPath = [
              "$HOME/.cache/npm/bin"
              "$HOME/.local/share/bun/bin"
            ];
          };

          # Declare which AI tool runs in this cage.
          # The tool registry (lib/tools.nix) automatically exposes
          # ~/.config/opencode read-only inside the sandbox.
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

        # Development shell with landlocked opencode
        devShells.default = pkgs.mkShell {
          buildInputs = [
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
            echo "  opencode-cage    (directly)"
            echo "  nix run .#       (via flake app)"
            echo ""

            # Create BUN_TMPDIR on the same filesystem as cage cache to
            # avoid cross-mount rename failures when bun installs packages.
            mkdir -p "$HOME/.local/state/ai-cage/opencode/tmp"

            # oh-my-opencode plugin shim fix
            #
            # Bun's compiled binary (opencode) cannot resolve directory imports
            # via package.json exports/main fields for paths outside the bundle.
            # When opencode does `await import(pluginDir)`, bun needs an index.js
            # at the directory root.
            #
            # oh-my-opencode ships only dist/index.js (declared via "main"/"exports"),
            # so we create a thin re-export shim at package root. This is re-written
            # on every shell entry to survive bun reinstalls.
            OMC_DIR="$HOME/.local/state/ai-cage/opencode/cache/opencode/node_modules/oh-my-opencode"
            if [[ -d "$OMC_DIR/dist" ]]; then
              cat > "$OMC_DIR/index.js" <<'SHIM'
export * from './dist/index.js';
SHIM
              echo "✓ oh-my-opencode shim created at $OMC_DIR/index.js"
            else
              echo "⚠ oh-my-opencode not found - install with:"
              echo "  cd ~/.local/state/ai-cage/opencode/cache/opencode"
              echo "  bun add oh-my-opencode@<version>"
            fi
          '';
        };
      }
    );
}
