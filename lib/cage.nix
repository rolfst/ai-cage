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

  userCfg = {
    inherit name argv workspace packages filesystem nixStore network ssh env;
  };
  cfg = lib.recursiveUpdate (lib.recursiveUpdate defaults profileCfg) userCfg;

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

  roxFlagsScript = lib.concatMapStrings (p: ''
    landrunArgs+=("--rox" "${p}")
  '') filteredStorePaths;

  roFlagsScript = lib.concatMapStrings (p: ''
    landrunArgs+=("--ro" "${p}")
  '') fsRo;

  roxUserFlagsScript = lib.concatMapStrings (p: ''
    landrunArgs+=("--rox" "${p}")
  '') fsRox;

  rwFlagsScript = lib.concatMapStrings (p: ''
    landrunArgs+=("--rw" "${p}")
  '') fsRw;

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
