{ ... }:
{
  # 01.12.2024: nixos-rebuild complains about dotnet-runtime 6 being EOL
  nixpkgs.config.permittedInsecurePackages = [
    "dotnet-runtime-6.0.36"
    "dotnet-runtime-6.0.428"
    "dotnet-sdk-wrapped-6.0.428"
    "dotnet-sdk-6.0.428"
  ];
}
