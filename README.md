# ESP CN105 Configuration

This repo is modified from the one used for this YouTube video: https://youtu.be/I7jC5Xi063E

This is based on the project here: https://github.com/echavet/MitsubishiCN105ESPHome

**See the above repository for much more in-depth customization and guidance**

## Devices

Each room is its own self-contained directory, with its own `main.yaml`, its own `secrets.yaml`, and its own copies of `device.yaml`/`climate.yaml`/`connection.yaml` (independent per device, not shared, by design):

- `living-room/`
- `bedroom/`
- `kid-room/`
- `office/`

## Optional: ESPectre motion detection

Wi-Fi based motion detection is available as an optional add-on (`espectre.yaml`), disabled in every room for now. See [Espectre.md](Espectre.md) for how to enable it in a room, the test findings, and the known conflict with the CN105 component.

## Remote room temperature (Zigbee sensors)

Each device's `main.yaml` has a `remote_temperature_entity_id` substitution used to feed a Home Assistant sensor entity (e.g. a Zigbee thermometer) into the heat pump as the reference temperature, instead of relying on the indoor unit's own built-in sensor. It ships as a placeholder (`sensor.CHANGE_ME_<room>_temperature`) - replace it with your room's actual entity ID, then `make compile`/`make upload` that device for it to take effect. If the sensor stops updating, the unit falls back to its internal sensor after `remote_temperature_timeout` (set in `climate.yaml`).

## WiFi provisioning

If a device can't reach its configured WiFi network, it falls back to its own hotspot (SSID = the device name, e.g. `living-room-ac`, password in that device's `secrets.yaml` as `ap_password`). Connect a phone/laptop to it and visit `http://192.168.4.1` to set new WiFi credentials via a plain setup page - no app or special browser required.

## Flashing via the Makefile

The `Makefile` at the repo root auto-detects which ESP32 is currently plugged in over USB (by its MAC address) and resolves it to the right device directory via a `<mac> -> <room>/` symlink.

```
source venv/bin/activate

make whoami                  # show detected port/MAC/config for the plugged-in board
make register ROOM=bedroom   # first time only: link the currently plugged-in board to bedroom/
make compile                 # esphome compile <resolved config>
make upload                  # esphome compile + upload <resolved config>
make logs                    # esphome logs <resolved config>
make clean                   # esphome clean <resolved config>
```

Override the port if auto-detection picks the wrong device: `make upload PORT=/dev/ttyUSB0`.

## Setup Instructions
### First time
```
1. python3 -m venv venv
2. source venv/bin/activate
3. pip install esphome
4. ls -la /dev/tty*
5. make whoami
6. make register ROOM=<name>   # once per new board
7. make upload
```
---

### Re-entry
```
1. source venv/bin/activate
2. make whoami
3. make upload
```

## Wiring

### ESP32 connections

This table is specific to the ESP32 board and the cable purchased for this
project

| Color  | Board pin                   | CN105 wire             | Notes                                                           |
|--------|-----------------------------|------------------------|-----------------------------------------------------------------|
| Black  | n/a                         | Wire 1 (12V)           | Leave unconnected                                               |
| Red    | `GND` (next to `VIN`)       | Wire 2 (GND)           |                                                                 |
| White  | `VIN` (top-left)            | Wire 3 (5V)            | **Not** `3V3` - that's a regulated *output*, never back-feed it |
| Yellow | `D18` / GPIO18 (bottom row) | Wire 4 (TX, from unit) | This is `rx_pin` in `climate.yaml`                              |
| Orange | `D17` / GPIO17 (bottom row) | Wire 5 (RX, to unit)   | This is `tx_pin` in `climate.yaml`                              |

**Important**: use `D17`/`D18` in the bottom row, **not** `RX0`/`TX0` further along the same row. `RX0`/`TX0` are the chip's UART0, used for USB flashing and the serial console - wiring the CN105 to those pins conflicts with flashing/logging.

### Safety notes

- Getting **12V/5V/GND wrong** can damage the board - if in doubt, verify with a multimeter before connecting.
- Getting **TX/RX swapped** is harmless - worst case, the climate entity just won't communicate with the unit. Simply swap the two wires and try again.

### CN105 connector pinout (background)

The CN105 connector is a 5-pin JST-style header on the indoor unit's control board. **Wire colors are not standardized** across cables/manufacturers. CN105 wire *position* is authoritative (per the [MitsubishiCN105ESPHome library docs](https://github.com/echavet/MitsubishiCN105ESPHome)), with wire 1 conventionally being the wire nearest the connector's keyed/marked edge, in order: 12V (unused), GND, 5V, TX (from unit), RX (to unit).
