# Example: cage opencode (from nixpkgs) inside a consumer flake.
#
# Usage:
#   nix run .#opencode
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
      packages.${system}.opencode = ai-cage.lib.cage { inherit pkgs; } {
        name = "opencode";
        profile = "aiAgent";
        argv = [ "${pkgs.opencode}/bin/opencode" ];

        # Packages serve two purposes inside the cage:
        # 1. Their store paths get --rox (execute permission) in the Landlock sandbox.
        # 2. Their bin/ dirs are concatenated into PATH.
        # The Nix store is already mounted read-only, but without --rox a binary
        # cannot be executed. Only add packages the agent actually shells out to.
        # Remove any that the tool bundles itself or that you don't need.
        packages = with pkgs; [
          opencode          # the agent itself
          git               # version control
          coreutils         # ls, cat, mkdir, etc.
          findutils         # find, xargs
          gnugrep           # grep
          ripgrep           # fast grep (used by many agents)
          fd                # fast find (used by many agents)
          bash              # shell for subprocesses
        ];

        env = {
          pass = [ "TERM" "LANG" "ANTHROPIC_API_KEY" "OPENAI_API_KEY" "GEMINI_API_KEY" ];
        };
      };
    };
}
