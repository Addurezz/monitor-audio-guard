#!/usr/bin/swift
import CoreAudio
import Foundation

private let usage = """
Verwendung:
  ./monitor-audio-guard.swift [--list] [--once] [--exclude "Gerätename"]

Leitet den Standardton und Systemtöne von HDMI- und DisplayPort-Ausgängen um.
--list     Ausgänge und Erkennung anzeigen, ohne etwas umzustellen.
--once     Einmal prüfen und beenden. Ohne Option läuft die Überwachung bis Ctrl+C.
--exclude  Einen weiteren Ausgang per exaktem Namen ausschließen. Mehrfach möglich.
"""

private struct GuardError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct Options {
    var list = false
    var once = false
    var excludedNames: Set<String> = []

    init(_ args: [String]) throws {
        var arguments = args.makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--list": list = true
            case "--once": once = true
            case "--exclude":
                guard let name = arguments.next(), !name.isEmpty, !name.hasPrefix("--") else {
                    throw GuardError(message: "--exclude erwartet einen Gerätenamen.")
                }
                excludedNames.insert(name)
            default:
                throw GuardError(message: "Unbekannte Option: \(argument)\n\(usage)")
            }
        }
    }
}

private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

private struct Output {
    let device: AudioHardwareDevice
    let name: String
    let uid: String
    let transport: UInt32
    let canPlayAudio: Bool
    let canPlayEffects: Bool

    init?(_ device: AudioHardwareDevice) {
        let audio = (try? device.canBeDefaultOutputDevice) ?? false
        let effects = (try? device.canBeDefaultSoundEffectsDevice) ?? false
        guard audio || effects, let name = try? device.name, let uid = try? device.uid else { return nil }

        var property = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: transport))
        guard AudioObjectGetPropertyData(device.id, &property, 0, nil, &size, &transport) == noErr else {
            return nil
        }
        self.device = device
        self.name = name
        self.uid = uid
        self.transport = transport
        canPlayAudio = audio
        canPlayEffects = effects
    }

    var transportName: String {
        switch transport {
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeBuiltIn: return "Intern"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        default: return "Sonstiger Anschluss"
        }
    }

    func isExcluded(_ names: Set<String>) -> Bool {
        transport == kAudioDeviceTransportTypeDisplayPort ||
        transport == kAudioDeviceTransportTypeHDMI ||
        names.contains(name)
    }
}

private final class AudioGuard {
    private let system = AudioHardwareSystem.shared
    private let excludedNames: Set<String>
    private var lastAudioUID: String?
    private var lastEffectsUID: String?

    init(excludedNames: Set<String>) {
        self.excludedNames = excludedNames
    }

    private func outputs() throws -> [Output] {
        try system.devices.compactMap(Output.init).sorted { $0.name < $1.name }
    }

    func list() throws {
        for output in try outputs() {
            let state = output.isExcluded(excludedNames) ? "wird umgangen" : "verwendbar"
            print("\(output.name) [\(output.transportName)] – \(state)")
        }
    }

    private func redirect(current: AudioHardwareDevice?, lastUID: inout String?, candidates: [Output],
                          label: String, apply: (AudioHardwareDevice) throws -> Void) throws {
        guard let current, let output = Output(current) else { return }
        guard output.isExcluded(excludedNames) else {
            lastUID = output.uid
            return
        }

        let allowed = candidates.filter { !$0.isExcluded(excludedNames) }
        guard let replacement = allowed.first(where: { $0.uid == lastUID }) ??
            allowed.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }) ??
            allowed.first else {
            fputs("\(label): Kein alternativer Ausgang verfügbar.\n", stderr)
            return
        }
        try apply(replacement.device)
        lastUID = replacement.uid
        print("\(label): \(output.name) → \(replacement.name)")
    }

    func update() throws {
        let available = try outputs()
        try redirect(current: system.defaultOutputDevice, lastUID: &lastAudioUID,
                     candidates: available.filter(\.canPlayAudio), label: "Standardton",
                     apply: system.setDefaultOutputDevice)
        try redirect(current: system.defaultSoundEffectsDevice, lastUID: &lastEffectsUID,
                     candidates: available.filter(\.canPlayEffects), label: "Systemtöne",
                     apply: system.setDefaultSoundEffectsDevice)
    }

    func watch() throws {
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice,
                         kAudioHardwarePropertyDevices] {
            var property = address(selector)
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, .main) {
                [self] _, _ in
                do {
                    try update()
                } catch {
                    fputs("Audio konnte nicht umgeleitet werden: \(error.localizedDescription)\n", stderr)
                }
            }
            guard status == noErr else {
                throw GuardError(message: "Core-Audio-Überwachung konnte nicht starten (OSStatus \(status)).")
            }
        }
        try update()
        print("Überwachung aktiv. Zum Beenden Ctrl+C drücken.")
        fflush(stdout)
        dispatchMain()
    }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.contains("--help") || args.contains("-h") {
        print(usage)
        exit(EXIT_SUCCESS)
    }
    let options = try Options(args)
    let guardProcess = AudioGuard(excludedNames: options.excludedNames)
    if options.list {
        try guardProcess.list()
    } else if options.once {
        try guardProcess.update()
    } else {
        try guardProcess.watch()
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
