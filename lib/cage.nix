{ pkgs, lib }:

{
  name,
  profile ? null,
  argv,
  workspace ? { },
  packages ? [ ],
  filesystem ? { },
  nixStore ? { },
  network ? { },
  ssh ? { },
  env ? { },
  ...
}:
let
  profiles = import ./profiles.nix;

  profileCfg =
    if profile == null then
      { }
    else if builtins.isString profile then
      if builtins.hasAttr profile profiles then profiles.${profile} else throw "Unknown ai-cage profile: ${profile}"
    else if builtins.isAttrs profile then
      profile
    else
      throw "profile must be null, a profile name, or an attribute set";

  defaults = {
    workspace = { };
    packages = [ ];
    filesystem = { };
    nixStore = { };
    network = { };
    ssh = { };
    env = { };
  };

  # recursiveUpdate that concatenates (and deduplicates) lists instead of
  # replacing them.  This ensures that e.g. a profile's filesystem.ro
  # paths are preserved when the consumer also supplies filesystem.ro.
  mergeWith = base: overlay:
    lib.mapAttrs (key: baseVal:
      if builtins.hasAttr key overlay then
        let overlayVal = overlay.${key}; in
        if builtins.isAttrs baseVal && builtins.isAttrs overlayVal then
          mergeWith baseVal overlayVal
        else if builtins.isList baseVal && builtins.isList overlayVal then
          lib.unique (baseVal ++ overlayVal)
        else
          overlayVal
      else
        baseVal
    ) base // (lib.filterAttrs (k: _: !(builtins.hasAttr k base)) overlay);

  userCfg = {
    inherit name argv workspace packages filesystem nixStore network ssh env;
  };
  cfg = mergeWith (mergeWith defaults profileCfg) userCfg;

  landrun =
    if pkgs ? landrun then pkgs.landrun else pkgs.callPackage ../pkgs/landrun.nix { };

  workspacePath = cfg.workspace.path or "$PWD";
  connectTcp = cfg.network.connectTcp or [ ];
  fsRo = cfg.filesystem.ro or [ ];
  fsRox = cfg.filesystem.rox or [ ];
  fsRw = cfg.filesystem.rw or [ ];
  fsRwx = cfg.filesystem.rwx or [ ];
  passEnv = cfg.env.pass or [ ];
  setEnv = cfg.env.set or { };
  appendPath = cfg.env.appendPath or [ ];
  useStoreRead = cfg.nixStore.read or true;
  storeExecMode = cfg.nixStore.exec or "closure";
  forwardSshAgent = cfg.ssh.agentForward or false;

  closureInfo = pkgs.closureInfo { rootPaths = cfg.packages; };
  storePaths = lib.splitString "\n" (builtins.readFile "${closureInfo}/store-paths");
  filteredStorePaths = builtins.filter (p: p != "") storePaths;

  # All paths that have execute permission (closure + user rox + user rwx).
  # Used to detect when a less-permissive rule (ro, rw) would shadow an
  # execute-granting parent in Landlock's most-specific-path-wins model.
  allExecPaths = filteredStorePaths ++ fsRox ++ fsRwx;

  # Check whether `child` is equal to or a subdirectory of `parent`.
  # Both may contain unexpanded variables like $HOME, so this is a
  # conservative string-prefix check.  It works correctly for literal
  # paths and for paths that share the same variable prefix.
  isSubpathOf = parent: child:
    let p = if lib.hasSuffix "/" parent then parent else parent + "/";
    in child == parent || lib.hasPrefix p child;

  # True when `path` falls under any entry in `execPaths`.
  coveredByExec = path:
    builtins.any (ep: isSubpathOf ep path) allExecPaths;

  roxFlagsScript = lib.concatMapStrings (p: ''
    landrunArgs+=("--rox" "${p}")
  '') filteredStorePaths;

  # Promote ro paths to rox when they fall under an existing rox/rwx
  # parent.  Landlock applies the most-specific rule, so a child --ro
  # would silently strip the execute bit granted by a parent --rox.
  roFlagsScript = lib.concatMapStrings (p:
    if coveredByExec p then ''
      landrunArgs+=("--rox" "${p}")
    '' else ''
      landrunArgs+=("--ro" "${p}")
    ''
  ) fsRo;

  roxUserFlagsScript = lib.concatMapStrings (p: ''
    landrunArgs+=("--rox" "${p}")
  '') fsRox;

  # Same promotion for rw paths under an rwx parent.
  allWriteExecPaths = fsRwx;

  coveredByWriteExec = path:
    builtins.any (ep: isSubpathOf ep path) allWriteExecPaths;

  rwFlagsScript = lib.concatMapStrings (p:
    if coveredByWriteExec p then ''
      landrunArgs+=("--rwx" "${p}")
    '' else ''
      landrunArgs+=("--rw" "${p}")
    ''
  ) fsRw;

  rwxFlagsScript = lib.concatMapStrings (p: ''
    landrunArgs+=("--rwx" "${p}")
  '') fsRwx;

  netFlagsScript = lib.concatMapStrings (p: ''
    landrunArgs+=("--connect-tcp" "${toString p}")
  '') connectTcp;

  passEnvScript = lib.concatMapStrings (v: ''
    if [[ -n "''${${v}:-}" ]]; then
      landrunArgs+=("--env" "${v}")
    fi
  '') passEnv;

  setEnvScript = lib.concatStringsSep "\n" (
    lib.mapAttrsToList
      (k: v: ''
        landrunArgs+=("--env" "${k}=${toString v}")
      '')
      setEnv
  );

  argvScript = lib.concatStringsSep " " (map lib.escapeShellArg cfg.argv);
  computedPath = lib.makeBinPath cfg.packages;
  extraPath = lib.concatStringsSep ":" appendPath;
  fullPath = if appendPath == [ ] then computedPath else "${computedPath}:${extraPath}";
in
assert lib.assertMsg (cfg.argv != [ ]) "ai-cage: argv must not be empty";
assert lib.assertMsg (storeExecMode == "closure") "ai-cage: nixStore.exec currently supports only \"closure\"";
pkgs.writeShellScriptBin "${cfg.name}-cage" ''
  set -euo pipefail

  ORIG_HOME="''${HOME:?HOME must be set}"
  STATE="$ORIG_HOME/.local/state/ai-cage/${cfg.name}"
  mkdir -p "$STATE"/{home,config,state,cache}

  WORKSPACE="${workspacePath}"
  cd "$WORKSPACE"

  declare -a landrunArgs
  landrunArgs+=("--log-level" "error")

  ${lib.optionalString useStoreRead ''
    landrunArgs+=("--rox" "/nix/store")
  ''}

  ${roxFlagsScript}
  ${roFlagsScript}
  ${roxUserFlagsScript}
  ${rwFlagsScript}
  ${rwxFlagsScript}
  ${netFlagsScript}

  # Essential system paths that almost every program needs.
  # /dev/stdin, /dev/stdout, /dev/stderr are inherited file descriptors and
  # do not need Landlock rules. /dev/fd is a symlink to /proc/self/fd.

  # /lib64 is needed on NixOS for nix-ld compatibility. Non-Nix dynamically-
  # linked binaries (e.g. npm-installed tools) use /lib64/ld-linux-x86-64.so.2
  # which is a symlink to the nix-ld shim. Without this, such binaries crash
  # with SIGABRT because the dynamic linker can't be resolved under Landlock.
  if [[ -d /lib64 ]]; then
    landrunArgs+=("--rox" "/lib64")
  fi

  landrunArgs+=("--rw" "/dev/null")
  landrunArgs+=("--rw" "/dev/zero")
  landrunArgs+=("--ro" "/dev/urandom")
  landrunArgs+=("--ro" "/dev/random")
  if [[ -c /dev/tty ]]; then
    landrunArgs+=("--rw" "/dev/tty")
  fi
  landrunArgs+=("--rw" "/tmp")

  landrunArgs+=("--rw" "$STATE")
  landrunArgs+=("--rw" "$WORKSPACE")

  landrunArgs+=("--env" "HOME=$STATE/home")
  landrunArgs+=("--env" "XDG_CONFIG_HOME=$STATE/config")
  landrunArgs+=("--env" "XDG_STATE_HOME=$STATE/state")
  landrunArgs+=("--env" "XDG_CACHE_HOME=$STATE/cache")
  landrunArgs+=("--env" "PATH=${fullPath}")

  ${passEnvScript}
  ${setEnvScript}

  if [[ "${if forwardSshAgent then "1" else "0"}" == "1" ]] && [[ -n "''${SSH_AUTH_SOCK:-}" ]]; then
    if [[ -S "$SSH_AUTH_SOCK" ]]; then
      landrunArgs+=("--ro" "$(dirname "$SSH_AUTH_SOCK")")
      landrunArgs+=("--rw" "$SSH_AUTH_SOCK")
      landrunArgs+=("--env" "SSH_AUTH_SOCK")
    fi
  fi

  argv=( ${argvScript} )
  exec ${landrun}/bin/landrun "''${landrunArgs[@]}" -- "''${argv[@]}"
''
