# Zigbee

## CH9102X

Get into bootloader mode by pressing and holding K1 key before plugging it in and releasing it couple of seconds later.

Coordinator:

```sh
# Samole only
git clone https://github.com/JelmerT/cc2538-bsl.git
cd cc2652p-bsl
wget https://github.com/Koenkk/Z-Stack-firmware/raw/master/coordinator/Z-Stack_3.x.0/bin/CC1352P2_CC2652P_launchpad_coordinator_20230507.zip
unzip CC1352P2_CC2652P_launchpad_coordinator_20230507.zip
pip install wheel pyserial intelhex python-magic
pip install zigpy-znp
python3 -m zigpy_znp.tools.nvram_read /dev/tty.usbserial-* -o nvram_backup.json
python3 cc2538-bsl.py -e -v -w  CC1352P2_CC2652P_launchpad_coordinator_20230507.hex
```

Router (tested):

```sh
git clone https://github.com/JelmerT/cc2538-bsl.git
cd cc2538-bsl/cc2538_bsl
wget https://github.com/Koenkk/Z-Stack-firmware/raw/master/router/Z-Stack_3.x.0/bin/CC1352P2_CC2652P_launchpad_router_20221102.zip
unzip CC1352P2_CC2652P_launchpad_router_20221102.zip
pip install wheel pyserial intelhex python-magic
pip install zigpy-znp
#python3 -m zigpy_znp.tools.nvram_read /dev/ttyACM0 -o nvram_backup.json
python3 cc2538_bsl.py -e -v -w  CC1352P2_CC2652P_launchpad_router_20221102.hex
```

Note that CH9102X seems to have a bug that will render the device unresponsive (permanently) if the user trys to change power (dB) of the device in Zigbee2MQTT.

A good tool on Windows is [ZigStarGW](https://github.com/xyzroe/ZigStarGW-MT/releases/).
