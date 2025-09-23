import SwiftUI
import UIKit
import Combine

// Reusable top toolbar showing Settings and signaling status (dot + text in the center)
struct SignalingToolbar: ViewModifier {
    @EnvironmentObject private var chat: ChatManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var isExpanded = false
    @State private var showJoinPopup = false
    @State private var joinCode: String = ""
    @FocusState private var joinFieldFocused: Bool
    @State private var caretBlinkOn: Bool = true
    // Join -> Name transition state
    @State private var showNameStep = false
    @State private var newRoomTempName: String = ""
    // Deep link naming state
    @State private var showDeepLinkNameStep = false
    @FocusState private var nameFieldFocused: Bool
    // Create flow states
    @State private var showCreatePopup = false
    @State private var roomName: String = ""
    @State private var durationMinutes: Int = 5
    @FocusState private var createNameFocused: Bool
    @State private var showCreateResult = false
    @State private var createdCode: String = ""
    @State private var navigateToChatAfterCreate = false
    // QR Scan for join code
    @State private var showJoinScanner = false
    // QR sheet for newly created room
    @State private var showCreatedQRCode = false

    func body(content: Content) -> some View {
        ZStack {
            content
            if let code = chat.pendingDeepLinkCode {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                VStack(spacing: 16) {
                    if !showDeepLinkNameStep {
                        Text("Join via Link")
                            .font(.headline)
                        Text("Code: \(code)")
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        Text("You opened a link containing a join code. Confirm to proceed.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        HStack(spacing: 24) {
                            Button("Cancel") {
                                withAnimation(.spring()) { chat.cancelPendingDeepLinkJoin() }
                            }
                            Button {
                                // Custom deep link join with naming step
                                confirmDeepLinkJoinWithNaming()
                            } label: {
                                Label("Join", systemImage: "arrow.right.circle.fill")
                                    .font(.body.weight(.semibold))
                            }
                            .buttonStyle(.glass)
                        }
                    } else {
                        Text("Name This Room")
                            .font(.headline)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Room name", text: $newRoomTempName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .focused($nameFieldFocused)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.15))
                                )
                        }
                        .transition(.opacity.combined(with: .scale))
                        HStack(spacing: 20) {
                            Button("Skip") {
                                finalizeDeepLinkJoinName(nil)
                            }
                            Button("Save") {
                                finalizeDeepLinkJoinName(newRoomTempName.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            .buttonStyle(.glass)
                            .disabled(newRoomTempName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.15))
                )
                .padding()
                .transition(.scale.combined(with: .opacity))
            }
            if showJoinPopup {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        if showNameStep {
                            // Ignore outside tap during name step to reduce accidental dismiss
                        } else {
                            joinFieldFocused = false
                            endEditing()
                            withAnimation(.spring()) { showJoinPopup = false }
                        }
                    }

                VStack(spacing: 14) {
                    if !showNameStep {
                        Text("Enter Join Code")
                            .font(.headline)
                            .foregroundColor(.primary)

                        TextField("", text: $joinCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($joinFieldFocused)
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                            .onChange(of: joinCode) { newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered.count > 6 {
                                    joinCode = String(filtered.prefix(6))
                                } else if filtered != newValue {
                                    joinCode = filtered
                                }
                            }

                        HStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { idx in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15))

                                    let ch = character(at: idx)
                                    Text(ch)
                                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .opacity(ch.isEmpty ? 0 : 1)
                                        .scaleEffect(ch.isEmpty ? 0.95 : 1.0)
                                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: ch)

                                    if joinFieldFocused && joinCode.count < 6 && idx == joinCode.count && ch.isEmpty {
                                        Rectangle()
                                            .fill(Color.accentColor.opacity(0.9))
                                            .frame(width: 2, height: 24)
                                            .opacity(caretBlinkOn ? 1 : 0)
                                            .transition(.opacity)
                                    }
                                }
                                .frame(width: 42, height: 50)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { joinFieldFocused = true }

                        HStack(spacing: 20) {
                            Button(role: .cancel) {
                                joinFieldFocused = false
                                endEditing()
                                withAnimation(.spring()) { showJoinPopup = false }
                            } label: { Text("Cancel") }

                            Button {
                                let code = joinCode
                                Task { @MainActor in
                                    if let roomId = await chat.acceptJoinCode(code) {
                                        // Create session and transition to naming step
                                        _ = chat.addAcceptedSession(name: nil, code: code, roomId: roomId, isCreatedByMe: false)
                                        chat.joinRoom(roomId: roomId)
                                        withAnimation(.spring()) {
                                            showNameStep = true
                                            joinFieldFocused = false
                                            endEditing()
                                        }
                                        // Focus name field after animation
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            nameFieldFocused = true
                                        }
                                    } else {
                                        // Could show error feedback here
                                        withAnimation(.shake()) { }
                                    }
                                }
                            } label: {
                                Text("Join")
                                    .fontWeight(.semibold)
                            }
                            .disabled(joinCode.count != 6)
                            .buttonStyle(.glass)
                            .tint(joinCode.count == 6 ? .green : .gray)
                            Button {
                                showJoinScanner = true
                            } label: {
                                Image(systemName: "qrcode.viewfinder")
                            }
                            .accessibilityLabel("Scan QR code")
                        }
                    } else {
                        Text("Name This Room")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Room name", text: $newRoomTempName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .focused($nameFieldFocused)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.15))
                                )
                        }
                        .transition(.opacity.combined(with: .scale))
                        HStack(spacing: 20) {
                            Button("Skip") {
                                finalizeJoinName(nil)
                            }
                            Button("Save") {
                                finalizeJoinName(newRoomTempName.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            .buttonStyle(.glass)
                            .disabled(newRoomTempName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15))
                )
                .padding()
                .transition(.scale.combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Enter 6 digit join code")
                .onAppear { joinFieldFocused = true }
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: joinCode)
                .animation(.easeInOut(duration: 0.18), value: joinFieldFocused)
                .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                    if showJoinPopup && joinFieldFocused && joinCode.count < 6 {
                        withAnimation(.easeInOut(duration: 0.2)) { caretBlinkOn.toggle() }
                    } else {
                        caretBlinkOn = true
                    }
                }
            }
            if showCreatePopup {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        createNameFocused = false
                        endEditing()
                        withAnimation(.spring()) { showCreatePopup = false }
                    }

                VStack(spacing: 14) {
                    if showCreateResult == false {
                        Text("Create Room")
                            .font(.headline)
                            .foregroundColor(.primary)

                        // Room name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Optional room name", text: $roomName)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .focused($createNameFocused)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15))
                                )
                        }

                        // Duration (fixed options)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Expires in")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach([1, 5, 60, 720, 1440], id: \.self) { preset in
                                    Button(action: { durationMinutes = preset }) {
                                        Text(preset < 60 ? "\(preset)m" : (preset % 60 == 0 ? "\(preset/60)h" : "\(preset)m"))
                                            .font(.caption.weight(.semibold))
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 12)
                                            .background(
                                                Capsule().fill(preset == durationMinutes ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Text(formatDuration(durationMinutes))
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 20) {
                            Button("Cancel", role: .cancel) {
                                createNameFocused = false
                                endEditing()
                                withAnimation(.spring()) { showCreatePopup = false }
                            }
                            Button {
                                // Generate code, create pending on server via ChatManager
                                createNameFocused = false
                                endEditing()
                                createdCode = String((0..<6).map { _ in String(Int.random(in: 0...9)) }.joined())
                                _ = chat.createSession(name: roomName.isEmpty ? nil : roomName, minutes: durationMinutes, code: createdCode)
                                withAnimation(.spring()) { showCreateResult = true }
                            } label: {
                                Text("Create")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.glass)
                        }
                    } else {
                        // Result: show code + copy
                        Text("Room Created")
                            .font(.headline)
                            .foregroundColor(.primary)
                        if roomName.isEmpty == false {
                            Text("\(roomName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { idx in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15))
                                    Text(String(createdCode[createdCode.index(createdCode.startIndex, offsetBy: idx)]))
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                }
                                .frame(width: 48, height: 56)
                            }
                        }
                        Button {
                            UIPasteboard.general.string = createdCode
                        } label: {
                            Label("Copy code", systemImage: "doc.on.doc")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 6)
                        Button {
                            showCreatedQRCode = true
                        } label: {
                            Label("Show QR", systemImage: "qrcode")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .padding(.top, 2)

            Button("Done") {
                            withAnimation(.spring()) {
                                showCreatePopup = false
                                showCreateResult = false
                                roomName = ""
                durationMinutes = 5
                                createdCode = ""
                            }
            }
                        .padding(.top, 4)
                    }
                }
                .padding(18)
                .frame(maxWidth: 360)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15))
                )
                .padding()
                .transition(.scale.combined(with: .opacity))
                .onAppear { createNameFocused = true }
            }
        }
        .onDisappear { isExpanded = false }
        .onChange(of: scenePhase) { _ in isExpanded = false }
        .onChange(of: chat.sessions) { _ in
            // Auto-close create popups when session becomes accepted (other client joined)
            if showCreatePopup || showCreateResult || showCreatedQRCode {
                if let activeSession = chat.sessions.first(where: { $0.id == chat.activeSessionId }),
                   activeSession.status == .accepted {
                    withAnimation(.spring()) {
                        showCreatePopup = false
                        showCreateResult = false
                        showCreatedQRCode = false
                        roomName = ""
                        durationMinutes = 5
                        createdCode = ""
                    }
                }
            }
        }
        .sheet(isPresented: $showJoinScanner) {
            QRCodeScannerContainer { code in
                if code.lowercased().hasPrefix("inviso://join/") {
                    if let c = code.split(separator: "/").last, c.count == 6 { joinCode = String(c); showJoinScanner = false }
                }
            }
        }
        .sheet(isPresented: $showCreatedQRCode) {
            VStack(spacing: 16) {
                Text("Share Join Code")
                    .font(.headline)
                if createdCode.count == 6 {
                    QRCodeView(value: "inviso://join/\(createdCode)")
                        .frame(width: 220, height: 220)
                        .padding()
                    Text(createdCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .padding(.bottom, 4)
                } else {
                    ProgressView()
                }
                Button("Close") { showCreatedQRCode = false }
                    .buttonStyle(.glass)
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(.spring()) {
            guard chat.connectionStatus == .connected else { return }
            if isExpanded { showJoinPopup = true; isExpanded = false } else { isExpanded = true }
                    }
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel("Join")
        .disabled(chat.connectionStatus != .connected)

        if isExpanded {
                    Button {
                        withAnimation(.spring()) {
                guard chat.connectionStatus == .connected else { return }
                showCreatePopup = true
                isExpanded = false
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create")
            .disabled(chat.connectionStatus != .connected)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .allowsHitTesting(false)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .allowsHitTesting(false)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Signaling status: \(statusText)")
            }
        }
    }

    private var statusColor: Color {
        switch chat.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var statusText: String {
        switch chat.connectionStatus {
        case .connected: return "Connected"
        case .connecting, .disconnected: return "Waiting"
        }
    }

    // Dismisses keyboard immediately
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func character(at index: Int) -> String {
        guard index < joinCode.count else { return "" }
        let idx = joinCode.index(joinCode.startIndex, offsetBy: index)
        return String(joinCode[idx])
    }

    private func formatDuration(_ minutes: Int) -> String {
        switch minutes {
        case 1: return "1 minute"
        case 5: return "5 minutes"
        case 60: return "1 hour"
        case 720: return "12 hours"
        case 1440: return "24 hours"
        default:
            if minutes < 60 { return "\(minutes) minutes" }
            let h = minutes / 60
            return "\(h) hours"
        }
    }

    private func finalizeJoinName(_ name: String?) {
        // Find most recent accepted session without name (created by others)
        if let session = chat.sessions.first(where: { $0.status == .accepted && $0.isCreatedByMe == false && ($0.name == nil || $0.name?.isEmpty == true) }) {
            chat.renameSession(session, newName: name?.isEmpty == true ? nil : name)
        }
        withAnimation(.spring()) {
            showNameStep = false
            showJoinPopup = false
            isExpanded = false
            joinCode = ""
            newRoomTempName = ""
        }
    }
    
    private func confirmDeepLinkJoinWithNaming() {
        guard let code = chat.pendingDeepLinkCode else { return }
        guard chat.connectionStatus == .connected else { return }
        
        Task { @MainActor in
            // Use custom deep link join that will trigger naming step
            if await chat.confirmPendingDeepLinkJoinWithNaming(code: code) {
                withAnimation(.spring()) {
                    showDeepLinkNameStep = true
                }
                // Focus name field after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    nameFieldFocused = true
                }
            } else {
                // Join failed, could show error feedback
                withAnimation(.shake()) { }
            }
        }
    }
    
    private func finalizeDeepLinkJoinName(_ name: String?) {
        // Find most recent accepted session without name (created by others)
        if let session = chat.sessions.first(where: { $0.status == .accepted && $0.isCreatedByMe == false && ($0.name == nil || $0.name?.isEmpty == true) }) {
            chat.renameSession(session, newName: name?.isEmpty == true ? nil : name)
        }
        withAnimation(.spring()) {
            showDeepLinkNameStep = false
            newRoomTempName = ""
        }
        chat.cancelPendingDeepLinkJoin()
    }
}

// MARK: - Shake animation util
private extension Animation {
    static func shake() -> Animation { .easeInOut(duration: 0.12) }
}

extension View {
    func signalingToolbar() -> some View { self.modifier(SignalingToolbar()) }
}
