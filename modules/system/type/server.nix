{ den, inputs, ... }:
let
  data = import "${inputs.infrastructure-secrets}/secrets/users/root/data.nix";
in
{
  den.aspects.server = {
    includes = [ den.aspects.admin ];
    nixos =
      { config, lib, ... }:
      let
        cfg = config.my.server.networking;
        networkConfig = {
          Gateway = cfg.gateway;
          DNS = cfg.dns;
        };
      in
      {
        options.my.server.networking = {
          nodeIPAddress = lib.mkOption {
            type = lib.types.strMatching "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";
            example = "10.0.0.5";
            description = "IP address of the server on the bridge network";
          };

          gateway = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "10.0.0.1" ];
            description = "Gateway addresses";
          };

          dns = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "9.9.9.9"
              "1.1.1.1"
            ];
            description = "DNS server addresses";
          };

          nics = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Predictable network interface name";
                  };
                  mac = lib.mkOption {
                    type = lib.types.str;
                    description = "Permanent MAC address for udev link matching";
                  };
                };
              }
            );
            default = [ ];
            description = "NICs that are members of the br0 bridge";
          };

          standaloneNics = lib.mkOption {
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Predictable network interface name";
                  };
                  mac = lib.mkOption {
                    type = lib.types.str;
                    description = "Permanent MAC address for udev link matching";
                  };
                  address = lib.mkOption {
                    type = lib.types.str;
                    description = "IP address with CIDR prefix (e.g. 10.0.30.15/16)";
                  };
                };
              }
            );
            default = [ ];
            description = "NICs with their own IP address, not part of the bridge";
          };
        };

        config = {
          users.users.root.openssh.authorizedKeys.keys = [
            data.ssh_authorized_keys.server
          ];

          # https://wiki.nixos.org/wiki/Systemd/networkd
          # https://astro.github.io/microvm.nix/simple-network.html
          # Test:
          # networkctl
          systemd.network = {
            enable = true;

            netdevs = {
              "20-br0" = {
                netdevConfig = {
                  Kind = "bridge";
                  Name = "br0";
                };
              };
            };

            networks = {
              # Bridge
              "40-br0" = {
                matchConfig.Name = "br0";
                networkConfig = networkConfig // {
                  Address = [ "${cfg.nodeIPAddress}/16" ];
                };
                linkConfig.RequiredForOnline = "routable";
              };
            }
            // lib.listToAttrs (
              map (
                nic:
                lib.nameValuePair "30-${nic.name}" {
                  matchConfig.Name = nic.name;
                  networkConfig.Bridge = "br0";
                  linkConfig.RequiredForOnline = "enslaved";
                }
              ) cfg.nics
            )
            // lib.listToAttrs (
              map (
                nic:
                lib.nameValuePair "40-${nic.name}" {
                  matchConfig.Name = nic.name;
                  networkConfig = networkConfig // {
                    Address = [ nic.address ];
                  };
                  linkConfig.RequiredForOnline = false;
                }
              ) cfg.standaloneNics
            );

            links =
              lib.listToAttrs (
                map (
                  nic:
                  lib.nameValuePair "20-${nic.name}" {
                    matchConfig.PermanentMACAddress = nic.mac;
                    linkConfig.Name = nic.name;
                  }
                ) cfg.nics
              )
              // lib.listToAttrs (
                map (
                  nic:
                  lib.nameValuePair "20-${nic.name}" {
                    matchConfig.PermanentMACAddress = nic.mac;
                    linkConfig.Name = nic.name;
                  }
                ) cfg.standaloneNics
              );
          };

          networking.useDHCP = false;
        };
      };
  };
}
