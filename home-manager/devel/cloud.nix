{ pkgs, ... }:
{
  home.packages = with pkgs; [
    oci-cli
    rclone
    s3cmd
  ];
}
