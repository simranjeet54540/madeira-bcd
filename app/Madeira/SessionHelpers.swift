//
//  SessionHelpers.swift
//
//  1) GameSwitcher / SwitchGameOverlay : game chalte waqt "dusra game" -- app band hoti hai
//     aur ek notification aata hai, us par tap karne se app naye sire se khulti hai.
//     (Ek app-launch mein ek hi Windows session chal sakta hai, isliye restart hi raasta hai.)
//
//  2) AudioInterruptionGuard : call / Siri / alarm ke baad game ki awaaz wapas laata hai.
//

import SwiftUI
import UIKit
import AVFoundation
import UserNotifications

// ---------------------------------------------------------------------
// MARK: 1) Dusra game chalana
// ---------------------------------------------------------------------

enum GameSwitcher {
    private static let pendingKey = "madeira.pendingSwitchExe"

    /// App start par ek baar: notification ki permission maangta hai, aur agar pichhli baar
    /// koi game queue kiya tha to usko shortcut ki tarah chalane ke liye de deta hai.
    static func prepare() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if let path = UserDefaults.standard.string(forKey: pendingKey) {
            UserDefaults.standard.removeObject(forKey: pendingKey)
            ShortcutRouter.shared.pendingExe = path
        }
    }

    /// App band karta hai aur 1 second baad notification bhejta hai.
    /// `windowsPath` do to agli baar wahi game chalane ki koshish hogi, na do to bas library khulegi.
    static func restart(thenPlay windowsPath: String? = nil, gameTitle: String? = nil) {
        if let p = windowsPath {
            UserDefaults.standard.set(p, forKey: pendingKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingKey)
        }
        let content = UNMutableNotificationContent()
        content.title = "Madeira"
        if windowsPath == nil {
            content.body = "Dusra game chunne ke liye yahan tap karo."
        } else {
            content.body = "\(gameTitle ?? "Game") chalane ke liye yahan tap karo."
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "madeira.switch", content: content, trigger: trigger)
        LogStore.shared.log("[switch] restart requested (pending=\(windowsPath ?? "none"))")
        UNUserNotificationCenter.current().add(request) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
        }
    }
}

/// Chhota, halka sa button game ke upar (sirf tab dikhta hai jab game chal raha ho).
struct SwitchGameOverlay: View {
    @State private var confirm = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if wine_process_is_running() != 0 {
                Button {
                    confirm = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .padding(.leading, 10)
                .padding(.top, 6)
                .opacity(0.5)
                .confirmationDialog("Dusra game chalana hai?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Game band karo aur library kholo", role: .destructive) {
                        GameSwitcher.restart()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("App band hogi aur ek notification aayega. Usko tap karke app dobara kholo. Game ka unsaved progress chala jayega.")
                }
            }
        }
    }
}

// ---------------------------------------------------------------------
// MARK: 2) Call ke baad awaaz wapas
// ---------------------------------------------------------------------

final class AudioInterruptionGuard {
    static let shared = AudioInterruptionGuard()

    private var started = false
    private var needsResume = false

    /// App start par ek baar bulao (RootView.onAppear).
    func start() {
        guard !started else { return }
        started = true
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

    /// Call ke turant baad setActive kabhi fail hota hai, isliye 0.7 s ke gap se 5 baar tak try.
    private func resume(attempt: Int) {
        guard wine_process_is_running() != 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)

            // STAGE 2 (sirf tab jab neeche wali C function jod do, README dekho):
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
