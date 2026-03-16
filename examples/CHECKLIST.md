# Contribution Checklist: ai-cage Examples

Use this checklist to prepare and submit improved examples to ai-cage.

## Pre-Contribution Review

### ✅ Example Quality

- [x] Examples are complete, standalone flakes
- [x] Follow ai-cage naming conventions (`<tool>-<variant>.nix`)
- [x] Include header comments with usage instructions
- [x] Inline documentation explains non-obvious choices
- [x] Reference existing ai-cage docs where appropriate
- [ ] Examples tested and working (see Testing section below)

### ✅ File Structure

- [x] `opencode-global-improved.nix` - Basic improved argv pattern
- [x] `opencode-advanced-plugin-config.nix` - Advanced oh-my-opencode setup
- [x] `README.md` - Contribution guide
- [x] `IMPROVEMENTS.md` - Quick reference comparing patterns
- [x] `CHECKLIST.md` - This file

---

## Testing Checklist

### Test Environment Setup

- [ ] Clean test environment (fresh directory)
- [ ] opencode installed globally: `npm i -g opencode-ai`
- [ ] Host plugins installed: `cd ~/.cache/opencode && bun add oh-my-opencode opencode-anthropic-auth`
- [ ] Caged plugins synced (for advanced example):
  ```bash
  mkdir -p ~/.local/state/ai-cage/opencode/cache/opencode
  cd ~/.local/state/ai-cage/opencode/cache/opencode
  bun add oh-my-opencode@<version> opencode-anthropic-auth@<version>
  ```

### Test: opencode-global-improved.nix

```bash
cd examples-for-ai-cage
nix run .#opencode-global --impure
```

**Expected results:**
- [ ] opencode launches successfully
- [ ] No "command not found" errors
- [ ] Can access workspace directory
- [ ] Config loaded from ~/.config/opencode/
- [ ] API keys work (test with provider auth)
- [ ] Git commands work inside opencode

**Test commands inside opencode:**
```bash
# In opencode session:
git status        # Should work
ls -la           # Should see current directory
pwd              # Should show workspace path
echo $HOME       # Should show caged home
```

### Test: opencode-advanced-plugin-config.nix

```bash
cd examples-for-ai-cage
nix develop .#opencode-advanced-plugin-config --impure
```

**Expected results:**
- [ ] DevShell enters successfully
- [ ] shellHook runs without errors
- [ ] BUN_TMPDIR created
- [ ] oh-my-opencode shim created (if plugin installed)
- [ ] `opencode-cage` command available

```bash
# In devShell:
opencode-cage
```

**Inside caged opencode:**
- [ ] opencode launches successfully
- [ ] Tab completion shows agents (sisyphus, oracle, librarian, explore)
- [ ] Can select provider (GitHub Copilot, Anthropic, etc.)
- [ ] Plugins load without errors
- [ ] Agent commands work

**Check logs for errors:**
```bash
ls -t ~/.local/state/ai-cage/opencode/home/.local/share/opencode/log/*.log | head -1 | xargs tail -100 | grep -i "error\|failed"
```

**Expected:** No plugin-related errors

---

## Code Review Checklist

### Configuration Correctness

- [x] `argv` uses binary name only (no $HOME)
- [x] `env.appendPath` includes binary directories
- [x] `filesystem.rox` grants execute access to binary locations
- [x] `env.pass` includes necessary API keys
- [x] `tools = ["opencode"]` declared
- [x] Comments explain why each configuration choice was made

### Advanced Example Specifics

- [x] All oh-my-opencode filesystem grants present
- [x] XDG_CONFIG_HOME points to $ORIG_HOME/.config
- [x] XDG_CACHE_HOME points to $STATE/cache
- [x] BUN_TMPDIR configured correctly
- [x] shellHook creates BUN_TMPDIR
- [x] shellHook creates oh-my-opencode shim
- [x] shellHook handles missing plugin gracefully

### Documentation Quality

- [x] Header comment describes what example demonstrates
- [x] Prerequisites clearly listed
- [x] Usage instructions included
- [x] References to AI_CAGE_PLUGIN_SETUP.md where relevant
- [x] Inline comments explain complex sections
- [x] Why improvements matter is documented

---

## Contribution Preparation

### Repository Preparation

- [ ] Fork `rolfst/ai-cage` on GitHub
- [ ] Clone fork locally
- [ ] Create feature branch: `git checkout -b feat/improved-opencode-examples`
- [ ] Verify ai-cage main branch is up to date

### File Preparation

- [ ] Copy `opencode-global-improved.nix` to `<ai-cage>/examples/`
- [ ] Copy `opencode-advanced-plugin-config.nix` to `<ai-cage>/examples/`
- [ ] Verify file paths are correct
- [ ] Verify files are complete (no truncation)

### Documentation Updates (Optional)

If updating README.md:

- [ ] Add entries to "Supported tools" table
- [ ] Add note about argv best practices
- [ ] Reference new examples in appropriate sections

If adding to AI_CAGE_PLUGIN_SETUP.md:

- [ ] Add "Best Practice: argv Path Resolution" section
- [ ] Link to new examples

### Git Workflow

```bash
cd <ai-cage-clone>
git checkout -b feat/improved-opencode-examples

# Copy files
cp ../typst-d2-mcp/examples-for-ai-cage/opencode-global-improved.nix examples/
cp ../typst-d2-mcp/examples-for-ai-cage/opencode-advanced-plugin-config.nix examples/

# Stage changes
git add examples/opencode-global-improved.nix
git add examples/opencode-advanced-plugin-config.nix

# Optional: Update docs
git add README.md  # if updated
git add docs/AI_CAGE_PLUGIN_SETUP.md  # if updated

# Commit
git commit -m "feat: add improved opencode examples with better argv handling

- Add opencode-global-improved.nix showing correct argv pattern
- Add opencode-advanced-plugin-config.nix with oh-my-opencode setup
- Fix \$HOME expansion issue in argv by using env.appendPath
- Include production-tested plugin configuration

Addresses limitation in current opencode-global.nix where absolute
paths in argv don't work due to lib.escapeShellArg single-quoting.

The advanced example provides complete oh-my-opencode setup based on
production usage in typst-d2-mcp project."

# Push to fork
git push -u origin feat/improved-opencode-examples
```

Checklist:
- [ ] Commit message follows conventional commits format
- [ ] Commit message explains what and why
- [ ] Branch pushed to fork

---

## Pull Request Checklist

### PR Creation

- [ ] Navigate to `rolfst/ai-cage` on GitHub
- [ ] Click "Pull requests" → "New pull request"
- [ ] Select: base: `main` ← compare: `<your-fork>:feat/improved-opencode-examples`
- [ ] Click "Create pull request"

### PR Title

```
feat: improved opencode examples with argv best practices
```

- [ ] Title is clear and concise
- [ ] Title starts with conventional commit type (`feat:`, `docs:`, etc.)

### PR Description

Use template from `README.md` in this directory, including:

- [ ] Summary of changes
- [ ] List of files added/modified
- [ ] Explanation of why changes are needed
- [ ] Testing information
- [ ] Related issues (if any)

### PR Checklist (in description)

Include this in PR description:

```markdown
## Checklist

- [ ] Examples tested and working
- [ ] Follow existing example format
- [ ] Documentation is clear
- [ ] No breaking changes
- [ ] Ready for review
```

### After PR Creation

- [ ] Verify files are correct in PR diff
- [ ] Verify formatting is preserved
- [ ] Respond to review comments promptly
- [ ] Make requested changes if needed

---

## Post-Contribution

### If PR Accepted

- [ ] Star ai-cage repository (if you haven't)
- [ ] Update typst-d2-mcp to reference upstream examples (optional)
- [ ] Consider contributing to tool registry (`lib/tools.nix`) if new tools added

### If PR Needs Changes

- [ ] Address review comments
- [ ] Push updates to same branch
- [ ] Comment on PR explaining changes made

### If PR Rejected

- [ ] Ask for feedback on why
- [ ] Keep examples in typst-d2-mcp as local reference
- [ ] Document any ai-cage-specific patterns that differ

---

## Quick Testing Script

Save as `test-examples.sh`:

```bash
#!/usr/bin/env bash
set -e

echo "Testing opencode-global-improved.nix..."
cd examples-for-ai-cage
nix run .#opencode-global --impure --command opencode --version
echo "✓ Basic example works"

echo ""
echo "Testing opencode-advanced-plugin-config.nix..."
nix develop .#opencode-advanced-plugin-config --impure --command bash -c '
  if [ -f "$HOME/.local/state/ai-cage/opencode/cache/opencode/node_modules/oh-my-opencode/index.js" ]; then
    echo "✓ Plugin shim created"
  else
    echo "⚠ Plugin shim not found (may need plugin install)"
  fi
  
  if [ -d "$HOME/.local/state/ai-cage/opencode/tmp" ]; then
    echo "✓ BUN_TMPDIR created"
  else
    echo "✗ BUN_TMPDIR missing"
    exit 1
  fi
'

echo ""
echo "All tests passed!"
```

- [ ] Test script created
- [ ] Test script executed successfully

---

## Notes

### Questions to Ask Maintainer (Optional)

Before or during PR, consider asking:

1. Preference for example naming?
2. Should existing `opencode-global.nix` be replaced or kept?
3. Where should argv best practice be documented?
4. Interest in more advanced examples (e.g., multi-tool cages)?

### Related Work

If you discover similar issues in other examples:

- [ ] Document in PR comments
- [ ] Offer to fix in separate PR
- [ ] Update this checklist for future contributions

---

## Status

**Current Status:** ⬜ Not Started | ◻️ In Progress | ✅ Complete

- [ ] Examples created and tested
- [ ] Fork and branch prepared
- [ ] Files copied to ai-cage fork
- [ ] Commit created with good message
- [ ] Pushed to fork
- [ ] PR created
- [ ] PR reviewed and merged

**Last Updated:** 2026-03-16
**Prepared By:** OpenCode (AI)
**Source Project:** typst-d2-mcp
