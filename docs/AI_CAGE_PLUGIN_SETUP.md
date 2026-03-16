# Using OpenCode (and similar AI assistants) with ai-cage

This document explains how to properly configure [ai-cage](https://github.com/antithesishq/ai-cage) for AI coding assistants that use plugin systems with npm/bun packages, such as OpenCode, Claude Desktop, Cursor, etc.

## The Problem

When running OpenCode inside ai-cage with Landlock sandboxing, you may encounter issues where:
- Plugins fail to load
- Agents/subagents don't appear in the UI (e.g., tab completion shows no agents)
- Plugin installation errors like "Command failed with exit code 1"
- OpenCode starts successfully but features are missing

## Why This Happens

AI assistants like OpenCode use plugin systems (npm/bun packages) that interact with multiple cache directories:

1. **Config** (`~/.config/opencode/opencode.json`) - Plugin list and configuration
2. **Plugin cache** (`~/.cache/opencode/node_modules/`) - Installed plugin code
3. **Plugin data** (`~/.cache/oh-my-opencode/`) - Runtime data (connected providers, models)

**The ai-cage dilemma:**

- ai-cage remaps `$HOME` to `$STATE/home` (e.g., `~/.local/state/ai-cage/opencode/home/`)
- This creates **two separate cache directories**:
  - **Host cache**: `~/.cache/opencode/` (where plugins are normally installed)
  - **Caged cache**: `~/.local/state/ai-cage/opencode/cache/opencode/` (where caged OpenCode looks)
- OpenCode inside the cage can't find plugins installed in the host cache
- `XDG_CACHE_HOME` can point to either, but not both

## The Solution

**Keep plugins in the caged cache for maximum isolation**, and ensure both caches have identical plugin installations.

### Architecture Overview

```
Host (outside cage)                    Cage (inside ai-cage)
==================                     =================

~/.config/opencode/                    $XDG_CONFIG_HOME
  ├─ opencode.json          ──────→      (read-only access to host config)
  └─ oh-my-opencode.json    ──────→      (agent definitions)

~/.cache/oh-my-opencode/              (read-only access to host)
  ├─ connected-providers.json ─────→      (provider list)
  └─ provider-models.json     ─────→      (available models)

~/.cache/opencode/                    ❌ NO ACCESS
  └─ node_modules/                       (not used by cage)

                                       $XDG_CACHE_HOME = $STATE/cache
~/.local/state/ai-cage/opencode/
  └─ cache/opencode/            ──────→  (caged OpenCode uses THIS)
      ├─ package.json
      └─ node_modules/
          ├─ oh-my-opencode/
          └─ opencode-anthropic-auth/
```

### Step-by-Step Setup

#### 1. Configure flake.nix filesystem grants

```nix
opencode-caged = ai-cage.lib.cage { inherit pkgs; } {
  name = "opencode";
  profile = "aiAgent";
  argv = [ "opencode" ];

  filesystem = {
    # Read+execute access for binaries and shebang resolution
    rox = [ 
      "$HOME/.cache/npm" 
      "$HOME/.local/share/bun"
      "$HOME/.local/share/opencode"
      "/usr"  # Required for #!/usr/bin/env node
    ];

    # Read-only access to config and plugin data
    ro = [
      "$HOME/.cache/npm/lib"
      "$HOME/.config/opencode/"      # Plugin list, agent definitions
      "$HOME/.cache/oh-my-opencode"  # Provider data
    ];

    # Read+write+execute in caged directories
    rwx = [
      "$HOME/.npm/_npx"
      "$HOME/.bun"
      "$HOME/.local/state/ai-cage/opencode/home/.cache"
      "$HOME/.local/state/ai-cage/opencode/home/.bun"
      "$HOME/.local/state/ai-cage/opencode/cache"  # Caged plugin cache
      "$HOME/.local/state/ai-cage/opencode/tmp"
    ];
  };

  env = {
    pass = [
      "TERM"
      "LANG"
      "ANTHROPIC_API_KEY"
      "OPENAI_API_KEY"
      "GEMINI_API_KEY"
      # Add other API keys as needed
    ];

    set = {
      XDG_CONFIG_HOME = "$ORIG_HOME/.config";  # Read host config
      XDG_CACHE_HOME = "$STATE/cache";          # Use caged cache for plugins
      BUN_TMPDIR = "$ORIG_HOME/.local/state/ai-cage/opencode/tmp";
    };

    appendPath = [ 
      "$HOME/.cache/npm/bin"
      "$HOME/.local/share/bun/bin"
    ];
  };
};
```

#### 2. Sync plugin installations

**Important**: Plugins must be installed in BOTH locations with matching versions.

**Check host plugins:**
```bash
cat ~/.cache/opencode/package.json
```

Example output:
```json
{
  "dependencies": {
    "opencode-anthropic-auth": "0.0.13",
    "oh-my-opencode": "3.11.2"
  }
}
```

**Install matching plugins in caged cache:**
```bash
cd ~/.local/state/ai-cage/opencode/cache/opencode
bun add oh-my-opencode@3.11.2 opencode-anthropic-auth@0.0.13
```

**Verify installation:**
```bash
cat ~/.local/state/ai-cage/opencode/cache/opencode/package.json
```

Should match host versions:
```json
{
  "dependencies": {
    "oh-my-opencode": "^3.11.2",
    "opencode-anthropic-auth": "0.0.13"
  }
}
```

#### 3. Rebuild and test

```bash
exit              # Exit current nix shell
nix develop       # Re-enter with updated config
opencode-cage     # Launch caged OpenCode
```

**Test agents**: Press `Tab` in OpenCode - you should see agents like `sisyphus`, `oracle`, `librarian`, `explore`, etc.

## Maintenance: Updating Plugins

When you update plugins in your host OpenCode, sync them to the caged cache:

**1. Update host plugins** (outside cage):
```bash
cd ~/.cache/opencode
bun update oh-my-opencode
```

**2. Check new version:**
```bash
cat ~/.cache/opencode/package.json
```

**3. Update caged plugins** to match:
```bash
cd ~/.local/state/ai-cage/opencode/cache/opencode
bun add oh-my-opencode@<new-version>
```

**4. Restart caged OpenCode** (exit and re-enter nix shell if needed)

## Troubleshooting

### Agents don't appear when pressing Tab

**Symptom**: OpenCode starts, but no agents show up in tab completion.

**Diagnosis**:
```bash
# Check latest caged log
ls -t ~/.local/state/ai-cage/opencode/home/.local/share/opencode/log/*.log | head -1 | xargs tail -100 | grep -i "plugin\|error"
```

Look for errors like:
```
ERROR service=plugin pkg=opencode-anthropic-auth version=0.0.13 error=Command failed with exit code 1 failed to install plugin
```

**Solution**: Install the missing plugin in caged cache:
```bash
cd ~/.local/state/ai-cage/opencode/cache/opencode
bun add opencode-anthropic-auth@0.0.13
```

### Permission denied errors

**Symptom**: Landlock blocks file access.

**Diagnosis**:
```bash
# Check active wrapper grants
readlink -f $(which opencode-cage)
grep -E '(\.local/share/bun|\.local/share/opencode|\.cache/opencode|/usr)' $(readlink -f $(which opencode-cage))
```

**Solution**: Verify all required paths are granted in `flake.nix`, then rebuild:
```bash
exit
nix develop
```

### Plugin versions mismatch

**Symptom**: Plugins load but behave inconsistently.

**Solution**: Ensure exact version match between host and caged caches:
```bash
# Compare versions
diff <(cat ~/.cache/opencode/package.json) <(cat ~/.local/state/ai-cage/opencode/cache/opencode/package.json)
```

If different, sync versions:
```bash
cd ~/.local/state/ai-cage/opencode/cache/opencode
bun add <plugin>@<exact-version-from-host>
```

## Security Implications

This configuration maintains strong isolation:

**✅ Isolated (cage-only):**
- Plugin code execution (runs from caged cache)
- Plugin writes (only to caged directories)
- Network access (controlled by ai-cage profile)

**✅ Read-only host access (low risk):**
- OpenCode config (plugin list, agent definitions)
- oh-my-opencode provider data (connected providers, model list)
- Binaries and npm modules (read+execute only)

**❌ No access (fully protected):**
- Home directory
- Documents, downloads, etc.
- Write access to host cache
- Any paths not explicitly granted

**Trade-off**: Read-only access to oh-my-opencode cache (`~/.cache/oh-my-opencode/`) exposes:
- Connected provider list (GitHub Copilot, Google, etc.)
- Available model names
- Provider configuration metadata

This is acceptable because:
1. Data is read-only (can't be modified)
2. No sensitive credentials (API keys passed via environment variables)
3. Required for agent functionality
4. Alternative (copying to cage) adds maintenance overhead

## Applying This Pattern to Other AI Assistants

This pattern works for any AI assistant with plugin systems:

| Assistant | Config Path | Plugin Cache | Plugin Data |
|-----------|-------------|--------------|-------------|
| **OpenCode** | `~/.config/opencode/` | `~/.cache/opencode/node_modules/` | `~/.cache/oh-my-opencode/` |
| **Claude Desktop** | `~/Library/Application Support/Claude/` | `~/Library/Caches/Claude/` | Similar pattern |
| **Cursor** | `~/.cursor/` | `~/.cursor/extensions/` | Similar pattern |
| **Cline** | `~/.cline/` | Varies by platform | Similar pattern |

**General steps:**
1. Identify config, cache, and data directories
2. Grant read-only access to config and data
3. Use caged cache via `XDG_CACHE_HOME = "$STATE/cache"`
4. Install plugins in caged cache
5. Sync plugin versions between host and cage

## Example: Full Working Configuration

See this project's `flake.nix` for a complete working example of OpenCode with ai-cage.

Key files:
- `flake.nix` (lines 66-148) - Filesystem grants and environment variables
- `~/.config/opencode/opencode.json` - OpenCode configuration
- `~/.config/opencode/oh-my-opencode.json` - Agent definitions

## Contributing Back to ai-cage

This pattern would be valuable in the ai-cage documentation. Consider contributing:

1. **Example configuration** for popular AI assistants
2. **Troubleshooting guide** for plugin systems
3. **Best practices** for node/bun package isolation

Repository: https://github.com/antithesishq/ai-cage

## References

- [ai-cage Documentation](https://github.com/antithesishq/ai-cage)
- [OpenCode Documentation](https://opencode.ai)
- [oh-my-opencode Plugin](https://github.com/code-yeongyu/oh-my-opencode)
- [Landlock Linux Security Module](https://landlock.io/)

## License

This documentation is provided as-is for use with ai-cage and related projects.
