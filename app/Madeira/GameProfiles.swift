//
//  GameProfiles.swift
//  Madeira
//
//  madeira-bcd: a game's own settings file -- Winlator's per-shortcut
//  overrides, in this app's terms.
//
//  Same syntax as Documents/madeira.cfg (key = value, env.NAME = value, # for
//  comments). The launch exports its path as MADEIRA_CFG_GAME; the native
//  reader (build/madeira_cfg.h) lets a key set here win over madeira.cfg, and
//  WineProcessBridge exports its env.* lines after madeira.cfg's. So any
//  runtime switch -- a D3D12 experiment, a FEX option, a DXMT setting -- can be
//  set for one game without touching the others, and without a new build.
//
//  The game settings sheet edits the common ones with pickers; the raw file is
//  one tap further for everything else.
//

import Foundation
import SwiftUI
import UIKit
import AVFoundation


struct GameProfile {
    let windowsPath: String

    static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("GameConfigs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var url: URL? {
        GameProfile.directory?.appendingPathComponent(
            String(format: "%016llx.cfg", CoverStore.stableHash(windowsPath.lowercased())))
    }

    /// The whole file ("" when there is none). Setting "" deletes it.
    var text: String {
        get {
            guard let u = url, let t = try? String(contentsOf: u, encoding: .utf8) else { return "" }
            return t
        }
        nonmutating set {
            guard let u = url else { return }
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? FileManager.default.removeItem(at: u)
            } else {
                try? (newValue.hasSuffix("\n") ? newValue : newValue + "\n").write(to: u, atomically: true, encoding: .utf8)
            }
        }
    }

    /// key -> value, the last line winning, as the native reader does.
    var values: [String: String] { GameProfile.parse(text) }

    static func values(ofFile url: URL) -> [String: String] {
        parse((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let k = line[..<eq].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty { out[k] = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces) }
        }
        return out
    }

    /// True when the file sets anything at all.
    var hasSettings: Bool { !values.isEmpty }

    func get(_ key: String) -> String? {
        guard let v = values[key], !v.isEmpty else { return nil }
        return v
    }

    /// Sets or (nil / "") removes `key`, keeping every other line as written.
    func set(_ key: String, _ value: String?) {
        var lines = text.components(separatedBy: "\n")
        while lines.last == "" { lines.removeLast() }
        if lines.isEmpty { lines = ["# Madeira settings for \(windowsPath)", "# madeira.cfg syntax; keys here win over madeira.cfg."] }
        lines.removeAll { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { return false }
            return line[..<eq].trimmingCharacters(in: .whitespaces) == key
        }
        if let value, !value.isEmpty { lines.append("\(key) = \(value)") }
        let kept = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        text = kept.isEmpty ? "" : lines.joined(separator: "\n")
    }

    // MARK: The curated switches

    /// MetalFX spatial upscaling factor: the D3D12 runtime reads
    /// metalfx-upscale itself; a D3D11 game gets DXMT's own MetalFX swapchain
    /// with the same factor (LaunchRequest.apply).
    static let metalFXChoices: [(String, String)] = [("", "Off"), ("1.5", "1.5×"), ("2", "2×")]

    /// Frame limit the session starts with (the Session panel still changes it).
    static let fpsChoices: [(String, String)] = [("", "Default (60)"), ("30", "30 FPS"), ("40", "40 FPS"),
                                                  ("60", "60 FPS"), ("max", "Display max"), ("raw", "Unlimited")]

    /// The D3D12 runtime's cap on low-detail tessellation (dxil-tess-max-factor).
    static let tessChoices: [(String, String)] = [("", "Default (3)"), ("2", "Low (2)"), ("4", "Medium (4)"),
                                                   ("8", "High (8)"), ("0", "Full (no cap)")]

    /// ml1120/ml1121 async-submit: the D3D12 runtime encodes the game's command
    /// lists on its own worker thread instead of inside the game's
    /// ExecuteCommandLists (10-16 ms of every Ghost of Tsushima frame in the
    /// 2026-09-28 14:04 log).
    static let submitChoices: [(String, String)] = [("", "Game's thread (default)"), ("1", "Worker thread")]

    /// fence-chain: F1 = every GPU pass waits for the one before (accurate,
    /// default); F6 = only where the game's barriers say so (the GPU overlaps
    /// work; the overlay's F pill switches the same thing live).
    static let gpuSyncChoices: [(String, String)] = [("", "Every pass (F1, default)"), ("6", "Barriers only (F6)")]
    /// env.MADEIRA_FRAMEGEN: MetalFX frame interpolation in the present path
    /// (tools/patch-dxmt-framegen.py), D3D11 and D3D12 alike.
    static let frameGenChoices: [(String, String)] = [("", "Off"), ("1", "MetalFX 2× (experimental)")]
    /// ml2100 env.MADEIRA_PAD_MODE (GamepadInput.configuredPadMode): player 1 as an
    /// XInput pad (default) or as a HID controller -- a DualSense when it is one.
    static let padModeChoices: [(String, String)] = [("", "XInput (default)"), ("hid", "DirectInput / HID")]

    var frameLimit: FrameLimit? {
        switch get("fps-limit") {
        case "30": return .locked30
        case "40": return .locked40
        case "60": return .locked60
        case "max": return .display
        case "raw": return .unlimited
        default: return nil
        }
    }

    var metalFXFactor: Double? {
        guard let s = get("metalfx-upscale"), let f = Double(s), f >= 1.1 else { return nil }
        return min(f, 3)
    }
}

/// The raw file, for any switch the sheet has no picker for.
struct GameConfigEditor: View {
    let profile: GameProfile
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.caption.monospaced())
                    .frame(minHeight: 260)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } footer: {
                Text("One key = value per line, as in madeira.cfg; env.NAME = value exports an environment "
                     + "variable (FEX_*, DXMT_*, MADEIRA_*). A key set here wins over madeira.cfg for this "
                     + "game only. Examples: dxil-tess-max-factor = 0, metalfx-upscale = 2, "
                     + "env.FEX_MULTIBLOCK = 1.")
            }
        }
        .navigationTitle("Game config")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    profile.text = text
                    onSave()
                    dismiss()
                }
            }
        }
        .onAppear { text = profile.text }
    }
}

// =====================================================================
// Madeira Tools v3  (Game Doctor + Phone Settings, ALAG ALAG)
//
//   GameLogs      : Madeira ki logs padhne ke common tools (dono screens use karte hain)
//   GameDoctor    : game mein aayi PROBLEM ki jaanch + us problem ka seedha fix
//   PhoneTuner    : is game ke liye PHONE ke hisaab se recommended settings
//
// Game Doctor sirf problem dekhta hai. Phone Settings sirf settings sujhata hai.
// Naya error handle karna ho to neeche rules list mein ek DoctorRule add karo.
// =====================================================================

// ---------------------------------------------------------------------
// MARK: Shared: Madeira ki logs
// ---------------------------------------------------------------------

enum GameLogs {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // Session logs: Documents/logs/<exe>-<yyyy-MM-dd_HH-mm-ss>.txt
    static var logsDirectory: URL {
        documentsDirectory.appendingPathComponent("logs")
    }

    /// "C:\Games\Crysis64.exe" -> "Crysis64.exe"
    static func exeName(_ windowsPath: String) -> String {
        windowsPath.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? windowsPath
    }

    static func has(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    /// Is game ki logs, nayi pehle. strict = true: sirf isi game ki (na mile to khaali).
    /// strict = false: na mile to sab logs, aur aakhir mein Madeira ki main log.
    static func logs(forGame gameExe: String?, limit: Int = 20, strict: Bool = false) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func date(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        var list = files.filter { $0.pathExtension == "txt" }
        if let exe = gameExe?.lowercased(), !exe.isEmpty {
            let stem = (exe as NSString).deletingPathExtension
            let matched = list.filter {
                let name = $0.lastPathComponent.lowercased()
                return name.contains(exe) || (!stem.isEmpty && name.contains(stem))
            }
            if !matched.isEmpty { list = matched } else if strict { return [] }
        }
        let sorted = Array(list.sorted { date($0) > date($1) }.prefix(limit))
        if strict { return sorted }
        let mains = ["madeira-log.txt", "madeira-log.prev.txt"]
            .map { documentsDirectory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return sorted + mains
    }

    /// Madeira ki main log, agar usme is game ka naam aata hai.
    static func mainLog(mentioning exe: String) -> URL? {
        for name in ["madeira-log.txt", "madeira-log.prev.txt"] {
            let u = documentsDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: u.path) else { continue }
            if sample(u).range(of: exe, options: .caseInsensitive) != nil { return u }
        }
        return nil
    }

    static func displayName(_ url: URL) -> String {
        switch url.lastPathComponent {
        case "madeira-log.txt":      return "Madeira main log (abhi ka session)"
        case "madeira-log.prev.txt": return "Madeira main log (pichhla session)"
        default:                     return url.lastPathComponent
        }
    }

    static func dateText(_ url: URL) -> String {
        guard let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    // Badi log (10MB+) poori nahi padhte: shuru ka 2MB + aakhir ka 2MB.
    static func sample(_ url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        let chunk = 2_000_000
        var data = (try? h.read(upToCount: chunk)) ?? Data()
        if let size = try? h.seekToEnd(), size > UInt64(chunk) {
            let start = max(UInt64(chunk), size - UInt64(chunk))
            try? h.seek(toOffset: start)
            data.append((try? h.read(upToCount: chunk)) ?? Data())
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Log ki aakhri kuch lines (crash se theek pehle kya hua).
    static func tail(_ url: URL, lines n: Int = 12) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd() else { return [] }
        let start: UInt64 = size > 20_000 ? size - 20_000 : 0
        try? h.seek(toOffset: start)
        let data = (try? h.readToEnd()) ?? Data()
        let all = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
        return all.suffix(n).map { String($0.prefix(220)) }
    }

    /// Log mein "[footprint] ... (peak N)" lines ka sabse bada N (MB).
    static func memoryPeakMB(in text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: "\\[footprint\\][^\\n]*?\\(peak (\\d+)\\)") else { return nil }
        let ns = text as NSString
        var best: Int? = nil
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges > 1, let v = Int(ns.substring(with: m.range(at: 1))) else { return }
            if best == nil || v > best! { best = v }
        }
        return best
    }

    /// Log mein "clamping reported physical memory X MB -> Y MB" ka Y (iOS ka asli memory limit).
    static func memoryLimitMB(in text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: "clamping reported physical memory \\d+ MB -> (\\d+) MB") else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return Int(ns.substring(with: m.range(at: 1)))
    }
}

// ---------------------------------------------------------------------
// MARK: Game Doctor: fix actions (sirf problem se jude fix)
// ---------------------------------------------------------------------

enum DoctorAction: String, Identifiable {
    case avxOn, vcrtOn, nvidiaOn, safeSyncOn, gpuSyncSafe, dx11Args, storageMemory, fps30

    var id: String { rawValue }

    /// true = andaza (try karke dekho), false = log ka seedha ilaaj.
    var isGuess: Bool {
        switch self {
        case .avxOn, .nvidiaOn, .fps30: return false
        default: return true
        }
    }

    var title: String {
        let base: String
        switch self {
        case .avxOn:         base = "AVX / AVX2 on karo"
        case .vcrtOn:        base = "Wine's C++ runtime on karo"
        case .nvidiaOn:      base = "NVIDIA GPU report karo"
        case .safeSyncOn:    base = "Safe thread sync on karo"
        case .gpuSyncSafe:   base = "GPU sync safe (default) karo"
        case .dx11Args:      base = "DX11 mode (-dx11) lagao"
        case .storageMemory: base = "Storage-backed memory on karo"
        case .fps30:         base = "FPS limit 30 karo"
        }
        return base + (isGuess ? " (try)" : "")
    }

    var icon: String {
        switch self {
        case .avxOn:         return "cpu"
        case .vcrtOn:        return "shippingbox"
        case .nvidiaOn:      return "display"
        case .safeSyncOn:    return "lock.shield"
        case .gpuSyncSafe:   return "arrow.triangle.2.circlepath"
        case .dx11Args:      return "terminal"
        case .storageMemory: return "internaldrive"
        case .fps30:         return "speedometer"
        }
    }

    /// Fix lagata hai; wapas ek line batata hai ki kya hua.
    func apply(windowsPath: String) -> String {
        let profile = GameProfile(windowsPath: windowsPath)
        switch self {
        case .avxOn:
            if LibraryPrefs.avx(windowsPath) { return "AVX pehle se on hai." }
            LibraryPrefs.setAVX(true, for: windowsPath)
            return "AVX / AVX2 on kar diya. Game dobara chalao."
        case .vcrtOn:
            if LibraryPrefs.wineVCRT(windowsPath) { return "Wine's C++ runtime pehle se on hai." }
            LibraryPrefs.setWineVCRT(true, for: windowsPath)
            return "Wine's C++ runtime on kar diya. Game dobara chalao."
        case .nvidiaOn:
            if LibraryPrefs.nvidia(windowsPath) { return "NVIDIA GPU report pehle se on hai." }
            LibraryPrefs.setNvidia(true, for: windowsPath)
            return "NVIDIA GPU report on kar diya. Game dobara chalao."
        case .safeSyncOn:
            if LibraryPrefs.safeSync(windowsPath) { return "Safe thread sync pehle se on hai." }
            LibraryPrefs.setSafeSync(true, for: windowsPath)
            return "Safe thread sync on kar diya (thoda slow, par crash kam). Game dobara chalao."
        case .gpuSyncSafe:
            profile.set("fence-chain", nil)
            profile.set("async-submit", nil)
            return "GPU sync aur command encoding default (safe) par wapas. Game dobara chalao."
        case .dx11Args:
            var parts = GameArguments.get(windowsPath).split(separator: " ").map(String.init)
            parts.removeAll { $0.lowercased().hasPrefix("-dx") }
            parts.append("-dx11")
            GameArguments.set(parts.joined(separator: " "), for: windowsPath)
            return "Arguments mein -dx11 laga diya. Game dobara chalao."
        case .storageMemory:
            if ExperimentalSettings.storageBackedMemory { return "Storage-backed memory pehle se on hai." }
            ExperimentalSettings.storageBackedMemory = true
            return "Storage-backed memory on kar di (sab games ke liye). Agle game start par lagegi."
        case .fps30:
            profile.set("fps-limit", "30")
            return "FPS limit 30 par lock kar diya. Game dobara chalao."
        }
    }
}

// ---------------------------------------------------------------------
// MARK: Game Doctor: rules
// ---------------------------------------------------------------------

enum DoctorSeverity { case problem, info }

struct DoctorRule: Identifiable {
    let id: String
    let severity: DoctorSeverity
    let patterns: [String]      // inme se koi ek bhi log mein mile (chhote/bade akshar ek jaise) to rule match
    let detailRegex: String?    // optional: log se naam/detail nikalne ke liye (group 1 dikhega)
    let problem: String         // kya hua
    let reason: String          // kyun hua
    let fix: String             // kya karo
    let actions: [DoctorAction] // button jo fix seedha lagate hain
    var isFallback = false      // jab koi khaas crash rule na mile tabhi dikhta hai
}

struct DoctorFinding: Identifiable {
    let id = UUID()
    let rule: DoctorRule
    let detail: String?
}

enum GameDoctor {

    // --- Crash ---
    static let crashRules: [DoctorRule] = [
        DoctorRule(
            id: "unrecognized-insn", severity: .problem,
            patterns: ["UNRECOGNIZED insn"],
            detailRegex: "UNRECOGNIZED insn=([0-9a-fA-F]+)",
            problem: "Emulator ko ek CPU instruction samajh nahi aayi, isliye game crash hua.",
            reason: "x18 handler mein yeh instruction type missing hai (Madeira ka bug).",
            fix: "Latest mod build use karo. Phir bhi aaye to yeh log developer ko bhejo.",
            actions: []
        ),
        DoctorRule(
            id: "crash-c0000005", severity: .problem,
            patterns: ["Unhandled exception code c0000005"],
            detailRegex: nil,
            problem: "Game crash ho gaya (access violation).",
            reason: "Game ya emulator ne galat memory address padha. Aksar thread sync ya GPU sync ki wajah se.",
            fix: "Neeche ke fix ek ek karke try karo, har baar game chalakar dekho.",
            actions: [.safeSyncOn, .gpuSyncSafe, .dx11Args]
        ),
        DoctorRule(
            id: "crash-illegal-insn", severity: .problem,
            patterns: ["Unhandled exception code c000001d"],
            detailRegex: nil,
            problem: "Game ne aisi CPU instruction chalayi jo emulator support nahi karta.",
            reason: "Game ya uski DLL AVX jaise naye CPU features maangti hai.",
            fix: "AVX / AVX2 on karo.",
            actions: [.avxOn]
        ),
        DoctorRule(
            id: "crash-stack-overflow", severity: .problem,
            patterns: ["Unhandled exception code c00000fd"],
            detailRegex: nil,
            problem: "Game ka stack bhar gaya (stack overflow).",
            reason: "Game ke andar infinite loop ya bahut gehri recursion.",
            fix: "Game ke mods/patches hata do aur dobara try karo.",
            actions: []
        ),
        DoctorRule(
            id: "crash-heap", severity: .problem,
            patterns: ["Unhandled exception code c0000374"],
            detailRegex: nil,
            problem: "Game ki memory kharab (heap corruption) ho gayi.",
            reason: "Ek thread ne wo memory free kar di jo doosra thread abhi use kar raha tha.",
            fix: "Safe thread sync on karo. Phir bhi ho to game files verify/reinstall karo, mod DLL hatao.",
            actions: [.safeSyncOn]
        ),
        DoctorRule(
            id: "crash-other", severity: .problem,
            patterns: ["Unhandled exception code"],
            detailRegex: "Unhandled exception code ([0-9a-fA-F]{8})",
            problem: "Game ek anjaan error se crash hua.",
            reason: "Is error code ka koi khaas ilaaj abhi Doctor ke paas nahi hai.",
            fix: "Detail mein error code dekho aur log share karke bhejo, naya rule jod diya jayega.",
            actions: [],
            isFallback: true
        )
    ]

    // --- DLL / JIT / session / graphics / audio ---
    static let setupRules: [DoctorRule] = [
        DoctorRule(
            id: "dll-missing", severity: .problem,
            patterns: ["which is needed by", "status c0000135"],
            detailRegex: "Library ([^ ]+) \\(which is needed by",
            problem: "Ek zaroori DLL file nahi mili.",
            reason: "Game ko jo DLL chahiye woh Wine prefix mein installed nahi hai.",
            fix: "Detail mein DLL ka naam dekho. Agar woh C++ runtime ki hai (msvcp / vcruntime) to Wine's C++ runtime try karo. Warna woh DLL game folder mein daalo.",
            actions: [.vcrtOn]
        ),
        DoctorRule(
            id: "dll-bad-image", severity: .problem,
            patterns: ["status c000007b", "Unhandled exception code c000007b"],
            detailRegex: nil,
            problem: "Ek DLL ya exe ka version (32-bit/64-bit) match nahi karta.",
            reason: "Game 32-bit hai par 64-bit DLL mili (ya ulta).",
            fix: "Sahi bit-version wali DLL game folder mein daalo.",
            actions: []
        ),
        DoctorRule(
            id: "dll-init-failed", severity: .problem,
            patterns: ["status c0000142"],
            detailRegex: nil,
            problem: "Ek DLL shuru nahi ho payi.",
            reason: "DLL ko koi aur cheez chahiye jo available nahi hai.",
            fix: "Wine's C++ runtime on karo.",
            actions: [.vcrtOn]
        ),
        DoctorRule(
            id: "jit-not-enabled", severity: .problem,
            patterns: ["JIT not enabled", "JIT pool allocation FAILED"],
            detailRegex: nil,
            problem: "JIT chalu nahi tha, isliye game shuru nahi hua.",
            reason: "Windows games ko JIT chahiye. JIT ke bina Wine start hi nahi hota.",
            fix: "Library mein Play dabao (Madeira khud JIT maangta hai) ya Enable JIT dabao. StikDebug se JIT chalu hone do, phir game shuru karo.",
            actions: []
        ),
        DoctorRule(
            id: "jit-no-debugger", severity: .problem,
            patterns: ["CS_DEBUGGED is set but no debugger"],
            detailRegex: nil,
            problem: "JIT ka flag laga hai par debugger juda nahi hai.",
            reason: "StikDebug ki apni list se JIT chalu karne par debugger chhod kar chala jata hai.",
            fix: "Madeira ke andar se Enable JIT dabao, phir game shuru karo.",
            actions: []
        ),
        DoctorRule(
            id: "session-once", severity: .problem,
            patterns: ["A Wine session already ran in this launch", "[session-once] launch held"],
            detailRegex: nil,
            problem: "Is app-launch mein pehle hi ek game chal chuka hai.",
            reason: "Ek app-launch mein ek hi Windows session chal sakta hai (JIT pool sirf ek baar banta hai).",
            fix: "Madeira ko app switcher se band karke dobara kholo, phir doosra game chalao.",
            actions: []
        ),
        DoctorRule(
            id: "no-graphics-card", severity: .problem,
            patterns: ["no installed graphics card", "failed to get GPU driver info", "no graphics card"],
            detailRegex: nil,
            problem: "Game ko graphics card nahi mila.",
            reason: "Game ek jaane-pehchane vendor (NVIDIA) ka driver dhoondhta hai.",
            fix: "NVIDIA GPU report on karo.",
            actions: [.nvidiaOn]
        ),
        DoctorRule(
            id: "d3dx-invalid-data", severity: .problem,
            patterns: ["D3DXERR_INVALIDDATA"],
            detailRegex: nil,
            problem: "Shader load nahi ho paya.",
            reason: "Game ka D3D9 shader data is build mein sahi se nahi chal raha.",
            fix: "DirectX runtime (d3dx9 DLLs) install karo ya D3D9 related settings badlo.",
            actions: []
        ),
        DoctorRule(
            id: "audio-silent-format", severity: .problem,
            patterns: ["UNMIXABLE format", "mixer full -- client stays silent"],
            detailRegex: nil,
            problem: "Is game ki awaaz nahi aayegi.",
            reason: "Game ka audio format support nahi hai, ya Madeira ka audio mixer bhar gaya.",
            fix: "Game ki audio settings mein 48000 Hz aur stereo chuno. Phir bhi chup rahe to log developer ko bhejo.",
            actions: []
        ),
        DoctorRule(
            id: "audio-resume-failed", severity: .info,
            patterns: ["[audio-guard] setActive failed"],
            detailRegex: nil,
            problem: "Call ke baad awaaz wapas laane mein ek baar dikkat aayi.",
            reason: "Call ke turant baad iOS audio session dene mein der karta hai.",
            fix: "Madeira apne aap 5 baar koshish karta hai. Awaaz na aaye to game ko ek baar background mein bhejkar wapas laao.",
            actions: []
        )
    ]

    // --- Memory / phone ki haalat ---
    static let stateRules: [DoctorRule] = [
        DoctorRule(
            id: "jit-pool-shrunk", severity: .info,
            patterns: ["no hole fits a"],
            detailRegex: nil,
            problem: "Game ka JIT memory pool chhota banaya gaya (aksar normal hai).",
            reason: "Itna bada ek-saath memory block nahi mila, isliye pool thoda kam banaya gaya.",
            fix: "Game theek chal raha ho to kuch mat karo. Crash ya memory ki dikkat aaye tabhi baaki apps band karo.",
            actions: []
        ),
        DoctorRule(
            id: "thermal-serious", severity: .problem,
            patterns: ["thermal=serious", "thermal=critical", "[thermal] now serious", "[thermal] now critical"],
            detailRegex: nil,
            problem: "Phone bahut garam tha.",
            reason: "Garmi ki wajah se CPU slow ho jata hai, game lag aur crash karta hai.",
            fix: "Cover hatao, charging band karo, phone thanda hone do. FPS 30 par lock karna madad karta hai.",
            actions: [.fps30]
        ),
        DoctorRule(
            id: "low-power-mode", severity: .problem,
            patterns: ["low-power=1"],
            detailRegex: nil,
            problem: "Low Power Mode on tha.",
            reason: "iOS is mode mein performance kaat deta hai.",
            fix: "iPhone Settings > Battery mein Low Power Mode band karo. (App yeh khud band nahi kar sakti.)",
            actions: []
        )
    ]

    static let rules: [DoctorRule] = crashRules + setupRules + stateRules

    /// Log ke footprint se bani rule: memory limit ke kareeb.
    static let memoryRule = DoctorRule(
        id: "memory-near-limit", severity: .problem,
        patterns: [],
        detailRegex: nil,
        problem: "Game memory limit ke bahut kareeb chala gaya.",
        reason: "iOS memory limit paar hone par app ko bina bataye band kar deta hai.",
        fix: "Storage-backed memory on karo. Phone Settings mein Battery ya Balanced mode lagao (kam MetalFX aur tessellation).",
        actions: [.storageMemory]
    )

    /// Purane naam ke liye (kuch jagah GameDoctor.exeName use karti hain).
    static func exeName(_ windowsPath: String) -> String { GameLogs.exeName(windowsPath) }

    static func diagnose(logURL: URL) -> [DoctorFinding] {
        let text = GameLogs.sample(logURL)
        var out: [DoctorFinding] = []
        for rule in rules where !rule.isFallback && GameLogs.has(text, rule.patterns) {
            out.append(DoctorFinding(rule: rule, detail: extract(rule.detailRegex, from: text)))
        }
        // Anjaan crash tabhi dikhao jab koi khaas crash/DLL rule na mila ho.
        let specific: Set<String> = ["unrecognized-insn", "crash-c0000005", "crash-illegal-insn", "crash-stack-overflow",
                                     "crash-heap", "dll-missing", "dll-bad-image", "dll-init-failed"]
        if !out.contains(where: { specific.contains($0.rule.id) }),
           let fb = rules.first(where: { $0.isFallback }),
           GameLogs.has(text, fb.patterns) {
            out.append(DoctorFinding(rule: fb, detail: extract(fb.detailRegex, from: text)))
        }
        // Memory: peak, limit ke 85% se upar gaya?
        if let peak = GameLogs.memoryPeakMB(in: text),
           let limit = GameLogs.memoryLimitMB(in: text),
           limit > 0, Double(peak) >= Double(limit) * 0.85 {
            out.append(DoctorFinding(rule: memoryRule, detail: "Peak \(peak) MB / limit \(limit) MB"))
        }
        return out.filter { $0.rule.severity == .problem } + out.filter { $0.rule.severity == .info }
    }

    private static func extract(_ pattern: String?, from text: String) -> String? {
        guard let pattern, let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Game chalane se PEHLE phone ki haalat (log ki zaroorat nahi).
    static func preflight() -> [String] {
        var warnings: [String] = []
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled {
            warnings.append("Low Power Mode on hai. Band karo, warna game slow chalega.")
        }
        switch info.thermalState {
        case .serious, .critical:
            warnings.append("Phone abhi bahut garam hai. 5-10 minute thanda hone do, cover hatao.")
        case .fair:
            warnings.append("Phone thoda garam hai. Lamba khelna ho to FPS limit kam rakho.")
        default: break
        }
        if let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage,
           free < 3_000_000_000 {
            warnings.append("Storage kam hai (3 GB se kam). Kuch jagah khaali karo.")
        }
        return warnings
    }
}

// ---------------------------------------------------------------------
// MARK: Game Doctor screen
// ---------------------------------------------------------------------

struct GameDoctorView: View {
    let windowsPath: String
    let onFixed: (() -> Void)?

    @State private var logs: [URL] = []
    @State private var selected: URL?
    @State private var findings: [DoctorFinding] = []
    @State private var tailLines: [String] = []
    @State private var checked = false
    @State private var warnings: [String] = []
    @State private var results: [String: String] = [:]

    init(windowsPath: String, onFixed: (() -> Void)? = nil) {
        self.windowsPath = windowsPath
        self.onFixed = onFixed
    }

    private var gameExe: String { GameLogs.exeName(windowsPath) }
    private var problems: [DoctorFinding] { findings.filter { $0.rule.severity == .problem } }

    /// Sirf problems ke fix, duplicate hata kar, order wahi.
    private var allActions: [DoctorAction] {
        var seen = Set<String>()
        var out: [DoctorAction] = []
        for f in problems {
            for a in f.rule.actions where !seen.contains(a.id) {
                seen.insert(a.id)
                out.append(a)
            }
        }
        return out
    }

    var body: some View {
        List {
            Section("Game chalane se pehle") {
                if warnings.isEmpty {
                    Label("Phone ki haalat theek hai.", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                }
                ForEach(warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle").foregroundColor(.orange)
                }
            }

            Section {
                if logs.isEmpty {
                    Text("Madeira ki koi log nahi mili. Game ek baar chalao (crash ho to bhi chalega), phir wapas aao.")
                        .foregroundColor(.secondary)
                }
                ForEach(logs, id: \.self) { url in
                    Button { run(url) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GameLogs.displayName(url))
                            Text(GameLogs.dateText(url)).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Madeira ki logs")
            } footer: {
                Text("Sabse nayi log apne aap check ho jaati hai. Doosri log dabao to wo check hogi.")
            }

            if checked {
                Section("Nateeja") {
                    if problems.isEmpty {
                        Label("Koi badi problem nahi mili.", systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                    }
                    if findings.isEmpty {
                        Text("Is log mein koi jaani-pehchani cheez nahi mili. Neeche aakhri log lines dekho ya log share karke bhejo.")
                            .font(.footnote)
                    }
                    ForEach(findings) { f in
                        findingRow(f)
                    }
                    if allActions.count > 1 {
                        Button {
                            for a in allActions { fix(a) }
                        } label: {
                            Label("Saare fix ek saath lagao (\(allActions.count))", systemImage: "checkmark.seal")
                        }
                    }
                }

                if !tailLines.isEmpty {
                    Section {
                        DisclosureGroup("Log ke aakhri lines") {
                            Text(tailLines.joined(separator: "\n"))
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                        if let selected {
                            ShareLink(item: selected) {
                                Label("Log share karo", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Game Doctor")
        .onAppear {
            logs = GameLogs.logs(forGame: gameExe)
            warnings = GameDoctor.preflight()
            if !checked, let newest = logs.first { run(newest) }
        }
    }

    @ViewBuilder private func findingRow(_ f: DoctorFinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: f.rule.severity == .problem ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundColor(f.rule.severity == .problem ? .orange : .blue)
                Text(f.rule.problem).font(.headline)
            }
            if let d = f.detail { Text("Detail: " + d).font(.footnote) }
            Text("Kyun: " + f.rule.reason).font(.subheadline)
            Text("Kya karo: " + f.rule.fix).font(.subheadline).foregroundColor(.green)
            ForEach(f.rule.actions) { a in
                Button { fix(a) } label: {
                    Label(a.title, systemImage: a.icon)
                }
                .buttonStyle(.bordered)
                if let r = results[a.id] {
                    Text(r).font(.footnote).foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func run(_ url: URL) {
        selected = url
        findings = GameDoctor.diagnose(logURL: url)
        tailLines = GameLogs.tail(url)
        checked = true
    }

    private func fix(_ a: DoctorAction) {
        results[a.id] = a.apply(windowsPath: windowsPath)
        onFixed?()
    }
}

// ---------------------------------------------------------------------
// MARK: Phone Settings (recommended settings, phone + game ke hisaab se)
//
// Yeh keys likhta hai (GameProfile.set se, baaki lines ko nahi chhuta):
//   fps-limit            "30" / "40" / "60"
//   metalfx-upscale      "" (off) / "1.5" / "2"
//   dxil-tess-max-factor "" (default) / "4" / "2"
// Aur zarurat par storage-backed memory. Har apply se pehle purani values
// yaad rakhta hai, "Wapas karo" se wapas aa jaati hain.
// ---------------------------------------------------------------------

enum PhoneTier: Int {
    case low = 0, mid = 1, high = 2

    var label: String {
        switch self {
        case .low:  return "Kam (low)"
        case .mid:  return "Medium"
        case .high: return "Zyada (high)"
        }
    }
}

enum PhoneMode: String, CaseIterable, Identifiable {
    case auto, smooth, balanced, quality

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:     return "Auto (recommended)"
        case .smooth:   return "Battery aur thanda"
        case .balanced: return "Balanced"
        case .quality:  return "Best quality"
        }
    }

    var detail: String {
        switch self {
        case .auto:     return "Phone ki RAM, garmi, Low Power aur is game ki pichhli log dekhkar apne aap chunta hai."
        case .smooth:   return "Kam garmi, zyada battery: 30 FPS, MetalFX 2×, Tessellation Low."
        case .balanced: return "40 FPS, MetalFX 1.5×, Tessellation Medium."
        case .quality:  return "60 FPS, MetalFX off, Tessellation default. Phone garam ho sakta hai."
        }
    }
}

struct PhoneProfile {
    let model: String
    let ramMB: Int
    let thermal: ProcessInfo.ThermalState
    let lowPower: Bool
    let freeGB: Double

    private static let names: [String: String] = [
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd gen)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,6": "iPhone SE (3rd gen)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e"
    ]

    var friendlyName: String { PhoneProfile.names[model] ?? model }

    var thermalText: String {
        switch thermal {
        case .nominal:  return "Normal"
        case .fair:     return "Thoda garam"
        case .serious:  return "Bahut garam"
        case .critical: return "Bahut zyada garam"
        @unknown default: return "Pata nahi"
        }
    }

    static var current: PhoneProfile {
        var sys = utsname()
        uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let info = ProcessInfo.processInfo
        var free = 0.0
        if let v = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = v.volumeAvailableCapacityForImportantUsage {
            free = Double(bytes) / 1_000_000_000
        }
        return PhoneProfile(model: model,
                            ramMB: Int(info.physicalMemory / 1_048_576),
                            thermal: info.thermalState,
                            lowPower: info.isLowPowerModeEnabled,
                            freeGB: free)
    }

    // 8GB wale iPhone ~7600 MB dikhate hain, 6GB wale ~5600 MB.
    var baseTier: PhoneTier {
        if ramMB >= 7000 { return .high }
        if ramMB >= 5000 { return .mid }
        return .low
    }
}

enum PhoneTuner {

    // Bhaari games ke naam ka hissa (chhote akshar). Yeh andaza hai, apne tajurbe se badlo.
    static let heavyGameHints: [String] = ["farcry3", "bfbc2", "ghostoftsushima", "rdr2", "reddead",
                                           "witcher3", "cyberpunk", "crysis"]

    /// Jin keys ko tuner badalta hai (undo inhi ko wapas karta hai).
    private static let managedKeys = ["fps-limit", "metalfx-upscale", "dxil-tess-max-factor"]

    struct Plan {
        let tier: PhoneTier
        let fps: String
        let metalFX: String?
        let tess: String?
        let storageMemory: Bool
        let reasons: [String]
        let warning: String?
    }

    /// Is game ki pichhli log se kya seekha.
    struct History {
        var notes: [String] = []
        var heavy = false
        var memoryTight = false
        var usesD3D9 = false
    }

    static func history(forExe gameExe: String) -> History {
        var h = History()
        var url = GameLogs.logs(forGame: gameExe, limit: 1, strict: true).first
        if url == nil { url = GameLogs.mainLog(mentioning: gameExe) }
        guard let url else { return h }
        let text = GameLogs.sample(url)
        if GameLogs.has(text, ["thermal=serious", "thermal=critical", "[thermal] now serious", "[thermal] now critical"]) {
            h.notes.append("pichhli baar phone bahut garam hua tha")
            h.heavy = true
        }
        if let peak = GameLogs.memoryPeakMB(in: text),
           let limit = GameLogs.memoryLimitMB(in: text),
           limit > 0, Double(peak) >= Double(limit) * 0.75 {
            h.notes.append("pichhli baar memory limit ke kareeb gayi (peak \(peak) MB / \(limit) MB)")
            h.heavy = true
            h.memoryTight = true
        }
        if GameLogs.has(text, ["[d3d9-census]", "d9-batching"]) {
            h.usesD3D9 = true
        }
        return h
    }

    static func plan(gameExe: String, mode: PhoneMode = .auto, phone: PhoneProfile = .current) -> Plan {
        var level = phone.baseTier.rawValue
        var reasons = ["Phone: \(phone.friendlyName), RAM \(phone.ramMB) MB"]

        if phone.thermal == .serious || phone.thermal == .critical {
            level -= 1
            reasons.append("phone abhi garam hai")
        }
        if phone.lowPower {
            level -= 1
            reasons.append("Low Power Mode on hai")
        }
        let exe = gameExe.lowercased()
        if heavyGameHints.contains(where: { exe.contains($0) }) {
            level -= 1
            reasons.append("game bhaari hai")
        }
        let h = history(forExe: gameExe)
        if h.heavy {
            level -= 1
            reasons.append(contentsOf: h.notes)
        }

        let autoTier = PhoneTier(rawValue: max(0, min(2, level))) ?? .low
        let tier: PhoneTier
        switch mode {
        case .auto:     tier = autoTier
        case .smooth:   tier = .low
        case .balanced: tier = .mid
        case .quality:  tier = .high
        }
        if mode != .auto { reasons.append("aapne mode chuna: \(mode.label)") }

        var warning: String? = nil
        if mode == .quality && autoTier.rawValue < PhoneTier.high.rawValue {
            warning = "Auto is phone aur game ke liye \(autoTier.label) level sujha raha hai. Best quality se phone garam ho sakta hai."
        }

        let fps: String
        var metalFX: String?
        var tess: String?
        switch tier {
        case .high:
            fps = "60"; metalFX = nil; tess = nil
        case .mid:
            fps = "40"; metalFX = "1.5"; tess = "4"
        case .low:
            fps = "30"; metalFX = "2"; tess = "2"
        }
        if h.usesD3D9 {
            metalFX = nil
            tess = nil
            reasons.append("game D3D9 hai: MetalFX aur Tessellation is par asar nahi karte, isliye nahi lagaye")
        }
        let storage = (tier == .low || h.memoryTight) && phone.freeGB >= 8
        return Plan(tier: tier, fps: fps, metalFX: metalFX, tess: tess,
                    storageMemory: storage, reasons: reasons, warning: warning)
    }

    // MARK: Undo

    private static func undoKey(_ windowsPath: String) -> String {
        "madeira.phoneTune.undo." + windowsPath.lowercased()
    }

    static func hasUndo(_ windowsPath: String) -> Bool {
        UserDefaults.standard.dictionary(forKey: undoKey(windowsPath)) != nil
    }

    /// Pehli baar apply se pehle ki values yaad rakhta hai (dobara apply par purani wali hi rehti hai).
    private static func saveUndo(_ profile: GameProfile) {
        let key = undoKey(profile.windowsPath)
        guard UserDefaults.standard.dictionary(forKey: key) == nil else { return }
        var snap: [String: String] = [:]
        for k in managedKeys { snap[k] = profile.get(k) ?? "" }
        snap["__storage"] = ExperimentalSettings.storageBackedMemory ? "1" : "0"
        UserDefaults.standard.set(snap, forKey: key)
    }

    @discardableResult
    static func undo(profile: GameProfile) -> String {
        let key = undoKey(profile.windowsPath)
        guard let snap = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else {
            return "Wapas karne ke liye kuch nahi hai."
        }
        for k in managedKeys {
            let old = snap[k] ?? ""
            profile.set(k, old.isEmpty ? nil : old)
        }
        if snap["__storage"] == "0" { ExperimentalSettings.storageBackedMemory = false }
        UserDefaults.standard.removeObject(forKey: key)
        LogStore.shared.log("[phone-tune] \(profile.windowsPath): undo")
        return "Pichhli settings wapas laga di."
    }

    // MARK: Apply

    /// Plan ko game ki config file mein likh deta hai. User ko dikhane ka text return karta hai.
    @discardableResult
    static func apply(_ p: Plan, to profile: GameProfile, gameExe: String) -> String {
        saveUndo(profile)
        profile.set("fps-limit", p.fps)
        profile.set("metalfx-upscale", p.metalFX)
        profile.set("dxil-tess-max-factor", p.tess)
        if p.storageMemory && !ExperimentalSettings.storageBackedMemory {
            ExperimentalSettings.storageBackedMemory = true
        }
        let upscale = p.metalFX.map { "\($0)×" } ?? "Off"
        let tess = p.tess ?? "Default"
        LogStore.shared.log("[phone-tune] \(gameExe): tier=\(p.tier.label) fps=\(p.fps) metalfx=\(upscale) tess=\(tess) storage=\(p.storageMemory ? 1 : 0)")
        var text = "Lag gayi: FPS \(p.fps), MetalFX \(upscale), Tessellation \(tess)"
        if p.storageMemory { text += ", storage memory on" }
        text += ". Game band karke dobara chalao."
        return text
    }

    /// Purani call ke liye: Auto mode ka plan seedha lagata hai.
    @discardableResult
    static func apply(to profile: GameProfile, gameExe: String) -> String {
        apply(plan(gameExe: gameExe), to: profile, gameExe: gameExe)
    }
}

// ---------------------------------------------------------------------
// MARK: Phone Settings screen
// ---------------------------------------------------------------------

struct PhoneSettingsView: View {
    let windowsPath: String
    let onChanged: (() -> Void)?

    @State private var mode: PhoneMode = .auto
    @State private var phone = PhoneProfile.current
    @State private var plan: PhoneTuner.Plan? = nil
    @State private var curFPS = ""
    @State private var curMFX = ""
    @State private var curTess = ""
    @State private var canUndo = false
    @State private var applied = ""

    init(windowsPath: String, onChanged: (() -> Void)? = nil) {
        self.windowsPath = windowsPath
        self.onChanged = onChanged
    }

    private var gameExe: String { GameLogs.exeName(windowsPath) }
    private var profile: GameProfile { GameProfile(windowsPath: windowsPath) }

    private func label(_ value: String, _ choices: [(String, String)]) -> String {
        choices.first { $0.0 == value }?.1 ?? value
    }

    var body: some View {
        List {
            Section("Aapka phone") {
                LabeledContent("Model", value: phone.friendlyName)
                LabeledContent("RAM", value: "\(phone.ramMB) MB")
                LabeledContent("Garmi", value: phone.thermalText)
                LabeledContent("Low Power Mode", value: phone.lowPower ? "On (band karo)" : "Off")
                LabeledContent("Khaali storage", value: String(format: "%.0f GB", phone.freeGB))
            }

            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(PhoneMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Mode")
            } footer: {
                Text(mode.detail)
            }

            if let plan {
                Section {
                    compareRow("FPS limit",
                               now: label(curFPS, GameProfile.fpsChoices),
                               rec: label(plan.fps, GameProfile.fpsChoices))
                    compareRow("MetalFX upscaling",
                               now: label(curMFX, GameProfile.metalFXChoices),
                               rec: label(plan.metalFX ?? "", GameProfile.metalFXChoices))
                    compareRow("Tessellation (D3D12)",
                               now: label(curTess, GameProfile.tessChoices),
                               rec: label(plan.tess ?? "", GameProfile.tessChoices))
                    if plan.storageMemory {
                        Label("Storage-backed memory bhi on hogi", systemImage: "internaldrive")
                    }
                    if let w = plan.warning {
                        Label(w, systemImage: "exclamationmark.triangle").foregroundColor(.orange)
                    }
                } header: {
                    Text("\(gameExe) ke liye recommended")
                } footer: {
                    Text("Ye sirf FPS limit, MetalFX aur Tessellation badalta hai (aur zarurat par storage-backed memory). Baaki settings nahi chhuta.")
                }

                Section("Wajah") {
                    ForEach(plan.reasons, id: \.self) { r in
                        Text("• " + r).font(.footnote)
                    }
                }

                Section {
                    Button {
                        applied = PhoneTuner.apply(plan, to: profile, gameExe: gameExe)
                        reload()
                        onChanged?()
                    } label: {
                        Label("Ye settings lagao", systemImage: "wand.and.stars")
                    }
                    if canUndo {
                        Button(role: .destructive) {
                            applied = PhoneTuner.undo(profile: profile)
                            reload()
                            onChanged?()
                        } label: {
                            Label("Wapas karo", systemImage: "arrow.uturn.backward")
                        }
                    }
                    if !applied.isEmpty {
                        Text(applied).font(.footnote).foregroundColor(.green)
                    }
                } footer: {
                    Text("Game mein koi problem aaye (crash, awaaz nahi, black screen) to Game Doctor dekho.")
                }
            }
        }
        .navigationTitle("Phone Settings")
        .onAppear { reload() }
        .onChange(of: mode) { _, _ in reload() }
    }

    private func compareRow(_ title: String, now: String, rec: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Abhi: " + now).font(.caption).foregroundColor(.secondary)
                Text("Recommended: " + rec)
                    .font(.subheadline)
                    .foregroundColor(now == rec ? .green : .accentColor)
            }
        }
    }

    private func reload() {
        phone = PhoneProfile.current
        plan = PhoneTuner.plan(gameExe: gameExe, mode: mode, phone: phone)
        let p = profile
        curFPS = p.get("fps-limit") ?? ""
        curMFX = p.get("metalfx-upscale") ?? ""
        curTess = p.get("dxil-tess-max-factor") ?? ""
        canUndo = PhoneTuner.hasUndo(windowsPath)
    }
}

final class AudioInterruptionGuard {
    static let shared = AudioInterruptionGuard()

    private var started = false
    private var needsResume = false

    func start() {
        guard !started else { return }
        started = true
        LogStore.shared.log("[audio-guard] started")
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            self?.handleInterruption(n)
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.needsResume = true
            self?.resume(attempt: 0)
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.needsResume == true { self?.resume(attempt: 0) }
        }
    }

    private func handleInterruption(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            needsResume = true
            LogStore.shared.log("[audio-guard] interruption began")
        case .ended:
            LogStore.shared.log("[audio-guard] interruption ended")
            resume(attempt: 0)
        @unknown default:
            break
        }
    }

    private func resume(attempt: Int) {
        guard wine_process_is_running() != 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            madeira_audio_resume()
            needsResume = false
            LogStore.shared.log("[audio-guard] session active again (try \(attempt + 1))")
        } catch {
            LogStore.shared.log("[audio-guard] setActive failed: \(error.localizedDescription) (try \(attempt + 1))")
            if attempt < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    self?.resume(attempt: attempt + 1)
                }
            }
        }
    }
}

