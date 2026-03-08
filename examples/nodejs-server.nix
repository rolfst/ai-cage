# Example: Node.js server project with a caged opencode agent.
#
# This shows a realistic development flake where opencode is sandboxed
# while building and running a Node.js server application. Copilot CLI
# is already installed on the system (e.g. via npm i -g) and made
# available inside the cage via filesystem.rox + env.appendPath.
#
# The devNet profile opens ports 3000/5000/8080 so the agent can start
# the server and test HTTP endpoints. Local environment variables
# (database URLs, secrets, ports) are passed into the cage so the agent
# can run the app, but it still cannot read your ~/.ssh or ~/.aws.
#
# Both opencode and copilot run in the same Landlock sandbox — every
# child process inherits the same restrictions.
#
# Usage:
#   nix develop            # enter the dev shell (no cage)
#   nix run .#opencode     # launch opencode inside the cage
#
# Set your env vars before launching:
#   export ANTHROPIC_API_KEY="sk-..."
#   export GITHUB_TOKEN="ghp_..."
#   export DATABASE_URL="postgres://localhost:5432/myapp"
#   export API_SECRET="my-secret"
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
        name = "opencode-nodejs";

        # devNet allows ports 443, 80, 22, 8080, 3000, 5000 — enough for
        # HTTPS API calls, git over SSH, and local dev server.
        profile = "devNet";

        argv = [ "${pkgs.opencode}/bin/opencode" ];

        # Packages serve two purposes inside the cage:
        # 1. Their store paths get --rox (execute permission) in the Landlock sandbox.
        # 2. Their bin/ dirs are concatenated into PATH.
        # The Nix store is already mounted read-only, but without --rox a binary
        # cannot be executed. Only add packages the agent actually shells out to.
        # Remove any that the tool bundles itself or that you don't need.
        packages = with pkgs; [
          opencode          # the agent itself
          nodejs            # node runtime
          git               # version control
          gh                # GitHub CLI (used by copilot for auth)
          coreutils         # ls, cat, mkdir, etc.
          findutils         # find, xargs
          gnugrep           # grep
          gnused            # sed (used in npm scripts)
          ripgrep           # fast grep (used by many agents)
          fd                # fast find (used by many agents)
          bash              # shell for subprocesses
          curl              # HTTP requests (health checks, API testing)
          jq                # JSON processing
        ];

        filesystem = {
          # Copilot CLI is installed globally via npm (e.g. npm i -g @githubnext/github-copilot-cli).
          # Grant read+execute so the cage can run it.
          rox = [ "$HOME/.npm-global" ];
        };

        env = {
          # Variables the agent needs to call its LLM provider.
          # Add or remove provider keys to match your setup.
          pass = [
            "TERM"
            "LANG"
            "ANTHROPIC_API_KEY"
            "OPENAI_API_KEY"
            "GEMINI_API_KEY"

            # Copilot auth tokens.
            "GITHUB_TOKEN"
            "GH_TOKEN"
            "COPILOT_GITHUB_TOKEN"

            # Node.js / server environment.
            # These are read from your host shell, so the agent can
            # run `npm start` and the server picks up its config.
            "NODE_ENV"
            "PORT"
            "HOST"

            # Database and external services.
            "DATABASE_URL"
            "REDIS_URL"

            # Application secrets.
            # These are visible inside the cage but CANNOT be written
            # to disk or exfiltrated — the agent has no write access
            # outside the workspace and its private state directory.
            "API_SECRET"
            "JWT_SECRET"
            "SESSION_SECRET"
          ];

          # You can also hardcode values instead of passing from the host.
          set = {
            NODE_ENV = "development";
          };

          # Add the npm global bin directory to PATH so opencode can
          # find the `copilot` binary by name (not just by full path).
          appendPath = [ "$HOME/.npm-global/bin" ];
        };
      };

      # A normal dev shell for when you want to work without the cage.
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nodejs
          git
          curl
          jq
        ];
      };
    };
}
