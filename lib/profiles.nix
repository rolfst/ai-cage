{
  # No network at all — for offline tools
  offline = {
    network = { };
    nixStore = { read = true; exec = "closure"; };
  };

  # AI coding agent — HTTPS + SSH + private HOME
  aiAgent = {
    network = { connectTcp = [ 443 22 ]; };
    nixStore = { read = true; exec = "closure"; };
    ssh = { agentForward = true; };
    filesystem = {
      ro = [ "/etc/resolv.conf" "/etc/hosts" "/etc/nsswitch.conf" "/etc/passwd" "/etc/group" ];
    };
    env = { pass = [ "TERM" "LANG" ]; };
  };

  # Development with broader network access
  devNet = {
    network = { connectTcp = [ 443 80 22 8080 3000 5000 ]; };
    nixStore = { read = true; exec = "closure"; };
    ssh = { agentForward = true; };
    filesystem = {
      ro = [ "/etc/resolv.conf" "/etc/hosts" "/etc/nsswitch.conf" "/etc/passwd" "/etc/group" ];
    };
    env = { pass = [ "TERM" "LANG" ]; };
  };
}
