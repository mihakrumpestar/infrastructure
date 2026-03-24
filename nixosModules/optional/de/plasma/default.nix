{
  config,
  lib,
  #pkgs,
  ...
}:
with lib; {
  options.my = {
    de.plasma = {
      enable = mkEnableOption "Custom Plasma configuration";
    };
  };

  config = mkIf config.my.de.plasma.enable {
    # Enable the Plasma desktop environment
    services = {
      # xserver.enable = true; # optional, enables Xorg
      displayManager = {
        sddm = {
          enable = true;
          wayland.enable = true;
        };
      };

      desktopManager.plasma6.enable = true;
    };

    home-manager.sharedModules = [
      {
        # Run command below to get current config, options are at: https://nix-community.github.io/plasma-manager/options.xhtml
        # nix run github:nix-community/plasma-manager
        programs.plasma = {
          enable = true;
          shortcuts = {
            ksmserver = {
              "Log Out Without Confirmation" = ["Meta+L"];
              "Reboot Without Confirmation" = ["Meta+R"];
              "Shut Down" = ["Meta+Q"];
            };

            yakuake.toggle-window-state = "F12";
            "services/net.local.fuzzel.desktop"._launch = "Meta+Space"; # TODO: does not work
          };

          configFile = {
            baloofilerc."Basic Settings".Indexing-Enabled = false;
            kwalletrc.Wallet.Enabled = false; # We are using KeepassXC as secret-service provider

            spectaclerc.General.clipboardGroup = "PostScreenshotCopyImage";

            yakuakerc = {
              Dialogs.FirstRun = false;
              Window = {
                Height = 95;
                Width = 95;
              };
            };

            #kcminputrc."Libinput/1121/16386/Royuan ROYUAN Gaming Keyboard Consumer Control".ScrollFactor = 7;
            #kcminputrc."Libinput/1121/16386/Royuan ROYUAN Gaming Keyboard Mouse".PointerAcceleration = 0.600;
            #kcminputrc."Libinput/1121/16386/Royuan ROYUAN Gaming Keyboard Mouse".PointerAccelerationProfile = 2;
            #kcminputrc."Libinput/9639/64016/Nordic 2.4G Wireless Receiver Mouse".PointerAcceleration = 1.000;

            kded5rc.Module-browserintegrationreminder.autoload = false;
            kdeglobals."KFileDialog Settings"."Show hidden files" = true;
          };

          input = {
            keyboard.layouts = [
              {
                layout = "si";
              }
              {
                layout = "us";
              }
            ];
            mice = [
              {
                enable = true;
                scrollSpeed = 1;
                acceleration = 0.6;
                accelerationProfile = "none";
                naturalScroll = false;
                name = "Nordic 2.4G Wireless Receiver Mouse";
                productId = "9639";
                vendorId = "64016";
              }
            ];
          };

          kscreenlocker.timeout = 30; # In minutes

          kwin = {
            effects = {
              blur = {
                enable = true;
                strength = 5;
              };
              translucency.enable = true;
            };
            nightLight = {
              enable = true;
              mode = "automatic";
              temperature = {
                night = 5000; # Going lower too much reduces contrast on displays with reduces brightness
              };
              transitionTime = 30;
            };
          };

          panels = [
            # Windows-like panel at the bottom
            # cat  ~/.config/plasma-org.kde.plasma.desktop-appletsrc
            {
              location = "bottom";
              height = 50;

              widgets = [
                "org.kde.plasma.kickoff"
                "org.kde.plasma.pager"
                {
                  name = "org.kde.plasma.systemmonitor.cpu";
                  config = {
                    CurrentPreset = "org.kde.plasma.systemmonitor";
                    Appearance = {
                      chartFace = "org.kde.ksysguard.piechart";
                      title = "Total CPU Use";
                      updateRateLimit = 1000;
                    };
                    Sensors = {
                      highPrioritySensorIds = ''["cpu/all/usage"]'';
                      lowPrioritySensorIds = ''["cpu/all/cpuCount","cpu/all/coreCount"]'';
                      totalSensors = ''["cpu/all/usage"]'';
                    };
                    SensorColors = {
                      "cpu/all/usage" = "46,157,174";
                    };
                  };
                }
                {
                  name = "org.kde.plasma.systemmonitor.memory";
                  config = {
                    CurrentPreset = "org.kde.plasma.systemmonitor";
                    Appearance = {
                      chartFace = "org.kde.ksysguard.piechart";
                      title = "Memory Usage";
                      updateRateLimit = 1000;
                    };
                    Sensors = {
                      highPrioritySensorIds = ''["memory/physical/used"]'';
                      lowPrioritySensorIds = ''["memory/physical/total"]'';
                      totalSensors = ''["memory/physical/usedPercent"]'';
                    };
                    SensorColors = {
                      "memory/physical/used" = "46,157,174";
                    };
                  };
                }
                "org.kde.plasma.icontasks"
                "org.kde.plasma.marginsseparator"
                "org.kde.plasma.systemtray"
                {
                  digitalClock = {
                    calendar.firstDayOfWeek = "monday";
                    time.format = "24h";
                  };
                }
                "org.kde.plasma.showdesktop"
              ];
            }
          ];

          powerdevil = {
            general.pausePlayersOnSuspend = true;

            AC = {
              powerProfile = "performance";
              powerButtonAction = "shutDown";
              whenSleepingEnter = "standbyThenHibernate";
              whenLaptopLidClosed = "sleep";
              inhibitLidActionWhenExternalMonitorConnected = true;

              turnOffDisplay = {
                idleTimeout = 30 * 60; # In seconds
                idleTimeoutWhenLocked = 60; # In seconds
              };
            };

            batteryLevels = {
              lowLevel = 10; # 0 to 100
              criticalLevel = 5; # 0 to 100
              criticalAction = "hibernate";
            };

            battery = {
              powerProfile = "powerSaving";
              powerButtonAction = "showLogoutScreen";
              whenSleepingEnter = "standbyThenHibernate";
              whenLaptopLidClosed = "hibernate";
              inhibitLidActionWhenExternalMonitorConnected = true;

              turnOffDisplay = {
                idleTimeout = 5 * 60; # In seconds
                idleTimeoutWhenLocked = 60; # In seconds
              };

              autoSuspend = {
                action = "sleep";
                idleTimeout = 5 * 60 + 20; # In seconds
              };
            };

            lowBattery = {
              powerProfile = "powerSaving";
              whenLaptopLidClosed = "hibernate";

              turnOffDisplay = {
                idleTimeout = 60; # In seconds
                idleTimeoutWhenLocked = 60; # In seconds
              };

              autoSuspend = {
                action = "hibernate";
                idleTimeout = 2 * 60 + 20; # In seconds
              };

              dimDisplay = {
                enable = true;
                idleTimeout = 30; # In seconds
              };
              displayBrightness = 20; # 0 to 100

              dimKeyboard.enable = true;
              keyboardBrightness = 30; # 0 to 100
            };
          };

          windows.allowWindowsToRememberPositions = true;
          workspace.enableMiddleClickPaste = true;

          session.sessionRestore.restoreOpenApplicationsOnLogin = "startWithEmptySession";
        };
      }
    ];

    # Audio
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      #jack.enable = true; # Only if you need it
    };
  };
}
