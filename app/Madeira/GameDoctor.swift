// =====================================================================
// GameDoctor.swift  (v2)
//
// 1) GameDoctor  : Madeira ki log padhta hai, problem pehchanta hai aur
//                  fix ka BUTTON deta hai -- dabao to setting seedha lag jaati hai.
// 2) PhoneTuner  : phone ki RAM / garmi / Low Power + is game ki pichhli log
//                  dekhkar FPS, MetalFX, tessellation (aur zarurat par storage
//                  memory) badalta hai. "Wapas karo" se purani settings wapas.
//
// Naya error handle karna ho to neeche `rules` list mein ek DoctorRule add karo.
// =====================================================================

import Foundation
import SwiftUI
import UIKit

// ---------------------------------------------------------------------
// MARK: Fix actions (button dabane par yeh chalte hain)
// ---------------------------------------------------------------------

enum DoctorAction: String, Identifiable {
  
    case avxOn, vcrtOn, nvidiaOn, safeSyncOn, gpuSyncSafe, dx11Args, storageMemory, phoneTune

    var id: String { rawValue }

    /// true = andaza (try karke dekho), false = log ka seedha ilaaj.
    var isGuess: Bool {
        switch self {
        case .avxOn, .nvidiaOn, .phoneTune: return false
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
        case .phoneTune:     base = "Phone ke hisaab se settings lagao"
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
        case .phoneTune:     return "wand.and.stars"
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
        case .phoneTune:
            return PhoneTuner.apply(to: profile, gameExe: GameDoctor.exeName(windowsPath))
        }
    }
}

// ---------------------------------------------------------------------
// MARK: Game Doctor
// ---------------------------------------------------------------------

struct DoctorRule: Identifiable {
    let id: String
    let patterns: [String]     // inme se koi ek bhi log mein mile (chhote/bade akshar ek jaise) to rule match
    let detailRegex: String?   // optional: log se naam/detail nikalne ke liye (group 1 dikhega)
    let problem: String        // kya hua
    let reason: String         // kyun hua
    let fix: String            // kaise chalega (samjhane ke liye)
    let actions: [DoctorAction] // button jo fix seedha lagate hain
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
            fix: "Latest mod build use karo. Phir bhi aaye to yeh log developer ko bhejo.",
            actions: []
        ),
        DoctorRule(
            id: "crash-c0000005",
            patterns: ["Unhandled exception code c0000005"],
            detailRegex: nil,
            problem: "Game crash ho gaya (access violation).",
            reason: "Game ya emulator ne galat memory address padha. Aksar thread sync ya GPU sync ki wajah se.",
            fix: "Neeche ke fix ek ek karke try karo, har baar game chalakar dekho.",
            actions: [.safeSyncOn, .gpuSyncSafe, .dx11Args]
        ),
        DoctorRule(
            id: "crash-illegal-insn",
            patterns: ["Unhandled exception code c000001d"],
            detailRegex: nil,
            problem: "Game ne aisi CPU instruction chalayi jo emulator support nahi karta.",
            reason: "Game ya uski DLL AVX jaise naye CPU features maangti hai.",
            fix: "AVX / AVX2 on karo.",
            actions: [.avxOn]
        ),
        DoctorRule(
            id: "crash-stack-overflow",
            patterns: ["Unhandled exception code c00000fd"],
            detailRegex: nil,
            problem: "Game ka stack bhar gaya (stack overflow).",
            reason: "Game ke andar infinite loop ya bahut gehri recursion.",
            fix: "Game ke mods/patches hata do aur dobara try karo.",
            actions: []
        ),
        DoctorRule(
            id: "crash-heap",
            patterns: ["Unhandled exception code c0000374"],
            detailRegex: nil,
            problem: "Game ki memory kharab (heap corruption) ho gayi.",
            reason: "Ek thread ne wo memory free kar di jo doosra thread abhi use kar raha tha.",
            fix: "Safe thread sync on karo. Phir bhi ho to game files verify/reinstall karo, mod DLL hatao.",
            actions: [.safeSyncOn]
        ),

        // --- DLL / files ---
        DoctorRule(
            id: "dll-missing",
            patterns: ["which is needed by", "status c0000135"],
            detailRegex: "Library ([^ ]+) \\(which is needed by",
            problem: "Ek zaroori DLL file nahi mili.",
            reason: "Game ko jo DLL chahiye woh Wine prefix mein installed nahi hai.",
            fix: "Detail mein DLL ka naam dekho. Agar woh C++ runtime ki hai (msvcp / vcruntime) to Wine's C++ runtime try karo. Warna woh DLL game folder mein daalo.",
            actions: [.vcrtOn]
        ),
        DoctorRule(
            id: "dll-bad-image",
            patterns: ["status c000007b", "Unhandled exception code c000007b"],
            detailRegex: nil,
            problem: "Ek DLL ya exe ka version (32-bit/64-bit) match nahi karta.",
            reason: "Game 32-bit hai par 64-bit DLL mili (ya ulta).",
            fix: "Sahi bit-version wali DLL game folder mein daalo.",
            actions: []
        ),
        DoctorRule(
            id: "dll-init-failed",
            patterns: ["status c0000142"],
            detailRegex: nil,
            problem: "Ek DLL shuru nahi ho payi.",
            reason: "DLL ko koi aur cheez chahiye jo available nahi hai.",
            fix: "Wine's C++ runtime on karo.",
            actions: [.vcrtOn]
        ),

        // --- Graphics ---
        DoctorRule(
            id: "no-graphics-card",
            patterns: ["no installed graphics card", "failed to get GPU driver info", "no graphics card"],
            detailRegex: nil,
            problem: "Game ko graphics card nahi mila.",
            reason: "Game ek jaane-pehchane vendor (NVIDIA) ka driver dhoondhta hai.",
            fix: "NVIDIA GPU report on karo.",
            actions: [.nvidiaOn]
        ),
        DoctorRule(
            id: "d3dx-invalid-data",
            patterns: ["D3DXERR_INVALIDDATA"],
            detailRegex: nil,
            problem: "Shader load nahi ho paya.",
            reason: "Game ka D3D9 shader data is build mein sahi se nahi chal raha.",
            fix: "DirectX runtime (d3dx9 DLLs) install karo ya D3D9 related settings badlo.",
            actions: []
        ),

        // --- Memory ---
        DoctorRule(
            id: "jit-pool-shrunk",
            patterns: ["no hole fits a"],
            detailRegex: nil,
            problem: "JIT memory pool chhota karna pada.",
            reason: "Itna bada memory block mila nahi.",
            fix: "Baaki apps band karo. Storage-backed memory on karo aur phone ke hisaab se settings lagao.",
            actions: [.storageMemory, .phoneTune]
        ),

        // --- Phone state ---
        DoctorRule(
            id: "thermal-serious",
            patterns: ["thermal=serious", "thermal=critical", "[thermal] now serious", "[thermal] now critical"],
            detailRegex: nil,
            problem: "Phone bahut garam tha.",
            reason: "Garmi ki wajah se CPU slow ho jata hai, game lag aur crash karta hai.",
            fix: "Cover hatao, charging band karo. Phone ke hisaab se settings lagao (FPS 30-40).",
            actions: [.phoneTune]
        ),
        DoctorRule(
            id: "low-power-mode",
            patterns: ["low-power=1"],
            detailRegex: nil,
            problem: "Low Power Mode on tha.",
            reason: "iOS is mode mein performance kaat deta hai.",
            fix: "iPhone Settings > Battery mein Low Power Mode band karo. (App yeh khud band nahi kar sakti.)",
            actions: []
        )
    ]

    // Logs: Documents/logs/<exe>-<yyyy-MM-dd_HH-mm-ss>.txt (LogStore.startSessionLog)
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

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

    /// Is game ki logs, nayi pehle. Aakhir mein Madeira ki main log (agar file ho).
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
        let sorted = Array(list.sorted { date($0) > date($1) }.prefix(limit))
        let mains = ["madeira-log.txt", "madeira-log.prev.txt"]
            .map { documentsDirectory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return sorted + mains
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

    static func diagnose(logURL: URL) -> [DoctorFinding] {
        let text = sample(logURL)
        var out: [DoctorFinding] = []
        for rule in rules where has(text, rule.patterns) {
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

    /// Pichhli baar is game ke saath kya hua (PhoneTuner isse seekhta hai).
    static func history(forExe gameExe: String) -> [String] {
        guard let url = logs(forGame: gameExe, limit: 1).first else { return [] }
        let text = sample(url)
        var out: [String] = []
        if has(text, ["thermal=serious", "thermal=critical", "[thermal] now serious", "[thermal] now critical"]) {
            out.append("pichhli baar phone garam hua tha")
        }
        if has(text, ["no hole fits a"]) {
            out.append("pichhli baar memory kam padi thi")
        }
        return out
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
    @State private var canUndo = false
    @State private var undoNote = ""

    init(windowsPath: String, onFixed: (() -> Void)? = nil) {
        self.windowsPath = windowsPath
        self.onFixed = onFixed
    }

    private var gameExe: String { GameDoctor.exeName(windowsPath) }

    /// Saare findings ke fix, duplicate hata kar, order wahi.
    private var allActions: [DoctorAction] {
        var seen = Set<String>()
        var out: [DoctorAction] = []
        for f in findings {
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
                            Text(GameDoctor.displayName(url))
                            Text(GameDoctor.dateText(url)).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Madeira ki logs")
            } footer: {
                Text("Sabse nayi game log apne aap check ho jaati hai. Doosri log dabao to wo check hogi.")
            }

            if checked {
                Section("Nateeja") {
                    if findings.isEmpty {
                        Text("Koi jaani-pehchani problem nahi mili. Neeche aakhri log lines dekho ya log share karke bhejo.")
                    }
                    ForEach(findings) { f in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(f.rule.problem).font(.headline)
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

            if canUndo {
                Section {
                    Button(role: .destructive) {
                        undoNote = PhoneTuner.undo(profile: GameProfile(windowsPath: windowsPath))
                        canUndo = PhoneTuner.hasUndo(windowsPath)
                        onFixed?()
                    } label: {
                        Label("Phone tune wapas karo", systemImage: "arrow.uturn.backward")
                    }
                    if !undoNote.isEmpty { Text(undoNote).font(.footnote) }
                } footer: {
                    Text("FPS, MetalFX, tessellation aur storage memory ko tune se pehle wali value par le jaata hai.")
                }
            }
        }
        .navigationTitle("Game Doctor")
        .onAppear {
            logs = GameDoctor.logs(forGame: gameExe)
            warnings = GameDoctor.preflight()
            canUndo = PhoneTuner.hasUndo(windowsPath)
            if !checked, let newest = logs.first { run(newest) }
        }
    }

    private func run(_ url: URL) {
        selected = url
        findings = GameDoctor.diagnose(logURL: url)
        tailLines = GameDoctor.tail(url)
        checked = true
    }

    private func fix(_ a: DoctorAction) {
        results[a.id] = a.apply(windowsPath: windowsPath)
        canUndo = PhoneTuner.hasUndo(windowsPath)
        onFixed?()
    }
}

// ---------------------------------------------------------------------
// MARK: PhoneTuner (phone ke hisaab se settings)
//
// Yeh keys likhta hai (GameProfile.set se, baaki lines ko nahi chhuta):
//   fps-limit            "30" / "40" / "60"
//   metalfx-upscale      "" (off) / "1.5" / "2"
//   dxil-tess-max-factor "" (default) / "4" / "2"
// Aur sirf low level par (aur 8 GB+ storage khaali ho to) storage-backed memory.
// Har apply se pehle purani values yaad rakhta hai -> undo.
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
    let freeGB: Double

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
        // Is game ki pichhli log se seekho.
        let past = GameDoctor.history(forExe: gameExe)
        if !past.isEmpty {
            level -= 1
            reasons.append(contentsOf: past)
        }

        let tier = PhoneTier(rawValue: max(0, min(2, level))) ?? .low
        let storage = (tier == .low) && phone.freeGB >= 8
        switch tier {
        case .high: return Plan(tier: tier, fps: "60", metalFX: nil,   tess: nil, storageMemory: storage, reasons: reasons)
        case .mid:  return Plan(tier: tier, fps: "40", metalFX: "1.5", tess: "4", storageMemory: storage, reasons: reasons)
        case .low:  return Plan(tier: tier, fps: "30", metalFX: "2",   tess: "2", storageMemory: storage, reasons: reasons)
        }
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

    /// Settings turant game ki config file mein likh deta hai. User ko dikhane ka text return karta hai.
    @discardableResult
    static func apply(to profile: GameProfile, gameExe: String) -> String {
        let p = plan(gameExe: gameExe)
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

        var text = "Level: \(p.tier.label)\nFPS limit: \(p.fps)\nMetalFX: \(upscale)\nTessellation cap: \(tess)"
        if p.storageMemory { text += "\nStorage-backed memory: on" }
        text += "\n\nWajah: " + p.reasons.joined(separator: ", ")
        text += "\n\nGame band karke dobara chalao. Galat lage to Game Doctor mein 'Phone tune wapas karo' dabao."
        return text
    }
}
