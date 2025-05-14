{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  # Requires: hardware.sensor.iio.enable = true;
  rotate-display = pkgs.writeShellApplication {
    name = "rotate-display";
    runtimeInputs = with pkgs; [
      iio-sensor-proxy
      kdePackages.libkscreen
      gawk
    ];
    text = ''
      #!/usr/bin/env bash

      set -euo pipefail

      DISPLAY="eDP-1"

      # To get current rotation
      # output=$(kscreen-doctor --json)
      # rotation=$(echo "$output" | jq ".outputs[] | select(.name==\"$DISPLAY\") | .rotation")

      # Function to rotate the display
      rotate_display() {
        local new_rotation="$1"
        kscreen-doctor "output.$DISPLAY.rotation.$new_rotation"
      }

      # Monitor the sensor output
      monitor-sensor | while IFS= read -r line; do
        # Output the entire line to the console
        echo "$line"

        # Check if the line contains the orientation change
        if [[ "$line" == *"Accelerometer orientation changed:"* ]]; then
          # Extract the orientation from the output
          orientation=$(echo "$line" | awk '{print $NF}')
          echo "Detected orientation: $orientation"

          # Set the actions to be taken for each possible orientation
          case "$orientation" in
            normal)
              rotate_display "normal"
              echo "Display rotated to normal."
              ;;
            bottom-up)
              rotate_display "inverted"
              echo "Display rotated to inverted."
              ;;
            right-up)
              rotate_display "right"
              echo "Display rotated to right."
              ;;
            left-up)
              rotate_display "left"
              echo "Display rotated to left."
              ;;
            *)
              echo "Unknown orientation: $orientation"
              ;;
          esac
        fi
      done
    '';
  };
in {
  config = mkIf config.my.client.laptop.enable {
    services.power-profiles-daemon.enable = false; # Disable default power management used by KDE

    environment.systemPackages = with pkgs; [
      onboard # On-screen keyboard
      auto-cpufreq

      rotate-display
    ];

    boot.kernelParams = [
      # For optimal auto-cpufreq
      "initcall_blacklist=amd_pstate_init"
      "amd_pstate.enable=0"
    ];

    services.auto-cpufreq = {
      enable = true;
      # Docs: https://github.com/AdnanHodzic/auto-cpufreq
      settings = {
        battery = {
          governor = "powersave";
          turbo = "never";
          scaling_min_freq = 1400000; # This is min
          scaling_max_freq = 1700000;
          # Charging
          enable_thresholds = true;
          start_threshold = 20;
          stop_threshold = 80;
        };
        charger = {
          governor = "performance";
          turbo = "auto";
        };
      };
    };

    # Auto-rotate screen
    hardware.sensor.iio.enable = true;

    systemd.user.services.rotate-display = {
      description = "Rotate Display Based on Sensor Orientation";
      after = ["graphical.target"];
      serviceConfig = {
        ExecStart = "${rotate-display}/bin/rotate-display";
        Restart = "always";
        RestartSec = 5;
        Environment = "DISPLAY=:0";
      };
      wantedBy = ["default.target"];
    };

    # This below only if you need to change how the orientation is detected
    # > udevadm info -n  /dev/iio:device0
    # BMA250E
    # > cat /sys/class/dmi/id/modalias
    # svnLENOVO pn81SS

    # sensor:modalias:acpi:[driver name]*:dmi:*:svn[Manufacturer]*:pn[Product Name]:*

    #services.udev.extraHwdb = ''
    #  sensor:modalias:acpi:BMA250E*:dmi:*:svnLENOVO*:pn81SS:*
    #   ACCEL_MOUNT_MATRIX=0, 1, 0; 1, 0, 0; 0, 0, 1
    #'';

    # Test: sudo monitor-sensor
  };
}
