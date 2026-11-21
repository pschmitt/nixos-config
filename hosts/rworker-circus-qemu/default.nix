# The Circus ARM overflow agent runs on x86_64 and emulates aarch64-linux
# through qemu-user/binfmt. The native ARM GHA pool remains preferred and
# handles any job requiring big-parallel.
{ lib, ... }:
{
  imports = [ ../rworker-circus ];

  boot.binfmt.emulatedSystems = lib.mkForce [ "aarch64-linux" ];
  nix.settings.system-features = lib.mkForce [
    "nixos-test"
    "benchmark"
    "kvm"
  ];

  rworker.image = {
    label = lib.mkForce "Circus ARM overflow agent";
    pool = lib.mkForce "circus-qemu";
  };

  services.circus-agent.settings.agent = {
    name = lib.mkForce "circus-qemu-overflow";
    systems = lib.mkForce [ "aarch64-linux" ];
    # The native pool currently advertises only big-parallel. This agent can
    # take feature-free work; it must never accept big-parallel jobs.
    supported_features = lib.mkForce [ ];
    max_jobs = lib.mkForce 1;
    cores = lib.mkForce 8;
    speed_factor = lib.mkForce 0.25;
  };
}
