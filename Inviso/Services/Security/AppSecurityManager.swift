//
//  AppSecurityManager.swift
//  Inviso
//
//  Created by Bence Szilagyi on 9/17/25.
//

import SwiftUI
import Combine
import UIKit
import LocalAuthentication

/// Centralised security coordinator that manages privacy overlay and foreground authentication.
final class AppSecurityManager: ObservableObject {
    @Published var showPrivacyOverlay = false
    @Published private(set) var isLocked = false
    @Published private(set) var requiresPassphraseEntry = false
    @Published private(set) var shouldPromptBiometric = false
    @Published private(set) var isAttemptingBiometric = false
    @Published private(set) var biometricCapability: BiometricCapability = .none
    @Published var passphraseError: String?

    private let settingsStore = AuthenticationSettingsStore.shared
    private let passphraseManager = PassphraseManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var biometricTask: Task<Void, Never>?
    private var biometricSatisfied = false
    private var passphraseSatisfied = false
    private var biometricAutoAttempted = false
    private var externalAuthDepth = 0

    private static let unlockReason = "Unlock to access protected chats"

    init() {
        biometricCapability = BiometricAuth.shared.capability()
        setupNotificationObservers()
        observeSettingsChanges()
        DispatchQueue.main.async { [weak self] in
            self?.evaluateLockIfNeeded()
        }
    }

    deinit {
        biometricTask?.cancel()
        cancellables.removeAll()
    }

    func triggerBiometricIfNeeded() {
        guard shouldPromptBiometric else { return }
        biometricAutoAttempted = true
        attemptBiometricUnlock()
    }

    func submitPassphrase(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            passphraseError = "Passphrase cannot be empty."
            return
        }
        guard passphraseManager.hasPassphrase else {
            passphraseError = "No passphrase configured."
            return
        }
        if passphraseManager.validate(passphrase: trimmed) {
            passphraseSatisfied = true
            passphraseError = nil
            
            print("🔐 Passphrase validated - attempting to unlock storage...")
            // Unlock message storage with the validated passphrase
            do {
                try MessageStorageManager.shared.unlockWithPassphraseSync(trimmed)
                print("🔓 Message storage unlocked - isUnlocked: \(MessageStorageManager.shared.isUnlocked)")
            } catch {
                print("⚠️ Failed to unlock message storage: \(error)")
            }
            
            updateLockState()
        } else {
            passphraseError = "Incorrect passphrase."
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleWillResignActive()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleDidBecomeActive()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleDidEnterBackground()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .securityExternalAuthWillBegin)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.externalAuthDepth += 1
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .securityExternalAuthDidEnd)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.externalAuthDepth = max(0, self.externalAuthDepth - 1)
            }
            .store(in: &cancellables)
    }

    private func observeSettingsChanges() {
        settingsStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleSettingsUpdate()
            }
            .store(in: &cancellables)
    }

    private func handleSettingsUpdate() {
        biometricCapability = BiometricAuth.shared.capability()
        if settingsStore.settings.mode == .disabled {
            unlock()
        } else {
            if UIApplication.shared.applicationState == .active {
                lock()
            }
        }
    }

    private func handleWillResignActive() {
        guard externalAuthDepth == 0 else { return }
        showPrivacyOverlay = true
        if settingsStore.settings.mode != .disabled {
            lock()
        }
    }

    private func handleDidBecomeActive() {
        showPrivacyOverlay = false
        if isAttemptingBiometric {
            return
        }
        evaluateLockIfNeeded()
    }

    private func handleDidEnterBackground() {
        showPrivacyOverlay = true
        if settingsStore.settings.mode != .disabled {
            lock()
        }
    }

    private func evaluateLockIfNeeded() {
        guard settingsStore.settings.mode != .disabled else {
            unlock()
            return
        }
        if biometricSatisfied || passphraseSatisfied {
            unlock()
        } else {
            lock()
        }
    }

    private func lock() {
        cancelBiometricTask()
        if !isLocked {
            isLocked = true
        }
        passphraseError = nil
        biometricSatisfied = false
        passphraseSatisfied = false
        biometricAutoAttempted = false
        updateLockState()
    }

    private func unlock() {
        cancelBiometricTask()
        isLocked = false
        passphraseError = nil
        biometricAutoAttempted = false
        requiresPassphraseEntry = false
        shouldPromptBiometric = false
        isAttemptingBiometric = false
    }

    private func updateLockState() {
        var mode = settingsStore.settings.mode
        let hasStoredPassphrase = passphraseManager.hasPassphrase

        if mode.requiresPassphrase && !hasStoredPassphrase {
            settingsStore.update { settings in
                switch settings.mode {
                case .both:
                    settings.mode = .biometricOnly
                case .passphraseOnly:
                    settings.mode = .disabled
                default:
                    break
                }
            }
            mode = settingsStore.settings.mode
        }

        requiresPassphraseEntry = mode.requiresPassphrase && hasStoredPassphrase && !passphraseSatisfied
        shouldPromptBiometric = mode.requiresBiometrics && !biometricSatisfied


        if shouldPromptBiometric {
            if !biometricAutoAttempted && !isAttemptingBiometric {
                biometricAutoAttempted = true
                attemptBiometricUnlock()
            }
        } else {
            cancelBiometricTask()
            isAttemptingBiometric = false
        }

        if !shouldPromptBiometric && !requiresPassphraseEntry {
            unlock()
        }
    }

    private func attemptBiometricUnlock() {
        guard isLocked, shouldPromptBiometric else { return }
        biometricCapability = BiometricAuth.shared.capability()

        cancelBiometricTask()
        isAttemptingBiometric = true
        biometricTask = Task { [weak self] in
            guard let self else { return }
            await self.runBiometricFlow()
        }
    }

    private func runBiometricFlow() async {
        let primary = await BiometricAuth.shared.authenticateWithBiometrics(reason: Self.unlockReason)
        switch primary {
        case .success:
            await finalizeBiometricResult(.success)
        case .cancelled:
            await finalizeBiometricResult(.cancelled)
        case .fallback:
            let passcodeResult = await BiometricAuth.shared.authenticateAllowingDevicePasscode(
                reason: Self.unlockReason,
                fallbackTitle: "Enter Passcode"
            )
            await finalizeBiometricResult(passcodeResult)
        case .failed(let code):
            if code == .biometryLockout {
                let passcodeResult = await BiometricAuth.shared.authenticateAllowingDevicePasscode(
                    reason: Self.unlockReason,
                    fallbackTitle: "Enter Passcode"
                )
                await finalizeBiometricResult(passcodeResult, lockedOut: true)
            } else {
                await finalizeBiometricResult(.failed(code))
            }
        }
        await MainActor.run {
            self.isAttemptingBiometric = false
            self.biometricTask = nil
        }
    }

    @MainActor
    private func finalizeBiometricResult(_ result: BiometricAuthResult, lockedOut: Bool = false) async {
        switch result {
        case .success:
            biometricSatisfied = true
            passphraseError = nil
            
            print("🔐 Biometric validated - attempting to unlock storage...")
            // Unlock message storage with biometric - MUST complete before unlock
            do {
                try await MessageStorageManager.shared.unlockWithBiometric()
                print("🔓 Message storage unlocked with biometric - isUnlocked: \(MessageStorageManager.shared.isUnlocked)")
            } catch {
                print("⚠️ Failed to unlock message storage with biometric: \(error)")
                // Even if storage unlock fails, allow app unlock (storage just won't work)
            }
        case .fallback:
            break
        case .cancelled:
            break
        case .failed(let code):
            if lockedOut || code == .biometryLockout {
                passphraseError = "Biometrics locked. Use device passcode to retry."
            }
        }
        biometricAutoAttempted = true
        updateLockState()
    }

    private func cancelBiometricTask() {
        biometricTask?.cancel()
        biometricTask = nil
    }
}
