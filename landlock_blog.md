# Sandboxing AI coding agents with Landlock and Nix

Most AI coding agents — Claude Code, GitHub Copilot CLI, Gemini CLI, OpenAI Codex, opencode — run with your full user permissions. They can read your SSH keys, API tokens, credential files, browser cookies, anything in your home directory. If an agent gets tricked by a prompt injection, it can exfiltrate all of it over the network.

This isn't theoretical. The [Clinejection attack](https://adnanthekhan.com/posts/clinejection/) demonstrated exactly this: an attacker plants a malicious prompt in a PR description or a file in the repo. When the agent reads it, it follows the injected instructions to steal credentials and send them to a remote server. The agent has your permissions, so it succeeds.

I built [ai-cage](https://github.com/rolfst/ai-cage) to reduce this attack surface. It's a reusable Nix flake that uses the Landlock Linux Security Module to sandbox AI coding agents with a default-deny policy.

## How it works

Landlock is an unprivileged LSM — no root required. It lets a process permanently restrict its own filesystem and network access. I use [landrun](https://github.com/Zouuup/landrun) as the CLI wrapper.

When you run an agent inside ai-cage, it gets:

- **A private HOME directory.** Your real home stays hidden. The agent sees only its own isolated state directory.
- **SSH agent forwarding without key file access.** The agent can `git push` over SSH via the agent socket, but it cannot read `~/.ssh/id_*` from disk.
- **Restricted network.** Only explicitly allowed ports — 443 and 22 by default.
- **Nix store execute whitelist.** Only the packages you list get execute permission. Everything else in the store is read-only.
- **Permanent, inherited restrictions.** Once the cage is active, every child process inherits the rules. They cannot be lifted — not by the agent, not by anything it spawns.

## Why Landlock instead of containers?

The first question most people will ask. Containers (Docker, Podman, bubblewrap) create full filesystem isolation using mount namespaces — you build a separate root filesystem, then bind-mount in what you need. Landlock works the opposite way: your process stays in the same filesystem, but the kernel denies access to paths you didn't allow. For AI coding agents, this difference matters a lot.

**The bind mount pain.** Rootless containers remap UIDs via user namespaces. When you bind-mount your project directory into a Podman container, files created inside can appear as `nobody:nogroup` on the host. Git breaks because `.git/config` has strict ownership requirements. File watchers (inotify) don't reliably propagate across mount boundaries, so LSP servers and tools like `nodemon` stop working. With Landlock there's no UID remapping and no mount boundary — the agent runs as your UID in your filesystem. Files it creates are owned by you. Git just works.

**SSH agent forwarding.** Containers require you to bind-mount `$SSH_AUTH_SOCK` and get the socket permissions right across the UID namespace boundary. Rootless Podman's docs devote entire sections to this because it's genuinely hard. With Landlock, the agent shares your session — `$SSH_AUTH_SOCK` just works because there's no namespace boundary to cross.

**Nix integration.** Running Nix tools inside a container means either bind-mounting `/nix/store` (coupling the container to the host store) or running a Nix daemon inside (slow, duplicates store content). With Landlock you just allow read access to `/nix/store` — no daemon, no bind mounts, no duplication. The entire cage definition is ~50 lines of Nix.

**The tradeoff.** Landlock only does access control. No PID namespace (the agent can see host processes), no network namespace (it shares your network stack), no mount isolation. If you need full environment isolation, containers are the right tool. But for "let the AI edit my code without reading my SSH keys" — Landlock's access control is sufficient and eliminates all the container plumbing.

## Using it

Import `github:rolfst/ai-cage` into your flake and define your cage:

```nix
caged-agent = ai-cage.lib.cage { inherit pkgs; } {
  name = "claude";
  profile = "aiAgent";           # preset: HTTPS + SSH + private HOME
  argv = [ "${pkgs.claude-code}/bin/claude" ];
  packages = with pkgs; [ bashInteractive coreutils git openssh curl ripgrep ];

  filesystem = {
    ro = [ "$ORIG_HOME/.gitconfig" ];
    rw = [ "$ORIG_HOME/.config/claude" ];
  };

  env.pass = [ "ANTHROPIC_API_KEY" ];
};
```

The flake ships three profiles (`offline`, `aiAgent`, `devNet`) and supports fully custom ones. The output is a wrapper script you run instead of the bare agent binary.

## What it does NOT protect against

I want to be upfront about the limitations:

- **Network filtering is port-only.** Landlock cannot filter by IP or hostname. The agent can talk to any server on the allowed ports. For IP-level filtering you'd need nftables or network namespaces (which require root).
- **Env var exfiltration.** If you pass API keys into the cage, the agent could send them over an allowed port. Landlock can't inspect traffic content.
- **No UDP restriction.** Landlock's network controls only cover TCP. DNS (UDP 53) works unfiltered.
- **Linux-only.** Landlock is a Linux kernel feature. You need kernel 6.7+ for network support.
- **Additive permissions within a layer.** You can't make a single file read-only inside a read-write directory within the same Landlock ruleset.

The goal is to shrink the blast radius of a prompt injection — not to make it impossible. An agent that can't touch your SSH keys, can't browse your home directory, and can only reach two ports is a much harder target than one running with your full shell.

Code: [github.com/rolfst/ai-cage](https://github.com/rolfst/ai-cage)
