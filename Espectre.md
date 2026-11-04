# ESPectre (Wi-Fi motion detection) - findings

[ESPectre](https://github.com/francescopace/espectre) detects motion from Wi-Fi
channel state information (CSI), with no extra sensor. We tried it on the
living-room board on the bench (no heat pump attached) in November 2026.
**It is currently disabled.** This file records what we learned and what is left to test.

## Status

| | |
|---|---|
| Works on our boards (ESP32-D0WD-V3, ESP-IDF) | yes |
| Detected a person moving in the room (seen in Home Assistant) | yes, with CN105 out of the way |
| Coexists with the CN105 component | **not verified**, see below |
| Tested with a real heat pump attached | **no**, no unit installed yet |
| Long soak test (days) | not done |

## How to enable it in a room

`espectre.yaml` at the repo root is a self-contained add-on. It is not included by any
room, so the room configs stay clean. To enable it for one room, add this to that
room's `main.yaml`, next to the other includes:

```yaml
packages:
  espectre: !include ../espectre.yaml
```

Then `make upload` (USB) or `make ota ROOM=<room>`. To remove it, delete those lines
and reflash (see the Home Assistant cleanup note below).

It is a `packages:` include, not a `<<` include, on purpose: `<<` silently drops a
section that already exists, and `sensor:` / `external_components:` already exist in
`climate.yaml`.

The file pulls the component from GitHub, **pinned to tag 3.1.0**, enables the
`lightweight` algorithm with the `ping` traffic generator, turns off the extra HTTP
server (`direct_api: false`), sets `cpu_frequency: 240MHz`, and adds diagnostic sensors
(uptime, Wi-Fi signal, free heap, largest heap block, loop time, reset reason).
Declaring `espectre:` creates its default entities.

## Gotchas

- **The esphome.io docs describe a different version.** That page documents `espectre`
  as `binary_sensor` / `sensor` / `button` platforms. ESPHome 2026.8.2 does not include
  it, and tag 3.1.0 is a standalone external component where a bare `espectre:` creates
  the entities. We followed the repo's own `examples/espectre-esp32.yaml`.
- **Entity names:** the motion binary sensor is "Motion Detected", the score is
  "Movement Score".
- **It detects motion, not presence.** A person sitting still reads as "no motion"
  within about a second. For occupancy use a hold-off timer (a template binary sensor
  with `delayed_off`), another signal, or an mmWave sensor (LD2410 / LD2450).
- **Side effects:** power save is forced off, AMPDU is disabled (so OTA is a bit
  slower), and the ESP32 TX rate is fixed at 6.5 Mbps. Use 2.4 GHz.
- **Placement matters:** the board will sit in or next to a ceiling-mounted indoor
  unit. Detection quality there is unknown; the bench test was in open air.
- **Home Assistant cleanup:** removing ESPectre leaves its entities as "unavailable"
  orphans in the entity registry. Delete them under Settings, Devices & services,
  Entities, or delete and re-add the ESPHome device.

## The problem: CN105 breaks CSI

On the bench, CSI is healthy for about 15 seconds after boot (about 100 accepted
packets/s, 91-94% occupancy, calibration completes). Then it collapses to 2-5 accepted
packets/s and 0-12% occupancy, and stays there. Detection needs at least 70% occupancy,
so it can no longer detect anything. Reproduced on every boot.

### Cause (found, not yet fixed)

With no heat pump attached, the CN105 component's handshake fails every 10 s and it
calls `force_low_level_uart_reinit()`.

1. `get_uart_port_index()` in `climate.py` guesses the UART port from the position of
   the `uart:` block in the config. The first (here only) one becomes port 0.
2. `force_low_level_uart_reinit()` reconfigures **UART0** to the heat pump settings
   (2400 baud, 8E1, GPIO17/18).
3. On the ESP32, UART0 is the **logger console**. The console is now at 2400 baud
   (about 240 bytes/s), so each log line blocks the main loop for about a second.
   ESPectre logged "Runtime loop took ~1150 ms ... log sink 1150 ms".
4. ESPectre's loop is starved, CSI frames go stale and are dropped.

Side effect: USB serial logs go silent after the first reinit.

### Evidence

| Build | CN105 handshake failures | CSI accepted/s | Occupancy | Loop stalls |
|---|---|---|---|---|
| Full config | repeating every 10 s | about 100, then 2-5 | 91-94%, then 0-12% | frequent, about 1 s |
| CN105 removed | n/a | 99-100 steady | 87-93% steady | none |
| Full config + `logger: baud_rate: 0` | 10 in the window | 99-100 steady | 91-95% steady | none |

Each steady run was watched for about 100 s. That is evidence of the cause, not a
soak test.

### Workaround (not applied)

Add `baud_rate: 0` to `logger:` in `device.yaml`. This disables UART logging, so the
console hijack becomes harmless. Logs are still available over Wi-Fi
(`esphome logs <room>/main.yaml --device <name>.local`), but `make logs` over USB would
show nothing, so it would need to use the network.

### Upstream

The port detection bug is in
[echavet/MitsubishiCN105ESPHome](https://github.com/echavet/MitsubishiCN105ESPHome)
(`components/cn105/climate.py` and `cn105.cpp`). No issue has been filed yet. The other
rooms share the same code, so they also stall if a handshake fails, ESPectre or not.

## To do when the first unit is installed

1. Re-enable ESPectre on that room only (see above).
2. Check whether the CN105 handshake succeeds. If it does, the retry loop may never run
   and the problem may not appear. If it does appear, apply the workaround.
3. Watch the CSI Accepted Rate and CSI Temporal Occupancy sensors, free heap, reset
   reason and loop time for several days.
4. Check detection range and sensitivity with the board in place, and recalibrate with
   the room empty.
5. If the CN105 UART reinit still breaks CSI on real hardware, file the upstream issue.
