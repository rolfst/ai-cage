# ai-cage Example Contributions

This directory contains improved ai-cage example configurations for OpenCode, ready for contribution to the upstream ai-cage repository.

## Files for Contribution

### 1. `opencode-global-improved.nix`
**Target location in ai-cage:** `examples/opencode-global-improved.nix`

**Purpose:** Shows the recommended pattern for caging globally-installed binaries.

**Key improvements:**
- ✅ Uses `argv = ["opencode"]` instead of `argv = ["$HOME/.cache/npm/bin/opencode"]`
- ✅ Demonstrates proper use of `env.appendPath` for PATH resolution
- ✅ Cleaner, more portable configuration
- ✅ Explains why absolute paths in argv don't work ($HOME expansion issue)

**Target audience:** Users who install opencode globally via npm/bun and want a simple, clean configuration.

---

### 2. `opencode-advanced-plugin-config.nix`
**Target location in ai-cage:** `examples/opencode-advanced-plugin-config.nix`

**Purpose:** Production-ready configuration for OpenCode with oh-my-opencode plugin support.

**Key improvements:**
- ✅ Comprehensive plugin isolation setup
- ✅ shellHook integration for plugin shim fixes
- ✅ BUN_TMPDIR configuration to avoid cross-mount rename errors
- ✅ Complete filesystem grants for oh-my-opencode
- ✅ devShell integration showing real-world usage
- ✅ Production-tested configuration from real projects

**Target audience:** Users who need oh-my-opencode plugins and want battle-tested configuration.

---

## Why These Examples Are Valuable

### Problem Solved: argv Path Expansion

**Current pattern in ai-cage examples:**
```nix
# ❌ Doesn't work - $HOME gets single-quoted and won't expand
argv = [ "$HOME/.cache/npm/bin/opencode" ];
```

**Improved pattern:**
```nix
# ✅ Works - binary name + appendPath handles resolution
argv = [ "opencode" ];
env.appendPath = [ "$HOME/.cache/npm/bin" ];
```

**Why this matters:**
- `lib.escapeShellArg` single-quotes argv elements, preventing $HOME expansion
- `env.appendPath` is processed differently and DOES expand $HOME
- Results in cleaner, more portable configuration
- Follows best practices for PATH management

---

### Problem Solved: oh-my-opencode Plugin Integration

The existing `opencode-npm.nix` example references plugin setup but doesn't show:
- Exact filesystem grants needed for plugins
- shellHook setup for plugin shims
- BUN_TMPDIR configuration for cross-mount rename errors
- Integration into development workflow

The advanced example fills this gap with production-tested configuration.

---

## Contribution Process

### Step 1: Review Current ai-cage Examples

Current examples in ai-cage (`examples/` directory):
- `opencode.nix` - Basic opencode from nixpkgs
- `opencode-npm.nix` - OpenCode from npm registry (references plugin setup)
- `opencode-global.nix` - Globally-installed opencode (basic)
- Other tools: `claude-code.nix`, `codex.nix`, `copilot-cli.nix`, `gemini-cli.nix`

### Step 2: Prepare Contribution

**Option A: Replace `opencode-global.nix`**
- Current `opencode-global.nix` uses absolute path in argv
- Replace with `opencode-global-improved.nix`
- Shows better practices

**Option B: Add as New Examples**
- Keep existing `opencode-global.nix` for compatibility
- Add `opencode-global-improved.nix` showing better pattern
- Add `opencode-advanced-plugin-config.nix` for oh-my-opencode users

**Recommendation:** Option B (additive, non-breaking)

### Step 3: Test Examples

Before contributing, verify each example works:

```bash
# Test basic improved example
cd examples-for-ai-cage
nix run .#opencode-global --impure

# Test advanced plugin example
nix develop .#opencode-advanced-plugin-config --impure
opencode-cage
```

### Step 4: Create Pull Request

1. Fork `rolfst/ai-cage`
2. Create branch: `git checkout -b feat/improved-opencode-examples`
3. Copy files:
   ```bash
   cp opencode-global-improved.nix <ai-cage-repo>/examples/
   cp opencode-advanced-plugin-config.nix <ai-cage-repo>/examples/
   ```
4. Update README.md if needed (add to "Supported tools" section)
5. Commit with clear message:
   ```
   feat: add improved opencode examples with better argv handling
   
   - Add opencode-global-improved.nix showing correct argv pattern
   - Add opencode-advanced-plugin-config.nix with oh-my-opencode setup
   - Fix $HOME expansion issue in argv by using env.appendPath
   - Include production-tested plugin configuration
   ```
6. Push and create PR

### Step 5: PR Description

```markdown
## Summary

Adds two improved OpenCode examples demonstrating better practices for argv handling and plugin integration.

## Changes

1. **opencode-global-improved.nix**
   - Shows correct pattern for globally-installed binaries
   - Uses `argv = ["opencode"]` instead of absolute path
   - Demonstrates `env.appendPath` for PATH resolution
   - Fixes $HOME expansion issue in argv

2. **opencode-advanced-plugin-config.nix**
   - Production-ready oh-my-opencode configuration
   - Includes shellHook for plugin shim fixes
   - Handles BUN_TMPDIR for cross-mount rename errors
   - Shows devShell integration pattern

## Why These Changes Are Needed

### argv Path Expansion Issue

Current `opencode-global.nix` uses:
```nix
argv = [ "$HOME/.cache/npm/bin/opencode" ];
```

This doesn't work because `lib.escapeShellArg` single-quotes the string, preventing $HOME expansion.

**Solution:**
```nix
argv = [ "opencode" ];
env.appendPath = [ "$HOME/.cache/npm/bin" ];
```

### Plugin Support Gap

Existing examples reference AI_CAGE_PLUGIN_SETUP.md but don't show complete working configuration. The advanced example provides production-tested setup for oh-my-opencode users.

## Testing

Both examples tested on:
- NixOS unstable
- OpenCode 1.2.x with oh-my-opencode 3.11.x
- Real development projects (typst-d2-mcp)

## Related Issues

None (proactive improvement)
```

---

## Maintenance Notes

### When ai-cage Updates

If ai-cage changes the cage API or adds new features:

1. Check if examples need updates
2. Test examples against new ai-cage version
3. Update if breaking changes

### When OpenCode Updates

If OpenCode changes plugin system or cache layout:

1. Update filesystem grants if needed
2. Update shellHook if plugin shim changes
3. Test with new OpenCode version

---

## Alternative: Update Existing Documentation

Instead of new examples, could update existing `docs/AI_CAGE_PLUGIN_SETUP.md`:

**Add section:**
```markdown
### Best Practice: argv Path Resolution

When caging globally-installed binaries, don't use absolute paths in argv:

❌ **Incorrect:**
```nix
argv = [ "$HOME/.cache/npm/bin/opencode" ];  # $HOME won't expand
```

✅ **Correct:**
```nix
argv = [ "opencode" ];
env.appendPath = [ "$HOME/.cache/npm/bin" ];
```

**Why:** `lib.escapeShellArg` single-quotes argv elements, preventing variable expansion. Use `env.appendPath` which does expand variables correctly.
```

---

## Questions for ai-cage Maintainer

Before contributing, consider asking:

1. **Preference for examples:** Replace existing or add new?
2. **Naming convention:** `opencode-global-improved.nix` or different name?
3. **Documentation location:** Should argv best practice go in README or docs/?
4. **oh-my-opencode focus:** Is dedicated advanced example wanted, or merge into existing?

---

## License

These examples are based on this project's MIT-licensed flake.nix and are contributed to ai-cage under the same MIT license.

---

## Credits

Configuration patterns developed for the typst-d2-mcp project:
https://github.com/dlouwers/typst-d2-mcp

Tested with real-world OpenCode usage and oh-my-opencode plugin integration.
