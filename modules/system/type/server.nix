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
          bridges = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  ip = lib.mkOption {
                    type = lib.types.strMatching "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";
                    example = "10.0.0.5";
                    description = "IP address of the bridge interface";
                  };
                  cidr = lib.mkOption {
                    type = lib.types.ints.between 1 128;
                    default = 16;
                    description = "CIDR prefix length for the bridge address";
                  };
                  members = lib.mkOption {
                    type = lib.types.attrsOf (
                      lib.types.submodule {
                        options = {
                          mac = lib.mkOption {
                            type = lib.types.str;
                            description = "Permanent MAC address for udev link matching";
                          };
                        };
                      }
                    );
                    default = { };
                    description = "Physical NICs that are members of this bridge, keyed by interface name";
                  };
                };
              }
            );
            default = { };
            description = "Bridge interfaces with their IP configuration and member NICs";
          };

          standaloneNics = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  ip = lib.mkOption {
                    type = lib.types.strMatching "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";
                    description = "IP address of the interface";
                  };
                  cidr = lib.mkOption {
                    type = lib.types.ints.between 1 128;
                    default = 16;
                    description = "CIDR prefix length for this interface";
                  };
                  mac = lib.mkOption {
                    type = lib.types.str;
                    description = "Permanent MAC address for udev link matching";
                  };
                };
              }
            );
            default = { };
            description = "NICs with their own IP address, not part of any bridge, keyed by interface name";
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

            netdevs = lib.mapAttrs' (
              name: _:
              lib.nameValuePair "20-${name}" {
                netdevConfig = {
                  Kind = "bridge";
                  Name = name;
                };
              }
            ) cfg.bridges;

            networks =
              # Bridge networks
              lib.mapAttrs' (
                name: brCfg:
                lib.nameValuePair "40-${name}" {
                  matchConfig.Name = name;
                  networkConfig = networkConfig // {
                    Address = [ "${brCfg.ip}/${toString brCfg.cidr}" ];
                  };
                  linkConfig.RequiredForOnline = "routable";
                }
              ) cfg.bridges
              # Bridge member networks
              //
                lib.foldl'
                  (
                    acc:
                    { bridge, member }:
                    acc
                    // {
                      "30-${member}" = {
                        matchConfig.Name = member;
                        networkConfig.Bridge = bridge;
                        linkConfig.RequiredForOnline = "enslaved";
                      };
                    }
                  )
                  { }
                  (
                    lib.concatLists (
                      lib.mapAttrsToList (
                        bridge: brCfg: lib.mapAttrsToList (member: _: { inherit bridge member; }) brCfg.members
                      ) cfg.bridges
                    )
                  )
              # Standalone NIC networks
              // lib.mapAttrs' (
                name: nicCfg:
                lib.nameValuePair "40-${name}" {
                  matchConfig.Name = name;
                  networkConfig = networkConfig // {
                    Address = [ "${nicCfg.ip}/${toString nicCfg.cidr}" ];
                  };
                  linkConfig.RequiredForOnline = false;
                }
              ) cfg.standaloneNics;

            links =
              # Bridge member links
              lib.foldl'
                (
                  acc: item:
                  acc
                  // {
                    "20-${item.member}" = {
                      matchConfig.PermanentMACAddress = item.mac;
                      linkConfig.Name = item.member;
                    };
                  }
                )
                { }
                (
                  lib.concatLists (
                    lib.mapAttrsToList (
                      _: brCfg:
                      lib.mapAttrsToList (member: memCfg: {
                        inherit member;
                        inherit (memCfg) mac;
                      }) brCfg.members
                    ) cfg.bridges
                  )
                )
              # Standalone NIC links
              // lib.mapAttrs' (
                name: nicCfg:
                lib.nameValuePair "20-${name}" {
                  matchConfig.PermanentMACAddress = nicCfg.mac;
                  linkConfig.Name = name;
                }
              ) cfg.standaloneNics;
          };

          networking.useDHCP = false;
        };
      };
  };
}
