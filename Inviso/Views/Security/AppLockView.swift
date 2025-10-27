//
//  AppLockView.swift
//  Inviso
//
//  App lock screen with biometric and passcode authentication
//
//  Created by GitHub Copilot on 10/27/25.
//

import SwiftUI

struct AppLockView: View {
    @ObservedObject var securityManager: AppSecurityManager
    @State private var passcode = ""
    @State private var showPasscodeEntry = false
    @FocusState private var isPasscodeFocused: Bool
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // App Logo/Icon
                VStack(spacing: 16) {
                    Image(systemName: "lock")
                        .font(.system(size: 80))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    Text("Inviso")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Authentication UI
                VStack(spacing: 24) {
                    if showPasscodeEntry {
                        // Passcode Entry
                        passcodeEntrySection
                    } else {
                        // Biometric prompt
                        if securityManager.shouldPromptBiometric {
                            biometricPromptSection
                        }
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
        .onAppear {
            handleInitialAuthentication()
        }
        .onChange(of: securityManager.requiresPassphraseEntry) { oldValue, newValue in
            // When biometric fails and passphrase is now required, show the entry
            if newValue && !oldValue && !showPasscodeEntry {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPasscodeEntry = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPasscodeFocused = true
                }
            }
        }
        .onChange(of: securityManager.isAttemptingBiometric) { oldValue, newValue in
            // Hide passcode entry while biometric is in progress
            if newValue && showPasscodeEntry {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPasscodeEntry = false
                    passcode = ""
                }
            }
        }
    }
    
    // MARK: - Biometric Prompt Section
    
    private var biometricPromptSection: some View {
        VStack(spacing: 20) {
            // Biometric Icon
            Image(systemName: securityManager.biometricCapability == .faceID ? "faceid" : "touchid")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.8))
            
            Text("Unlock with \(securityManager.biometricCapability.localizedName)")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            // Tap to authenticate
            Button {
                securityManager.triggerBiometricIfNeeded()
            } label: {
                Text("Tap to Authenticate")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .cornerRadius(12)
            }
            .padding(.top, 8)
            
            // Fallback to passcode
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPasscodeEntry = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPasscodeFocused = true
                }
            } label: {
                Text("Enter Passcode Instead")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Passcode Entry Section
    
    private var passcodeEntrySection: some View {
        VStack(spacing: 20) {
            Text("Enter Passcode")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            // Passcode Field
            SecureField("Passcode", text: $passcode)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isPasscodeFocused)
                .font(.system(size: 16))
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .onSubmit {
                    submitPasscode()
                }
            
            // Error message
            if let error = securityManager.passphraseError {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            
            // Submit button
            Button {
                submitPasscode()
            } label: {
                Text("Unlock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(passcode.isEmpty ? Color.white.opacity(0.3) : Color.white)
                    .cornerRadius(12)
            }
            .disabled(passcode.isEmpty)
            
            // Try Face ID again (only if biometric is enabled in settings AND device has capability)
            if securityManager.isBiometricEnabled && securityManager.biometricCapability != .none {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPasscodeEntry = false
                        passcode = ""
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        securityManager.retryBiometric()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: securityManager.biometricCapability == .faceID ? "faceid" : "touchid")
                        Text("Try \(securityManager.biometricCapability.localizedName) Again")
                    }
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleInitialAuthentication() {
        // Determine authentication method and auto-trigger if needed
        if securityManager.shouldPromptBiometric {
            // Biometric is available - DON'T show passcode entry yet
            showPasscodeEntry = false
            
            // Auto-trigger biometric after a short delay
            if !securityManager.isAttemptingBiometric {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    securityManager.triggerBiometricIfNeeded()
                }
            }
        } else if securityManager.requiresPassphraseEntry {
            // Only passcode available - show entry immediately
            showPasscodeEntry = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isPasscodeFocused = true
            }
        }
    }
    
    private func submitPasscode() {
        securityManager.submitPassphrase(passcode)
        // Don't clear passcode immediately - let the manager handle success/failure
        // Only clear on next attempt after error
        if securityManager.passphraseError == nil {
            passcode = ""
        }
    }
}

#Preview {
    AppLockView(securityManager: AppSecurityManager())
}
