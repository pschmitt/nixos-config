# Public repositories in the x86_64 pilot. The service adds the shared GitHub
# App webhook to each project.
[
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
