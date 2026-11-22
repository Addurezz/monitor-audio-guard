# Monitor Audio Guard for macOS

The script watches the default output for audio playback and system sounds. When macOS selects an HDMI or DisplayPort output, the script switches back to the last used non-monitor output. If that output is unavailable, it prefers the built-in speakers.

## Run the script

Open Terminal in the script's folder and run:

```bash
./monitor-audio-guard.swift
```

The script requires Swift from the Xcode Command Line Tools. It keeps watching until you press **Ctrl+C**.

| Option | What it does |
| --- | --- |
| `--list` | Lists audio outputs and their detected connection types. |
| `--once` | Checks the outputs once and exits. |
| `--exclude "Device Name"` | Avoids an additional output by its exact name. You can repeat this option. |

Use `--exclude` for a USB-C monitor that reports its audio output as USB audio. Run `--list` to find the device name.

## What it changes

The monitor remains selectable in macOS Sound settings. Apps with their own device selection can still use it directly. The script changes the default outputs for audio playback and system sounds. Microphone settings stay as configured.

Automatic switching was tested with an LG 38GN950 over DisplayPort. HDMI detection uses the connection type reported by Core Audio. It has yet to be tested with an HDMI device.
