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
            await MainActor.run { self.finalizeBiometricResult(.success) }
        case .cancelled:
            await MainActor.run { self.finalizeBiometricResult(.cancelled) }
        case .fallback:
            let passcodeResult = await BiometricAuth.shared.authenticateAllowingDevicePasscode(
                reason: Self.unlockReason,
                fallbackTitle: "Enter Passcode"
            )
            await MainActor.run { self.finalizeBiometricResult(passcodeResult) }
        case .failed(let code):
            if code == .biometryLockout {
                let passcodeResult = await BiometricAuth.shared.authenticateAllowingDevicePasscode(
                    reason: Self.unlockReason,
                    fallbackTitle: "Enter Passcode"
                )
                await MainActor.run { self.finalizeBiometricResult(passcodeResult, lockedOut: true) }
            } else {
                await MainActor.run { self.finalizeBiometricResult(.failed(code)) }
            }
        }
        await MainActor.run {
            self.isAttemptingBiometric = false
            self.biometricTask = nil
        }
    }

    @MainActor
    private func finalizeBiometricResult(_ result: BiometricAuthResult, lockedOut: Bool = false) {
        switch result {
        case .success:
            biometricSatisfied = true
            passphraseError = nil
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
