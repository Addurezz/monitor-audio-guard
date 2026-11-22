# Monitor Audio Guard for macOS

Choose a default audio output and keep macOS from routing standard audio or system sounds to a DisplayPort or HDMI monitor. The guard redirects those defaults to your chosen output when it is available.

## Install

1. Download **Monitor-Audio-Guard-macOS.zip** from the [latest GitHub release](https://github.com/Addurezz/monitor-audio-guard/releases/latest).
2. Unzip it and double-click **Setup.command**.
3. Choose your speakers, headphones, or other preferred output by number.

Setup selects the output immediately. It also uses the same output for system sounds if the device supports them. The guard starts right away and runs each time you sign in. To change the saved output, run **Setup.command** again.

The release contains a ready-to-run binary for Apple silicon and Intel Macs running macOS 15 or later. This build is not notarized by Apple. If macOS blocks the first launch and you trust the download, use **System Settings → Privacy & Security → Open Anyway**. [Apple's instructions](https://support.apple.com/en-us/102445)

## How routing works

The guard redirects audio only when macOS selects a DisplayPort or HDMI output. You can still switch to other speakers or headphones temporarily. If the preferred device is disconnected, the guard tries the most recently used allowed output, then the built-in speakers, then any remaining eligible output.

The monitor remains selectable in macOS Sound settings. Apps with their own device selection can still use it. Microphone settings stay as configured. Automatic switching was tested with an LG 38GN950 over DisplayPort. HDMI recognition uses Core Audio's connection type and has yet to be tested on HDMI hardware.

## Run from source

With the Xcode Command Line Tools installed, run `./setup.sh` for the same interactive setup, or run `./monitor-audio-guard.swift` to watch from Terminal until you press **Ctrl+C**.

| Option | What it does |
| --- | --- |
| `--list` | Shows audio outputs and their detected connection types. |
| `--outputs` | Lists allowed outputs with their persistent device UIDs. |
| `--preferred UID` | Prefers this output when redirecting away from a monitor. |
| `--preferred UID --set-default` | Sets this output immediately and exits. |
| `--once` | Checks the outputs once and exits. |
| `--exclude "Device Name"` | Avoids another output by exact name. You can repeat this option. |

For a USB-C monitor that reports itself as USB audio, use `--exclude` when running the guard manually. Use `--list` to find its exact name.

## Uninstall

Double-click **Uninstall.command** or run `./setup.sh --uninstall` from the source folder. This removes the background service. The current macOS output stays selected.
