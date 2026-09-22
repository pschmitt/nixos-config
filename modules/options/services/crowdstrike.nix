{ lib, ... }:
{
  options.services.falcon-sensor.customerIdFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Path to the CrowdStrike Falcon customer ID file.";
  };
}
