# Public repositories in the x86_64 pilot. The service adds the shared GitHub
# App webhook to each project.
[
  {
    name = "codex-ha-bridge";
    repository_url = "https://github.com/pschmitt/codex-ha-bridge";
    jobsets = [
      {
        name = "main";
        nix_expression = "packages.x86_64-linux";
        branch = "main";
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ];
  }
  {
    name = "ldifj";
    repository_url = "https://github.com/pschmitt/ldifj";
    jobsets = [
      {
        name = "main";
        nix_expression = "packages.x86_64-linux";
        branch = "main";
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ];
  }
  {
    name = "luks-mount-sh";
    repository_url = "https://github.com/pschmitt/luks-mount.sh";
    jobsets = [
      {
        name = "main";
        nix_expression = "packages.x86_64-linux";
        branch = "main";
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ];
  }
  {
    name = "pschmitt-dev";
    repository_url = "https://github.com/pschmitt/pschmitt.dev";
    jobsets = [
      {
        name = "main";
        nix_expression = "packages.x86_64-linux";
        branch = "main";
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ];
  }
  {
    name = "ruamel-fmt";
    repository_url = "https://github.com/pschmitt/ruamel-fmt";
    jobsets = [
      {
        name = "main";
        nix_expression = "packages.x86_64-linux";
        branch = "main";
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ];
  }
  {
    name = "shelly-ble-rpc";
    repository_url = "https://github.com/pschmitt/shelly-ble-rpc";
    jobsets = [
      {
        name = "main";
        nix_expression = "packages.x86_64-linux";
        branch = "main";
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ];
  }
  {
    name = "tmux-slay";
    repository_url = "https://github.com/pschmitt/tmux-slay";
    jobsets = [
      {
        name = "main";
        nix_expression = "packages.x86_64-linux";
        branch = "main";
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ];
  }
  {
    name = "tsvtool";
    repository_url = "https://github.com/pschmitt/tsvtool";
    jobsets = [
      {
        name = "main";
        nix_expression = "packages.x86_64-linux";
        branch = "main";
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ];
  }
  {
    name = "vodafone-station-cli";
    repository_url = "https://github.com/pschmitt/vodafone-station-cli";
    jobsets = [
      {
        name = "main";
        nix_expression = "packages.x86_64-linux";
        branch = "main";
        systems = [ "x86_64-linux" ];
        only_build_latest = true;
      }
    ];
  }
]
