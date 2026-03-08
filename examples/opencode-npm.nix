# Example: cage opencode fetched from the npm registry inside a consumer flake.
#
# This fetches the platform-specific Go binary directly from npm instead of
# using the nixpkgs package. Useful when you need a specific version.
#
# Usage:
#   nix run .#opencode-npm
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

      version = "1.2.21";

      opencode-from-npm = pkgs.stdenvNoCC.mkDerivation {
        pname = "opencode";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/opencode-linux-x64/-/opencode-linux-x64-${version}.tgz";
          hash = "sha256-N2HZC4PuILz/bNM7Ns1tM2jJo9WgpY5DIgXPKK50vzc=";
        };

        sourceRoot = ".";

        installPhase = ''
          mkdir -p $out/bin
          cp package/bin/opencode $out/bin/opencode
          chmod +x $out/bin/opencode
        '';

        meta = {
          description = "AI coding agent (installed from npm)";
          homepage = "https://github.com/anomalyco/opencode";
          platforms = [ "x86_64-linux" ];
          mainProgram = "opencode";
        };
      };

    in {
      packages.${system}.opencode-npm = ai-cage.lib.cage { inherit pkgs; } {
        name = "opencode-npm";
        profile = "aiAgent";
        argv = [ "${opencode-from-npm}/bin/opencode" ];

        # Packages serve two purposes inside the cage:
        # 1. Their store paths get --rox (execute permission) in the Landlock sandbox.
        # 2. Their bin/ dirs are concatenated into PATH.
        # The Nix store is already mounted read-only, but without --rox a binary
        # cannot be executed. Only add packages the agent actually shells out to.
        # Remove any that the tool bundles itself or that you don't need.
        packages = [
          opencode-from-npm   # the agent itself (fetched from npm registry)
          pkgs.git            # version control
          pkgs.coreutils      # ls, cat, mkdir, etc.
          pkgs.findutils      # find, xargs
          pkgs.gnugrep        # grep
          pkgs.ripgrep        # fast grep (used by many agents)
          pkgs.fd             # fast find (used by many agents)
          pkgs.bash           # shell for subprocesses
        ];

        env = {
          pass = [ "TERM" "LANG" "ANTHROPIC_API_KEY" "OPENAI_API_KEY" "GEMINI_API_KEY" ];
        };
      };
    };
}
