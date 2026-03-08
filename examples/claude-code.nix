# Example: cage Claude Code inside a consumer flake.
#
# Usage:
#   nix run .#claude
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
      packages.${system}.claude = ai-cage.lib.cage { inherit pkgs; } {
        name = "claude-code";
        profile = "aiAgent";
        argv = [ "${pkgs.claude-code}/bin/claude" ];

        # Packages serve two purposes inside the cage:
        # 1. Their store paths get --rox (execute permission) in the Landlock sandbox.
        # 2. Their bin/ dirs are concatenated into PATH.
        # The Nix store is already mounted read-only, but without --rox a binary
        # cannot be executed. Only add packages the agent actually shells out to.
        # Remove any that the tool bundles itself or that you don't need.
        packages = with pkgs; [
          claude-code       # the agent itself
          git               # version control
          coreutils         # ls, cat, mkdir, etc.
          findutils         # find, xargs
          gnugrep           # grep
          ripgrep           # fast grep (used by many agents)
          fd                # fast find (used by many agents)
          bash              # shell for subprocesses
        ];

        env = {
          pass = [ "TERM" "LANG" "ANTHROPIC_API_KEY" ];
        };
      };
    };
}
