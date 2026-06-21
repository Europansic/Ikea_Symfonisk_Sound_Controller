# IKEA SYMFONISK Sound Controller – SmartThings Edge Driver + Sonos Integration

A SmartThings **Edge Driver** for the IKEA SYMFONISK Sound Controller (Zigbee remote),
plus optional **Rules API** integration to control a Sonos speaker.

> Based on the original Groovy DTH by [jusa80 (Juha Tanskanen)](https://github.com/jusa80/smartthings),
> ported to the modern SmartThings Edge architecture.

Here is the Invite Link
https://bestow-regional.api.smartthings.com/invite/Boj0wAyOmqlA

---

## Features

| Action | Result |
|--------|--------|
| Single press | Play / Pause (Sonos) |
| Double press | Next Track |
| Triple press | Previous Track |
| Turn knob | Volume / Dimmer level |

- Battery reporting
- **Runs fully local** on the SmartThings Hub — no cloud dependency
- Compatible with SmartThings Routines and Rules API

---

## Requirements

- SmartThings Hub with Zigbee support (e.g. Aeotec Hub, SmartThings Hub v2/v3)
- IKEA SYMFONISK Sound Controller (Zigbee)
- [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli) installed
- *(Optional)* Sonos speaker connected to SmartThings

---

## Installation

### 1 – Install the Edge Driver

```bash
# Clone this repo
git clone https://github.com/YOUR_USERNAME/ikea-symfonisk-smartthings.git
cd ikea-symfonisk-smartthings

# Package and upload the driver to your hub
smartthings edge:drivers:package edge-driver/
smartthings edge:drivers:install
```

### 2 – Pair the SYMFONISK

1. In the SmartThings app → **Add Device** → **Scan nearby**
2. Hold the SYMFONISK button for **4 seconds** until the LED blinks
3. The device should appear as **"IKEA SYMFONISK Sound Controller"**

> **Important:** The driver must be installed on your hub *before* pairing.
> If you paired it before, remove the device and re-pair it.

### 3 – (Optional) Set up Sonos Rules

If you want the SYMFONISK to control a Sonos speaker:

```bash
cd sonos-rules/
chmod +x setup_rules.sh
./setup_rules.sh
```

The script will interactively ask for:
- Your SmartThings Personal Access Token ([create one here](https://account.smartthings.com/tokens))
- Your Location ID
- Your SYMFONISK Device ID
- Your Sonos Device ID

It then uploads 4 rules that run **locally** on your hub.

---

## File Structure

```
├── edge-driver/
│   ├── config.yml          # Driver metadata
│   ├── fingerprints.yml    # Zigbee device matching
│   ├── profiles/
│   │   └── symfonisk.yml   # SmartThings device profile
│   └── src/
│       └── init.lua        # Driver logic (Lua)
└── sonos-rules/
    ├── 01_play_pause.json
    ├── 02_next_track.json
    ├── 03_previous_track.json
    ├── 04_volume_sync.json
    └── setup_rules.sh      # Interactive setup script
```

---

## How It Works

The SYMFONISK sends Zigbee ZCL commands when operated:

| Physical Action | ZCL Cluster | Command | SmartThings Event |
|----------------|-------------|---------|-------------------|
| 1× press | OnOff (0x0006) | Toggle (0x02) | `button.pushed` |
| 2× press | Level (0x0008) | Step Up (0x02) | `button.pushed_2x` |
| 3× press | Level (0x0008) | Step Down (0x02) | `button.pushed_3x` |
| Knob turn | Level (0x0008) | Move (0x01) | `switchLevel.level` |
| Knob stop | Level (0x0008) | Stop (0x03) | *(level updated)* |

The knob level is calculated time-based: turning for 4 seconds = 100% change.

---

## AI Disclosure

See [AI_DISCLOSURE.md](AI_DISCLOSURE.md).

---

## Credits

- Original Groovy DTH: [jusa80 / Juha Tanskanen](https://github.com/jusa80/smartthings)
- Edge Driver port & Sonos integration: Leo (GN) with AI assistance
