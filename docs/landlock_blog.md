# Sandboxing AI coding agents with Landlock and Nix

Most AI coding agents — Claude Code, GitHub Copilot CLI, Gemini CLI, OpenAI Codex, opencode — run with your full user permissions. They can read your SSH keys, API tokens, credential files, browser cookies, anything in your home directory. If an agent gets tricked by a prompt injection, it can exfiltrate all of it over the network.

This isn't theoretical. The [Clinejection attack](https://adnanthekhan.com/posts/clinejection/) demonstrated exactly this: an attacker plants a malicious prompt in a PR description or a file in the repo. When the agent reads it, it follows injected instructions to steal credentials and send them to a remote server.

I built [ai-cage](https://github.com/rolfst/ai-cage) to reduce this attack surface. It's a reusable Nix flake that uses Landlock with a strict default-deny policy.

## How it works

Landlock is an unprivileged Linux Security Module (LSM) — no root required. It lets a process permanently reduce its own filesystem and network access. ai-cage uses [landrun](https://github.com/Zouuup/landrun) as the wrapper.

When you run an agent inside ai-cage, it gets:

- **A private HOME directory.** Your real home stays hidden.
- **SSH agent forwarding without key file access.** The agent can use your SSH agent socket, but cannot read `~/.ssh/id_*`.
- **Restricted network.** Only explicitly allowed TCP ports (443 + 22 in `aiAgent`).
- **Nix store execute allowlist.** Only package closures you list can execute.
- **Inherited, irreversible restrictions.** Child processes cannot escape the cage.

## Why Landlock instead of containers?

Containers (Docker/Podman/bwrap) isolate via mount namespaces. Landlock keeps the same host filesystem/session and denies disallowed access paths. For AI-assisted local dev, this avoids a lot of friction.

**No UID remapping surprises.** Files created by the agent stay owned by your user, so Git and editor tooling keep working.

**Simpler SSH usage.** No socket bind-mount gymnastics across namespaces; `$SSH_AUTH_SOCK` just works when forwarded.

**Nix-friendly model.** You can expose `/nix/store` as read-only and execute only approved package closures.

**Tradeoff:** Landlock is access control, not full environment virtualization. It does not provide PID/network/mount namespaces.

## Using it

Import `github:rolfst/ai-cage` into your flake and define a cage wrapper:

```nix
caged-agent = ai-cage.lib.cage { inherit pkgs; } {
  name = "claude";
  profile = "aiAgent";
  argv = [ "${pkgs.claude-code}/bin/claude" ];
  packages = with pkgs; [ bashInteractive coreutils git openssh curl ripgrep ];

  filesystem = {
    ro = [ "$ORIG_HOME/.gitconfig" ];
    rw = [ "$ORIG_HOME/.config/claude" ];
  };

  env.pass = [ "ANTHROPIC_API_KEY" ];
};
```

`ai-cage` ships three profiles (`offline`, `aiAgent`, `devNet`) and supports custom profiles.

## 2026 update: hard-earned lessons

- **`/dev` and `/tmp` are mandatory for real workloads.** Restricting too aggressively breaks common tools. ai-cage now explicitly grants safe required device paths and `/tmp` access.
- **Home-directory sibling file visibility exists in Landlock path traversal.** If you allow `--ro $HOME/.gitconfig`, sibling files in `$HOME/` (like `.bashrc`) can become readable. Subdirectories like `.ssh/` and `.gnupg/` remain blocked unless explicitly granted.
- **Best practice:** avoid grants directly in `$HOME/`; copy required config into the cage state dir or grant a narrow subdirectory path instead.

## What it does NOT protect against

I want to be explicit about limitations:

- **Port-only network rules.** Landlock cannot filter by hostname/IP.
- **Env var exfiltration.** If you pass secrets in `env.pass` and allow outbound network, a compromised agent can still transmit those values.
- **No UDP controls.** Landlock network restrictions cover TCP only.
- **Linux-only.** Landlock is a Linux kernel feature.
- **Additive permissions in one ruleset.** You cannot mark one file read-only inside a read-write directory in the same layer.

The goal is practical blast-radius reduction, not perfect containment. A constrained agent is still far safer than a fully privileged shell.

Code: [github.com/rolfst/ai-cage](https://github.com/rolfst/ai-cage)
