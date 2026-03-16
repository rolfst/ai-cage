# Tool registry: maps tool names to their known config directories.
#
# Each entry declares the host-side config paths (relative to $HOME)
# that the tool reads. When a user specifies  tools = [ "opencode" ];
# in their cage config, cage.nix looks up the tool here and merges its
# configDirs into the sandbox automatically.
#
# To add a new tool:  add an entry with its configDirs list.
# To extend an existing tool:  append paths to its configDirs.

{
  opencode = {
    configDirs = [ ".config/opencode" ];
  };

  claude-code = {
    configDirs = [ ".config/claude" ".claude" ];
  };

  copilot-cli = {
    configDirs = [ ".config/.copilot" ".config/gh" ];
  };

  codex = {
    configDirs = [ ".codex" ];
  };

  gemini-cli = {
    configDirs = [ ".gemini" ];
  };
}
