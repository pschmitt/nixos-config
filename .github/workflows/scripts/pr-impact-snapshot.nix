publicSource: configuration:
let
  cfg = configuration.config;
  normalize = scope: package: {
    inherit scope;
    name = package.pname or package.name;
    version = package.version or "";
  };
  users = cfg.home-manager.users or { };
  homePackages = builtins.concatLists (
    builtins.map (user: builtins.map (normalize "home") (users.${user}.home.packages or [ ])) (
      builtins.attrNames users
    )
  );
  androidHome = cfg.home-manager.config.home.packages or [ ];
  kernel = cfg.boot.kernelPackages.kernel or null;
  containers = cfg.virtualisation.oci-containers.containers or { };
  definitions =
    configuration.options.virtualisation.oci-containers.containers.definitionsWithLocations or [ ];
  publicPrefix = "${publicSource}/";
  isPublic =
    definition:
    builtins.substring 0 (builtins.stringLength publicPrefix) definition.file == publicPrefix;
  publicNames = builtins.concatLists (
    builtins.map (
      definition:
      if isPublic definition then
        builtins.filter (name: definition.value.${name} ? image) (builtins.attrNames definition.value)
      else
        [ ]
    ) definitions
  );
  otherNames = builtins.concatLists (
    builtins.map (
      definition:
      if isPublic definition then
        [ ]
      else
        builtins.filter (name: definition.value.${name} ? image) (builtins.attrNames definition.value)
    ) definitions
  );
  # Report public image definitions even when private modules add environment
  # files or other settings. Exclude images defined or overridden privately.
  reportedNames = builtins.filter (
    name: builtins.hasAttr name containers && !(builtins.elem name otherNames)
  ) publicNames;
in
{
  packages =
    builtins.map (normalize "system") (
      cfg.environment.systemPackages or (cfg.environment.packages or [ ])
    )
    ++ homePackages
    ++ builtins.map (normalize "home") androidHome;
  kernel =
    if kernel == null then
      null
    else
      {
        inherit (kernel) version;
        modDirVersion = kernel.modDirVersion or kernel.version;
      };
  containers = builtins.listToAttrs (
    builtins.map (name: {
      inherit name;
      value = containers.${name}.image;
    }) reportedNames
  );
}
