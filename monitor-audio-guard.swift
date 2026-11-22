#!/usr/bin/swift
import CoreAudio
import Foundation

private let usage = """
Usage: monitor-audio-guard [--list | --outputs | --once | --set-default]
                           [--preferred UID] [--exclude "Device Name"]

Keeps the default audio output and system sounds off HDMI and DisplayPort.
--list         Show detected outputs and whether they are allowed.
--outputs      List eligible outputs as UID and name, separated by a tab.
--once         Check once and exit. With no mode flag, watch until Ctrl+C.
--preferred    Prefer this output UID when redirecting away from a monitor.
--set-default  Set the preferred output immediately and exit.
--exclude      Avoid another output by exact name. May be repeated.
"""

private struct GuardError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct Options {
    var list = false
    var once = false
    var outputChoices = false
    var setDefault = false
    var preferredUID: String?
    var excludedNames: Set<String> = []

    init(_ args: [String]) throws {
        var arguments = args.makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--list": list = true
            case "--once": once = true
            case "--outputs": outputChoices = true
            case "--set-default": setDefault = true
            case "--preferred":
                guard let uid = arguments.next(), !uid.isEmpty, !uid.hasPrefix("--") else {
                    throw GuardError(message: "--preferred requires an output UID.")
                }
                preferredUID = uid
            case "--exclude":
                guard let name = arguments.next(), !name.isEmpty, !name.hasPrefix("--") else {
                    throw GuardError(message: "--exclude requires a device name.")
                }
                excludedNames.insert(name)
            default:
                throw GuardError(message: "Unknown option: \(argument)\n\(usage)")
            }
        }
        if [list, once, outputChoices, setDefault].filter({ $0 }).count > 1 {
            throw GuardError(message: "Choose one run mode.\n\(usage)")
        }
        if setDefault && preferredUID == nil {
            throw GuardError(message: "--set-default requires --preferred UID.")
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
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        default: return "Other connection"
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
    private let preferredUID: String?
    private var lastAudioUID: String?
    private var lastEffectsUID: String?

    init(excludedNames: Set<String>, preferredUID: String?) {
        self.excludedNames = excludedNames
        self.preferredUID = preferredUID
    }

    private func outputs() throws -> [Output] {
        try system.devices.compactMap(Output.init).sorted { $0.name < $1.name }
    }

    func list() throws {
        for output in try outputs() {
            let state = output.isExcluded(excludedNames) ? "avoided" : "allowed"
            print("\(output.name) [\(output.transportName)] – \(state)")
        }
    }

    func listOutputChoices() throws {
        for output in try outputs() where output.canPlayAudio && !output.isExcluded(excludedNames) {
            let name = output.name.components(separatedBy: .whitespacesAndNewlines.union(.controlCharacters))
                .filter { !$0.isEmpty }.joined(separator: " ")
            print("\(output.uid)\t\(name)")
        }
    }

    func setPreferredOutput() throws {
        guard let output = try outputs().first(where: {
            $0.uid == preferredUID && $0.canPlayAudio && !$0.isExcluded(excludedNames)
        }) else {
            throw GuardError(message: "The selected output is unavailable. Reconnect it and try again.")
        }
        if try system.defaultOutputDevice?.id != output.device.id {
            try system.setDefaultOutputDevice(output.device)
        }
        if output.canPlayEffects, try system.defaultSoundEffectsDevice?.id != output.device.id {
            try system.setDefaultSoundEffectsDevice(output.device)
        }
        print("Default output: \(output.name)")
    }

    private func redirect(current: AudioHardwareDevice?, lastUID: inout String?, candidates: [Output],
                          label: String, apply: (AudioHardwareDevice) throws -> Void) throws {
        guard let current, let output = Output(current) else { return }
        guard output.isExcluded(excludedNames) else {
            lastUID = output.uid
            return
        }

        let allowed = candidates.filter { !$0.isExcluded(excludedNames) }
        guard let replacement = allowed.first(where: { $0.uid == preferredUID }) ??
            allowed.first(where: { $0.uid == lastUID }) ??
            allowed.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }) ??
            allowed.first else {
            fputs("\(label): No alternative output available.\n", stderr)
            return
        }
        try apply(replacement.device)
        lastUID = replacement.uid
        print("\(label): \(output.name) → \(replacement.name)")
    }

    func update() throws {
        let available = try outputs()
        try redirect(current: system.defaultOutputDevice, lastUID: &lastAudioUID,
                     candidates: available.filter(\.canPlayAudio), label: "Default audio",
                     apply: system.setDefaultOutputDevice)
        try redirect(current: system.defaultSoundEffectsDevice, lastUID: &lastEffectsUID,
                     candidates: available.filter(\.canPlayEffects), label: "System sounds",
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
                    fputs("Could not redirect audio: \(error.localizedDescription)\n", stderr)
                }
            }
            guard status == noErr else {
                throw GuardError(message: "Could not start Core Audio monitoring (OSStatus \(status)).")
            }
        }
        try update()
        print("Monitoring audio outputs. Press Ctrl+C to stop.")
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
    let guardProcess = AudioGuard(excludedNames: options.excludedNames, preferredUID: options.preferredUID)
    if options.list {
        try guardProcess.list()
    } else if options.outputChoices {
        try guardProcess.listOutputChoices()
    } else if options.setDefault {
        try guardProcess.setPreferredOutput()
    } else if options.once {
        try guardProcess.update()
    } else {
        try guardProcess.watch()
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
