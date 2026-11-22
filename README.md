# Monitor Audio Guard für macOS

Das Skript überwacht den Standardausgang für Wiedergabe und Systemtöne. Sobald macOS dafür einen HDMI- oder DisplayPort-Ausgang auswählt, schaltet es auf den zuvor verwendeten anderen Ausgang zurück. Ist dieser nicht verfügbar, bevorzugt es eingebaute Lautsprecher.

## Starten

Öffne ein Terminal im Ordner des Skripts und führe aus:

```bash
./monitor-audio-guard.swift
```

Das Skript benötigt Swift aus den Xcode Command Line Tools. Die Überwachung läuft im Terminal bis **Ctrl+C**.

| Option | Funktion |
| --- | --- |
| `--list` | Zeigt Audioausgänge und ihren erkannten Verbindungstyp an. |
| `--once` | Prüft die Ausgänge einmal und beendet sich. |
| `--exclude "Gerätename"` | Bezieht einen weiteren Ausgang anhand seines exakten Namens ein. Wiederholbar. |

Mit `--exclude` kannst du etwa einen USB-C-Monitor erfassen, dessen Audiogerät sich als USB-Audio statt DisplayPort oder HDMI meldet. Den Namen zeigt `--list`.

## Umfang

Der Monitor bleibt im macOS-Tonmenü auswählbar. Apps mit eigener Geräteauswahl können ihn weiterhin direkt verwenden. Das Skript ändert ausschließlich die Standardausgänge und lässt den Mikrofoneingang in Ruhe.

Der automatische Rückwechsel wurde mit einem LG 38GN950 über DisplayPort geprüft. Die HDMI-Erkennung nutzt den von Core Audio gemeldeten Verbindungstyp und wurde noch nicht mit einem HDMI-Gerät geprüft.
