# Example: cage GitHub Copilot CLI inside a consumer flake.
#
# Usage:
#   nix run .#copilot
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
      packages.${system}.copilot = ai-cage.lib.cage { inherit pkgs; } {
        name = "copilot-cli";
        profile = "aiAgent";
        argv = [ "${pkgs.github-copilot-cli}/bin/copilot" ];

        # Packages serve two purposes inside the cage:
        # 1. Their store paths get --rox (execute permission) in the Landlock sandbox.
        # 2. Their bin/ dirs are concatenated into PATH.
        # The Nix store is already mounted read-only, but without --rox a binary
        # cannot be executed. Only add packages the agent actually shells out to.
        # Remove any that the tool bundles itself or that you don't need.
        packages = with pkgs; [
          github-copilot-cli # the agent itself
          git               # version control
          gh                # GitHub CLI (for auth and API access)
          coreutils         # ls, cat, mkdir, etc.
          findutils         # find, xargs
          gnugrep           # grep
          ripgrep           # fast grep (used by many agents)
          fd                # fast find (used by many agents)
          bash              # shell for subprocesses
        ];

        env = {
          pass = [ "TERM" "LANG" "GITHUB_TOKEN" "GH_TOKEN" "COPILOT_GITHUB_TOKEN" ];
        };

        # Declare which AI tool(s) run in this cage.  The tool registry
        # (lib/tools.nix) automatically exposes the correct host config
        # directories read-only inside the sandbox.
        tools = [ "copilot-cli" ];
      };
    };
}
