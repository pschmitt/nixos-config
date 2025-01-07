{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.luks-ssh-unlocker;
in
{
  options.services.luks-ssh-unlocker = {
    enable = mkEnableOption "LUKS SSH Unlocker Service";
    instances = mkOption {
      type = types.attrsOf (
        types.submodule ({
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
              default = "systemd";
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
            jumpHost = mkOption {
              type = types.nullOr (
                types.submodule {
                  options = {
                    enable = mkEnableOption "Enable jumphost.";
                    hostname = mkOption {
                      type = types.str;
                      description = "Jumphost hostname.";
                    };
                    username = mkOption {
                      type = types.str;
                      description = "Jumphost SSH username.";
                      default = "root";
                    };
                    key = mkOption {
                      type = types.path;
                      description = "Jumphost SSH key path.";
                      default = "/etc/ssh/ssh_host_ed25519_key";
                    };
                    port = mkOption {
                      type = types.int;
                      default = 22;
                      description = "Jumphost SSH port.";
                    };
                  };
                }
              );
              default = null;
              description = "Optional jumphost configuration.";
            };
            sleepInterval = mkOption {
              type = types.int;
              default = 15;
              description = "Time to wait between attempts.";
            };
            healthcheck = mkOption {
              type = types.submodule {
                options = {
                  enable = mkEnableOption "Healthcheck on/off.";
                  port = mkOption {
                    type = types.nullOr types.int;
                    description = "Health check port.";
                    default = null;
                  };
                  hostname = mkOption {
                    type = types.str;
                    description = "Remote hostname to run the command on.";
                    default = "";
                  };
                  username = mkOption {
                    type = types.str;
                    description = "Remote username for the remote healthcheck command.";
                    default = "";
                  };
                  command = mkOption {
                    type = types.str;
                    description = "Remote command to verify the status.";
                    default = "";
                  };
                };
              };
              description = "Health check configuration.";
            };
            emailNotifications = mkOption {
              type = types.submodule {
                options = {
                  enable = mkEnableOption "Enable email notifications.";
                  recipient = mkOption {
                    type = types.str;
                    description = "Email recipient address.";
                    default = "";
                  };
                  sender = mkOption {
                    type = types.str;
                    description = "Email sender address.";
                    default = "";
                  };
                  subject = mkOption {
                    type = types.str;
                    description = "Email subject (supports templating).";
                    default = "";
                  };
                };
              };
              description = "Email notifications";
            };
          };
        })
      );
      description = "Configuration for multiple LUKS SSH Unlocker instances.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.luks-ssh-unlock ];

    # Define environment files
    environment.etc = mapAttrs' (
      name: instance:
      nameValuePair "luks-ssh-unlock/${name}.env" {
        text = with instance; ''
          DEBUG=${optionalString (debug == true) "1"}
          SLEEP_INTERVAL=${toString sleepInterval}

          SSH_HOSTNAME=${hostname}
          SSH_USER=${username}
          SSH_KEY=${key}
          SSH_PORT=${toString port}

          FORCE_IPV4=${optionalString (forceIpv4 == true) "1"}
          FORCE_IPV6=${optionalString (forceIpv6 == true) "1"}

          ${optionalString (instance.jumpHost.enable) ''
            SSH_JUMPHOST=${optionalString (jumpHost.hostname != null) jumpHost.hostname}
            SSH_JUMPHOST_USERNAME=${optionalString (jumpHost.username != null) jumpHost.username}
            SSH_JUMPHOST_PORT=${optionalString (jumpHost.port != null) (toString jumpHost.port)}
            SSH_JUMPHOST_KEY=${optionalString (jumpHost.key != null) jumpHost.key}
          ''}

          LUKS_PASSPHRASE=${passphrase}
          LUKS_PASSPHRASE_FILE=${passphraseFile}
          LUKS_TYPE=${type}

          ${optionalString (instance.healthcheck.enable) ''
            HEALTHCHECK_PORT=${optionalString (healthcheck.port != null) (toString healthcheck.port)}
            HEALTHCHECK_REMOTE_HOSTNAME="${optionalString (healthcheck.hostname != "") healthcheck.hostname}"
            HEALTHCHECK_REMOTE_USERNAME="${optionalString (healthcheck.username != "") healthcheck.username}"
            HEALTHCHECK_REMOTE_CMD="${healthcheck.command}"
          ''}

          ${optionalString (instance.emailNotifications.enable) ''
            EMAIL_RECIPIENT="${
              optionalString (emailNotifications.recipient != "") emailNotifications.recipient
            }"
            EMAIL_SENDER="${optionalString (emailNotifications.sender != "") emailNotifications.sender}"
            EMAIL_SUBJECT="${optionalString (emailNotifications.subject != "") emailNotifications.subject}"
          ''}
        '';
      }
    ) cfg.instances;

    systemd.services = mapAttrs' (
      name: instance:
      nameValuePair "luks-ssh-unlock-${name}" {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          EnvironmentFile = "/etc/luks-ssh-unlock/${name}.env";
          ExecStart = "${pkgs.luks-ssh-unlock}/bin/luks-ssh-unlock";
        };
      }
    ) cfg.instances;
  };
}
