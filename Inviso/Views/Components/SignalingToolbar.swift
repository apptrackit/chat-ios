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

    func body(content: Content) -> some View {
        ZStack {
            content
            if isExpanded {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.spring()) { isExpanded = false } }
            }
            if showJoinPopup {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        joinFieldFocused = false
                        endEditing()
                        withAnimation(.spring()) { showJoinPopup = false }
                    }

                VStack(spacing: 12) {
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
                            print("Join code submitted: \(code)")
                            joinFieldFocused = false
                            endEditing()
                            withAnimation(.spring()) {
                                showJoinPopup = false
                                isExpanded = false
                                joinCode = ""
                            }
                        } label: {
                            Text("Join")
                                .fontWeight(.semibold)
                        }
                        .disabled(joinCode.count != 6)
                        .buttonStyle(.glass)
                        .tint(joinCode.count == 6 ? .green : .gray)
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
        }
        .onDisappear { isExpanded = false }
        .onChange(of: scenePhase) { _ in isExpanded = false }
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
                        if isExpanded {
                            showJoinPopup = true
                            isExpanded = false
                        } else {
                            isExpanded = true
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                }
                .accessibilityLabel("Join")

                if isExpanded {
                    Button {
                        print("Create tapped")
                        withAnimation(.spring()) { isExpanded = false }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create")
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
}

extension View {
    func signalingToolbar() -> some View { self.modifier(SignalingToolbar()) }
}
