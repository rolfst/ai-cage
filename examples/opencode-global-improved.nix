# Example: cage globally-installed opencode with improved argv setup
#
# This example shows the recommended pattern for caging a globally-installed
# binary (via npm/bun) without using absolute paths in argv.
#
# Key improvements over basic examples:
# 1. argv = ["opencode"] instead of ["$HOME/.cache/npm/bin/opencode"]
# 2. Uses env.appendPath to add binary directories to PATH
# 3. Cleaner, more portable configuration
#
# Prerequisites:
#   - opencode installed globally: npm i -g opencode-ai
#
# Usage:
#   nix run .#opencode-global

{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ai-cage.url = "github:rolfst/ai-cage";
  };

  outputs =
    {
      nixpkgs,
      ai-cage,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ ai-cage.overlays.default ];
      };
    in
    {
      packages.${system}.opencode-global = ai-cage.lib.cage { inherit pkgs; } {
        name = "opencode-global";
        profile = "aiAgent";

        # Use just the binary name instead of absolute path
        #
        # IMPORTANT: Don't use "$HOME/.cache/npm/bin/opencode" in argv
        # because $HOME gets single-quoted by lib.escapeShellArg and won't expand.
        #
        # Instead, use the binary name and let env.appendPath handle resolution.
        argv = [ "opencode" ];

        # Packages that the agent shells out to
        packages = with pkgs; [
          git # version control
          coreutils # ls, cat, mkdir, etc.
          findutils # find, xargs
          gnugrep # grep
          ripgrep # fast grep
          fd # fast find
          bash # shell for subprocesses
          nodejs # runtime for plugins
          bun # package manager for plugins
        ];

        filesystem = {
          # Grant read+execute access to globally-installed binaries
          rox = [
            "$HOME/.cache/npm" # npm global install location
            "$HOME/.local/share/bun" # bun global install location
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

          # Add npm/bun bin directories to PATH
          # This allows argv = ["opencode"] to resolve correctly
          # env.appendPath DOES expand $HOME (unlike argv)
          appendPath = [
            "$HOME/.cache/npm/bin"
            "$HOME/.local/share/bun/bin"
          ];
        };

        # Declare which AI tool runs in this cage
        # Automatically exposes ~/.config/opencode read-only
        tools = [ "opencode" ];
      };
    };
}
