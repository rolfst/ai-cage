# Example: cage OpenAI Codex inside a consumer flake.
#
# Codex uses port 1455 for its OAuth login callback.
#
# Usage:
#   nix run .#codex
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
      packages.${system}.codex = ai-cage.lib.cage { inherit pkgs; } {
        name = "codex";
        profile = "aiAgent";
        argv = [ "${pkgs.codex}/bin/codex" ];

        # Packages serve two purposes inside the cage:
        # 1. Their store paths get --rox (execute permission) in the Landlock sandbox.
        # 2. Their bin/ dirs are concatenated into PATH.
        # The Nix store is already mounted read-only, but without --rox a binary
        # cannot be executed. Only add packages the agent actually shells out to.
        # Remove any that the tool bundles itself or that you don't need.
        packages = with pkgs; [
          codex             # the agent itself
          git               # version control
          coreutils         # ls, cat, mkdir, etc.
          findutils         # find, xargs
          gnugrep           # grep
          ripgrep           # fast grep (used by many agents)
          fd                # fast find (used by many agents)
          bash              # shell for subprocesses
        ];

        network = { connectTcp = [ 443 22 1455 ]; };

        env = {
          pass = [ "TERM" "LANG" "OPENAI_API_KEY" ];
        };

        # Declare which AI tool(s) run in this cage.  The tool registry
        # (lib/tools.nix) automatically exposes the correct host config
        # directories read-only inside the sandbox.
        tools = [ "codex" ];
      };
    };
}
