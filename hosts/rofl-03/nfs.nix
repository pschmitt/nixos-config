{ ... }:

# Specify a reusable server address and a list of directories
let
  serverAddress = "rofl-02.netbird.cloud:/export";
  # mountDirs = [ "backups" "books" "documents" "mnt" "srv" "tmp" "videos" ];
  mountDirs = [ "videos" ];
in
{
  # Function to generate file system definitions
  fileSystems = builtins.listToAttrs (map
    (dir: {
      name = "/mnt/data/${dir}";
      value.device = "${serverAddress}/${dir}";
      value.fsType = "nfs";
      # value.options = [ "rsize=8192" "wsize=8192" "hard" "intr" ];
    })
    mountDirs);
}

