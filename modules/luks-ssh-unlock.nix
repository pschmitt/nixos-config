{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.luks-ssh-unlocker;
in
{
  options.services.luks-ssh-unlocker = {
    enable = mkEnableOption "LUKS SSH Unlocker Service";
    instances = mkOption {
      type = types.attrsOf (types.submodule ({
        options = {
          hostname = mkOption {
            type = types.str;
            description = "Hostname of the target machine.";
          };
          username = mkOption {
            type = types.str;
            description = "SSH username for the target machine.";
            default = "root";
          };
          key = mkOption {
            type = types.path;
            description = "SSH key path for authentication.";
            default = "/etc/ssh/ssh_host_ed25519_key";
          };
          port = mkOption {
            type = types.int;
            default = 22;
            description = "SSH port for the target machine.";
          };
          forceIpv4 = mkOption {
            type = types.bool;
            default = false;
            description = "Force IPv4 for SSH connection.";
          };
          forceIpv6 = mkOption {
            type = types.bool;
            default = false;
            description = "Force IPv6 for SSH connection.";
          };
          type = mkOption {
            type = types.str;
            description = "Type of LUKS operation.";
            default = "dracut";
          };
          passphrase = mkOption {
            type = types.str;
            default = "";
            description = "Passphrase for LUKS.";
          };
          passphraseFile = mkOption {
            type = types.path;
            description = "Path to the file containing the passphrase for LUKS.";
            default = "";
          };
          debug = mkOption {
            type = types.bool;
            default = false;
            description = "Enable debug mode.";
          };
          jumphost = mkOption {
            type = types.nullOr (types.submodule {
              options = {
                hostname = mkOption {
                  type = types.str;
                  description = "Jumphost hostname.";
                };
                username = mkOption {
                  type = types.str;
                  description = "Jumphost SSH username.";
                };
                key = mkOption {
                  type = types.path;
                  description = "Jumphost SSH key path.";
                };
                port = mkOption {
                  type = types.int;
                  default = 22;
                  description = "Jumphost SSH port.";
                };
              };
            });
            default = null;
            description = "Optional jumphost configuration.";
          };
          sleep_interval = mkOption {
            type = types.int;
            default = 15;
            description = "Time to wait between attempts.";
          };
          healthcheck = mkOption {
            type = types.submodule {
              options = {
                enable = mkEnableOption "Healthcheck on/off.";
                port = mkOption {
                  type = types.int;
                  default = 80;
                  description = "Health check port.";
                };
                remote_hostname = mkOption {
                  type = types.str;
                  description = "Remote hostname to run the command on.";
                  default = "";
                };
                remote_username = mkOption {
                  type = types.str;
                  description = "Remote username for the remote healthcheck command.";
                  default = "";
                };
                remote_cmd = mkOption {
                  type = types.str;
                  description = "Remote command to verify the status.";
                  default = "";
                };
              };
            };
            description = "Health check configuration.";
          };
        };
      }));
      description = "Configuration for multiple LUKS SSH Unlocker instances.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.luks-ssh-unlock ];

    # Define environment files
    environment.etc = mapAttrs'
      (name: instance: nameValuePair "luks-ssh-unlock/${name}.env" {
        text = with instance; ''
          DEBUG=${optionalString (debug == true) "1"}
          SSH_HOSTNAME=${hostname}
          SSH_USER=${username}
          SSH_KEY=${key}
          SSH_PORT=${toString port}
          SSH_FORCE_IPV4=${optionalString (forceIpv4 == true) "1"}
          SSH_FORCE_IPV6=${optionalString (forceIpv6 == true) "1"}
          SSH_JUMPHOST=${optionalString (jumphost != null) jumphost.hostname}
          SSH_JUMPHOST_USERNAME=${optionalString (jumphost != null) jumphost.username}
          SSH_JUMPHOST_PORT=${optionalString (jumphost != null) (toString jumphost.port)}
          SSH_JUMPHOST_KEY=${optionalString (jumphost != null) jumphost.key}
          LUKS_PASSWORD=${passphrase}
          LUKS_PASSWORD_FILE=${passphraseFile}
          LUKS_TYPE=${type}
          SLEEP_INTERVAL=${toString sleep_interval}
          ${optionalString (instance.healthcheck.enable) ''
            HEALTHCHECK_PORT=${toString healthcheck.port}
            HEALTHCHECK_REMOTE_HOSTNAME="${optionalString (healthcheck.remote_hostname != "") healthcheck.remote_hostname}"
            HEALTHCHECK_REMOTE_USERNAME="${optionalString (healthcheck.remote_username != "") healthcheck.remote_username}"
            HEALTHCHECK_REMOTE_CMD="${healthcheck.remote_cmd}"
          ''}
        '';
      })
      cfg.instances;

    systemd.services = mapAttrs'
      (name: instance: nameValuePair "luks-ssh-unlock-${name}" {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          EnvironmentFile = "/etc/luks-ssh-unlock/${name}.env";
          ExecStart = "${pkgs.luks-ssh-unlock}/bin/luks-ssh-unlock";
        };
      })
      cfg.instances;
  };
}

