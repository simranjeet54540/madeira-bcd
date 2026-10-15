import Foundation

struct GameOptimizer {
    
    // 1. iPhone ki Total RAM detect karna
    static var isHighRAMDevice: Bool {
        let ramInMB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
        return ramInMB >= 7000 // 8GB RAM models (7655MB) ke liye true
    }
    
    // 2. Game aur Phone ke hisaab se settings banana
    static func getOptimalConfig(for exeName: String) -> String {
        let poolSize = isHighRAMDevice ? 560 : 448
        let vramSize = isHighRAMDevice ? 2048 : 1024
        
        var settings: [String] = [
            "inproc-sync=0",
            "fastsync=1",
            "pool=\(poolSize)",
            "MADEIRA_D3D9=emulated",
            "MADEIRA_DINPUT_PAD=1",
            "MADEIRA_PAD_KBM=0"
        ]
        
        let exe = exeName.lowercased()
        
        if exe.contains("bfbc2") {
            // Battlefield 2 freeze aur hot-lock rokne ke liye
            settings.append("MADEIRA_SRV_NOSEM=1")
            settings.append("MADEIRA_APC_REQUEUE=0")
        } else if exe.contains("farcry3") {
            // Far Cry 3 DX11 crash rokne ke liye
            settings.append("MADEIRA_D3D11=0")
            settings.append("swap-mb=2048")
            settings.append("vram-mb=\(vramSize)")
        }
        
        return settings.joined(separator: "\n") + "\n"
    }
}
