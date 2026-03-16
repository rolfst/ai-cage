# Example: cage an opencode binary installed via `npm i -g opencode-ai`.
#
# The binary lives outside the Nix store (e.g. ~/.npm-global/bin/opencode),
# so we use filesystem.rox to grant it read+execute access.
#
# Prerequisites:
#   npm config set prefix ~/.npm-global
#   npm i -g opencode-ai
#
# Usage:
#   nix run .#opencode-global
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ai-cage.url = "github:rolfst/ai-cage";
  };

  outputs = { nixpkgs, ai-cage, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ ai-cage.overlays.default ];
      };
    in {
      packages.${system}.opencode-global = ai-cage.lib.cage { inherit pkgs; } {
        name = "opencode-global";
        profile = "aiAgent";

        # Point argv at the externally-installed binary.
        argv = [ "$HOME/.npm-global/bin/opencode" ];

        # Packages serve two purposes inside the cage:
        # 1. Their store paths get --rox (execute permission) in the Landlock sandbox.
        # 2. Their bin/ dirs are concatenated into PATH.
        # The Nix store is already mounted read-only, but without --rox a binary
        # cannot be executed. Only add packages the agent actually shells out to.
        # Remove any that the tool bundles itself or that you don't need.
        #
        # The opencode binary itself is NOT in this list — it lives outside the
        # store and is granted execute access via filesystem.rox below.
        packages = with pkgs; [
          git               # version control
          coreutils         # ls, cat, mkdir, etc.
          findutils         # find, xargs
          gnugrep           # grep
          ripgrep           # fast grep (used by many agents)
          fd                # fast find (used by many agents)
          bash              # shell for subprocesses
          nodejs            # node runtime (if the binary needs it)
        ];

        filesystem = {
          # Grant read+execute to the npm global prefix so landrun allows execution.
          rox = [ "$HOME/.npm-global" ];

          # The binary may need to read its own node_modules at runtime.
          ro = [ "$HOME/.npm-global/lib" ];
        };

        env = {
          pass = [ "TERM" "LANG" "ANTHROPIC_API_KEY" "OPENAI_API_KEY" "GEMINI_API_KEY" ];

          # Add the npm global bin directory to PATH so the cage can
          # find the opencode binary by name, not just by full path.
          appendPath = [ "$HOME/.npm-global/bin" ];
        };

        # Declare which AI tool(s) run in this cage.  The tool registry
        # (lib/tools.nix) automatically exposes the correct host config
        # directories read-only inside the sandbox.
        tools = [ "opencode" ];
      };
    };
}
