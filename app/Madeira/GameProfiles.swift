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
// GameDoctor.swift
//
// 1) GameDoctor  : log padhkar problem + solution batata hai, aur game chalane se
//                  pehle phone ki haalat check karta hai.
// 2) PhoneTuner  : phone ki RAM / garmi / Low Power dekhkar game ki FPS limit,
//                  MetalFX aur tessellation badalta hai (GameProfile mein likhta hai).
//
// Naya error handle karna ho to neeche `rules` list mein ek DoctorRule add karo.
// =====================================================================

// ---------------------------------------------------------------------
// MARK: Game Doctor
// ---------------------------------------------------------------------

struct DoctorRule: Identifiable {
    let id: String
    let patterns: [String]     // inme se koi ek bhi log mein mile to rule match
    let detailRegex: String?   // optional: log se naam/detail nikalne ke liye (group 1 dikhega)
    let problem: String        // kya hua
    let reason: String         // kyun hua
    let fix: String            // kaise chalega
}

struct DoctorFinding: Identifiable {
    let id = UUID()
    let rule: DoctorRule
    let detail: String?
}

enum GameDoctor {

    static let rules: [DoctorRule] = [

        // --- Crash ---
        DoctorRule(
            id: "unrecognized-insn",
            patterns: ["UNRECOGNIZED insn"],
            detailRegex: "UNRECOGNIZED insn=([0-9a-fA-F]+)",
            problem: "Emulator ko ek CPU instruction samajh nahi aayi, isliye game crash hua.",
            reason: "x18 handler mein yeh instruction type missing hai (Madeira ka bug).",
            fix: "Latest mod build use karo. Phir bhi aaye to yeh log developer ko bhejo."
        ),
        DoctorRule(
            id: "crash-c0000005",
            patterns: ["Unhandled exception code c0000005"],
            detailRegex: nil,
            problem: "Game crash ho gaya (access violation).",
            reason: "Game ya emulator ne galat memory address padha.",
            fix: "Dobara chalao. Baar-baar ho to FPS limit kam karo aur log share karo."
        ),
        DoctorRule(
            id: "crash-illegal-insn",
            patterns: ["Unhandled exception code c000001d"],
            detailRegex: nil,
            problem: "Game ne aisi CPU instruction chalayi jo emulator support nahi karta.",
            reason: "Game ya uski DLL naye CPU features (jaise AVX) maangti hai.",
            fix: "Game settings mein AVX switch badal ke dekho, ya DX9 mode try karo."
        ),
        DoctorRule(
            id: "crash-stack-overflow",
            patterns: ["Unhandled exception code c00000fd"],
            detailRegex: nil,
            problem: "Game ka stack bhar gaya (stack overflow).",
            reason: "Game ke andar infinite loop ya bahut gehri recursion.",
            fix: "Game ke mods/patches hata do aur dobara try karo."
        ),
        DoctorRule(
            id: "crash-heap",
            patterns: ["Unhandled exception code c0000374"],
            detailRegex: nil,
            problem: "Game ki memory kharab (heap corruption) ho gayi.",
            reason: "Game ya koi DLL ne memory galat jagah likh di.",
            fix: "Game files verify/reinstall karo. Overlay ya mod DLL hatao."
        ),

        // --- DLL / files ---
        DoctorRule(
            id: "dll-missing",
            patterns: ["which is needed by", "status c0000135"],
            detailRegex: "Library ([^ ]+) \\(which is needed by",
            problem: "Ek zaroori DLL file nahi mili.",
            reason: "Game ko jo DLL chahiye woh Wine prefix mein installed nahi hai.",
            fix: "Naam dekho (neeche likha hai). Visual C++ runtime (Wine's C++ runtime switch) ya DirectX runtime install karo, ya woh DLL game folder mein daalo."
        ),
        DoctorRule(
            id: "dll-bad-image",
            patterns: ["status c000007b", "Unhandled exception code c000007b"],
            detailRegex: nil,
            problem: "Ek DLL ya exe ka version (32-bit/64-bit) match nahi karta.",
            reason: "Game 32-bit hai par 64-bit DLL mili (ya ulta).",
            fix: "Sahi bit-version wali DLL daalo."
        ),
        DoctorRule(
            id: "dll-init-failed",
            patterns: ["status c0000142"],
            detailRegex: nil,
            problem: "Ek DLL shuru nahi ho payi.",
            reason: "DLL ko koi aur cheez chahiye jo available nahi hai.",
            fix: "Wine's C++ runtime switch on karo aur DirectX runtime install karo."
        ),

        // --- Graphics ---
        DoctorRule(
            id: "d3dx-invalid-data",
            patterns: ["D3DXERR_INVALIDDATA"],
            detailRegex: nil,
            problem: "Shader load nahi ho paya.",
            reason: "Game ka D3D9 shader data is build mein sahi se nahi chal raha.",
            fix: "DirectX runtime (d3dx9 DLLs) install karo ya D3D9 related settings badlo."
        ),

        // --- Memory ---
        DoctorRule(
            id: "jit-pool-shrunk",
            patterns: ["no hole fits a"],
            detailRegex: nil,
            problem: "JIT memory pool chhota karna pada.",
            reason: "Itna bada memory block mila nahi.",
            fix: "Baaki apps band karo, phone restart karo, MetalFX/FPS settings kam karo."
        ),

        // --- Phone state ---
        DoctorRule(
            id: "thermal-serious",
            patterns: ["thermal=serious", "thermal=critical", "[thermal] now serious", "[thermal] now critical"],
            detailRegex: nil,
            problem: "Phone bahut garam tha.",
            reason: "Garmi ki wajah se CPU slow ho jata hai, game lag aur crash karta hai.",
            fix: "Cover hatao, charging band karo. 'Phone ke hisaab se settings' dabao, FPS 30-40 par rakho."
        ),
        DoctorRule(
            id: "low-power-mode",
            patterns: ["low-power=1"],
            detailRegex: nil,
            problem: "Low Power Mode on tha.",
            reason: "iOS is mode mein performance kaat deta hai.",
            fix: "iPhone Settings mein Low Power Mode band karo."
        )
    ]

    // Logs: Documents/logs/<exe>-<yyyy-MM-dd_HH-mm-ss>.txt (LogStore.startSessionLog)
    static var logsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("logs")
    }

    /// "C:\Games\Crysis64.exe" -> "Crysis64.exe"
    static func exeName(_ windowsPath: String) -> String {
        windowsPath.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? windowsPath
    }

    /// Is game ki logs, nayi pehle. gameExe khaali ho to sab logs.
    static func logs(forGame gameExe: String?, limit: Int = 20) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func date(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        var list = files.filter { $0.pathExtension == "txt" }
        if let exe = gameExe?.lowercased(), !exe.isEmpty {
            let matched = list.filter { $0.lastPathComponent.lowercased().contains(exe) }
            if !matched.isEmpty { list = matched }
        }
        return Array(list.sorted { date($0) > date($1) }.prefix(limit))
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

    static func diagnose(logURL: URL) -> [DoctorFinding] {
        let text = sample(logURL)
        var out: [DoctorFinding] = []
        for rule in rules where rule.patterns.contains(where: { text.contains($0) }) {
            out.append(DoctorFinding(rule: rule, detail: extract(rule.detailRegex, from: text)))
        }
        return out
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

struct GameDoctorView: View {
    let gameExe: String?

    @State private var logs: [URL] = []
    @State private var selected: URL?
    @State private var findings: [DoctorFinding] = []
    @State private var checked = false
    @State private var warnings: [String] = []

    init(gameExe: String? = nil) { self.gameExe = gameExe }

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

            Section("Pichhli log check karo") {
                if logs.isEmpty {
                    Text("Is game ki koi log nahi mili.").foregroundColor(.secondary)
                }
                ForEach(logs, id: \.self) { url in
                    Button(url.lastPathComponent) { run(url) }
                }
            }

            if checked {
                Section("Nateeja") {
                    if findings.isEmpty {
                        Text("Koi jaani-pehchani problem nahi mili. Log share karke bhejo.")
                    }
                    ForEach(findings) { f in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(f.rule.problem).font(.headline)
                            if let d = f.detail { Text("Detail: " + d).font(.footnote) }
                            Text("Kyun: " + f.rule.reason)
                            Text("Kaise chalega: " + f.rule.fix).foregroundColor(.green)
                        }
                        .padding(.vertical, 4)
                    }
                    if let selected {
                        ShareLink(item: selected) {
                            Label("Log share karo", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("Game Doctor")
        .onAppear {
            logs = GameDoctor.logs(forGame: gameExe)
            warnings = GameDoctor.preflight()
        }
    }

    private func run(_ url: URL) {
        selected = url
        findings = GameDoctor.diagnose(logURL: url)
        checked = true
    }
}

// ---------------------------------------------------------------------
// MARK: PhoneTuner (phone ke hisaab se settings)
//
// Sirf teen keys likhta hai (GameProfile.set se, baaki lines ko nahi chhuta):
//   fps-limit            "30" / "40" / "60"
//   metalfx-upscale      "" (off) / "1.5" / "2"
//   dxil-tess-max-factor "" (default) / "4" / "2"
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

struct PhoneProfile {
    let model: String
    let ramMB: Int
    let thermal: ProcessInfo.ThermalState
    let lowPower: Bool

    static var current: PhoneProfile {
        var sys = utsname()
        uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let info = ProcessInfo.processInfo
        return PhoneProfile(model: model,
                            ramMB: Int(info.physicalMemory / 1_048_576),
                            thermal: info.thermalState,
                            lowPower: info.isLowPowerModeEnabled)
    }

    // 8GB wale iPhone ~7600 MB dikhate hain, 6GB wale ~5600 MB.
    var baseTier: PhoneTier {
        if ramMB >= 7000 { return .high }
        if ramMB >= 5000 { return .mid }
        return .low
    }
}

enum PhoneTuner {

    // Bhaari games ke naam ka hissa (chhote akshar). Yeh meri andaza wali list hai, apne tajurbe se badlo.
    static let heavyGameHints: [String] = ["farcry3", "bfbc2"]

    struct Plan {
        let tier: PhoneTier
        let fps: String
        let metalFX: String?
        let tess: String?
        let reasons: [String]
    }

    static func plan(gameExe: String, phone: PhoneProfile = .current) -> Plan {
        var level = phone.baseTier.rawValue
        var reasons = ["RAM: \(phone.ramMB) MB"]

        if phone.thermal == .serious || phone.thermal == .critical {
            level -= 1
            reasons.append("phone garam hai")
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

        let tier = PhoneTier(rawValue: max(0, min(2, level))) ?? .low
        switch tier {
        case .high: return Plan(tier: tier, fps: "60", metalFX: nil,   tess: nil, reasons: reasons)
        case .mid:  return Plan(tier: tier, fps: "40", metalFX: "1.5", tess: "4", reasons: reasons)
        case .low:  return Plan(tier: tier, fps: "30", metalFX: "2",   tess: "2", reasons: reasons)
        }
    }

    /// Settings turant game ki config file mein likh deta hai. Wapas user ko dikhane ka text return karta hai.
    @discardableResult
    static func apply(to profile: GameProfile, gameExe: String) -> String {
        let p = plan(gameExe: gameExe)
        profile.set("fps-limit", p.fps)
        profile.set("metalfx-upscale", p.metalFX)
        profile.set("dxil-tess-max-factor", p.tess)

        let upscale = p.metalFX.map { "\($0)×" } ?? "Off"
        let tess = p.tess ?? "Default"
        LogStore.shared.log("[phone-tune] \(gameExe): tier=\(p.tier.label) fps=\(p.fps) metalfx=\(upscale) tess=\(tess)")
        return "Level: \(p.tier.label)\nFPS limit: \(p.fps)\nMetalFX: \(upscale)\nTessellation cap: \(tess)\n(" +
               p.reasons.joined(separator: ", ") + ")"
    }
}
