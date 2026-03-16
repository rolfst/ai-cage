# Handoff: Fix Landlock REFER in ai-cage

## Problem

Jujutsu (jj) cannot manage source code inside an ai-cage sandbox. Every jj operation that writes git objects fails with:

```
Internal error: Failed to snapshot the working copy
Caused by:
1: Could not write object of type file
2: Could not turn temporary file into persisted file at '.git/objects/c2/6283a574...'
3: failed to persist temporary file: Invalid cross-device link (os error 18)
4: Invalid cross-device link (os error 18)
```

Git itself works fine. The issue is specific to jj's gitoxide backend.

## Root Cause

**Missing `LANDLOCK_ACCESS_FS_REFER` right in landrun rules.**

### How Landlock REFER works

Landlock v2 (kernel 5.19+) introduced `LANDLOCK_ACCESS_FS_REFER`, which controls the ability to `rename()` or `link()` files **between directories covered by different Landlock rules**. Without this right, cross-rule `rename()` returns `EXDEV` (cross-device link), even when both paths are on the same physical filesystem and device.

### What ai-cage does

The generated cage wrapper (`opencode-cage`) passes each path as a separate `--rw` flag to landrun:

```bash
landrunArgs+=("--rw" "/tmp")
landrunArgs+=("--rw" "$STATE")
landrunArgs+=("--rw" "$WORKSPACE")
```

Each `--rw` flag creates a **separate Landlock ruleset entry**. This means `rename()` between any two of these paths (or even between subdirectories within `$WORKSPACE`) is denied without `REFER`.

### What jj/gitoxide does

Gitoxide (jj's git backend) creates temporary files and renames them into `.git/objects/`. The rename crosses a Landlock rule boundary → `EXDEV`.

C git works because it creates temp files as siblings **inside** `.git/objects/` (same directory), then renames within the same directory.

### Evidence (tested inside the cage)

| Rename path | Result |
|---|---|
| `.git/objects/c2/src` → `.git/objects/c2/dst` | **OK** (same leaf dir) |
| `.git/objects/00/src` → `.git/objects/c2/dst` | **EXDEV** (sibling dirs!) |
| `.git/src` → `.git/objects/c2/dst` | **EXDEV** (parent to child) |
| `.git/objects/c2/src` → `.git/dst` | **EXDEV** (child to parent) |
| workspace root → `.git/objects/c2/dst` | **EXDEV** |
| `/tmp/src` → `.git/objects/c2/dst` | **EXDEV** |
| workspace root → workspace root (diff name) | **OK** (same leaf dir) |

Key observation: even `.git/objects/00/` → `.git/objects/c2/` (sibling directories under the **same** `--rw $WORKSPACE` rule) fails. This means landrun is not granting `LANDLOCK_ACCESS_FS_REFER` on its rulesets, so any rename between different directories fails with `EXDEV`, regardless of whether the same high-level path rule covers both.

The Landlock kernel docs confirm: without `REFER`, renames between directories always fail with `EXDEV`.

## Environment

- Kernel: 6.12.75 (Landlock ABI v5 — supports REFER)
- jj: 0.39.0
- landrun: 0.1.14 (reports 0.1.13 in --version)
- Filesystem: btrfs (device 34 for workspace, device 53 for /tmp)
- ai-cage: from `github:rolfst/ai-cage`

## The Generated Cage Wrapper

The wrapper lives at a nix store path like `/nix/store/...-opencode-cage/bin/opencode-cage`. Key lines:

```bash
landrunArgs+=("--rw" "/tmp")        # line 198
landrunArgs+=("--rw" "$STATE")      # line 200
landrunArgs+=("--rw" "$WORKSPACE")  # line 201

exec /nix/store/...-landrun-0.1.14/bin/landrun "${landrunArgs[@]}" -- "${argv[@]}"
```

landrun's available flags (no REFER support currently):
```
--ro    Allow read-only access to this path
--rox   Allow read-only access with execution to this path
--rw    Allow read-write access to this path
--rwx   Allow read-write access with execution to this path
```

## Fix Required

### In landrun (upstream or fork)

landrun currently does not expose `LANDLOCK_ACCESS_FS_REFER` in its ruleset. When landrun builds its `landlock_path_beneath_attr` rules, it needs to include `LANDLOCK_ACCESS_FS_REFER` for paths that have write access (`--rw`, `--rwx`).

Check landrun's Go source for where it builds the Landlock ruleset. Look for:
- `landlock.PathAccess()` or similar calls
- The set of `AccessFSRead`, `AccessFSWrite`, `AccessFSExecute` rights being granted
- `AccessFSRefer` must be added to writable paths

In Go's `github.com/landlock-lsm/go-landlock` library, the right is:
```go
landlock.AccessFSRefer
```

### In ai-cage (if landrun doesn't support it)

If landrun can't be patched to add REFER, ai-cage could:

1. **Option A**: Fork landrun, add REFER support, use the fork
2. **Option B**: Add a `--refer` flag to landrun and pass it from ai-cage for writable paths
3. **Option C**: As a workaround, ai-cage could set `TMPDIR` to a path within the workspace, but this only fixes tools that respect `TMPDIR` — gitoxide does not

### Recommended approach

The cleanest fix is in **landrun**: grant `LANDLOCK_ACCESS_FS_REFER` by default on all paths with write access (`--rw`, `--rwx`). This matches what users expect — if you can write to two directories, you should be able to rename between them. The `REFER` right is specifically designed to allow this.

If landrun wants to be conservative, add a `--allow-refer` flag (or `--refer` per-path, e.g., `--rw-refer /path`) and have ai-cage pass it for the workspace.

## How to Verify the Fix

After patching, run this inside the cage:

```bash
# This should succeed (currently fails with EXDEV)
node -e "
const fs = require('fs');
fs.writeFileSync('/tmp/refer-test', 'test');
try {
  fs.renameSync('/tmp/refer-test', process.cwd() + '/.git/objects/refer-test');
  console.log('REFER works!');
  fs.unlinkSync(process.cwd() + '/.git/objects/refer-test');
} catch(e) {
  console.log('REFER still broken:', e.code);
  fs.unlinkSync('/tmp/refer-test');
}
"

# And jj should work
jj status
jj log --limit 5
```

## Files to Examine in ai-cage

1. **The `cage` function** — where `--rw`/`--rwx` flags are assembled for landrun
2. **The `landrun` invocation** — see if there's already a mechanism for Landlock access rights
3. **Profile definitions** (like `aiAgent`) — may need a `refer` option

## Files to Examine in landrun

1. **Landlock ruleset construction** — where `landlock_path_beneath_attr` structs are built
2. **Access rights bitmask** — where `LANDLOCK_ACCESS_FS_*` constants are OR'd together
3. **The Go landlock library usage** — look for `landlock.PathAccess()` calls

## References

- [Landlock REFER documentation](https://docs.kernel.org/userspace-api/landlock.html#file-reparenting)
- [go-landlock AccessFSRefer](https://pkg.go.dev/github.com/landlock-lsm/go-landlock/landlock#pkg-constants)
- [landrun source](https://github.com/nicholasgasior/landrun)
- Kernel ABI version 2+ required for REFER (this system runs ABI v5)
