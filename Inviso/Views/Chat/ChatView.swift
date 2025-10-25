import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var chat: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var showLeaveConfirm = false
    @State private var showConnectionCard = false
    @State private var showRoomSettings = false
    @State private var showLocationPicker = false
    @State private var showVoiceRecorder = false
    @State private var showPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
    ZStack(alignment: .center) {
            // Messages list (always shown so user can see history)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, msg in
                            if msg.isSystem {
                                Text(msg.text)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 2)
                                    .id(msg.id)
                                    .padding(.horizontal)
                            } else if msg.isLocationMessage, let location = msg.locationData {
                                // Location message
                                let showTime = index == 0 || !Calendar.current.isDate(msg.timestamp, equalTo: chat.messages[index - 1].timestamp, toGranularity: .minute)
                                LocationMessageBubble(location: location, isFromSelf: msg.isFromSelf, showTime: showTime, timestamp: msg.timestamp)
                                    .id(msg.id)
                            } else if msg.isVoiceMessage, let voice = msg.voiceData {
                                // Voice message
                                let showTime = index == 0 || !Calendar.current.isDate(msg.timestamp, equalTo: chat.messages[index - 1].timestamp, toGranularity: .minute)
                                VoiceMessageBubble(voice: voice, isFromSelf: msg.isFromSelf, showTime: showTime, timestamp: msg.timestamp)
                                    .id(msg.id)
                            } else {
                                // Text message
                                let showTime = index == 0 || !Calendar.current.isDate(msg.timestamp, equalTo: chat.messages[index - 1].timestamp, toGranularity: .minute)
                                ChatBubble(message: MessageItem(id: msg.id, text: msg.text, isFromSelf: msg.isFromSelf, time: msg.timestamp), showTime: showTime)
                                    .id(msg.id)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        // Dismiss keyboard when user starts scrolling
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                )
                .onChange(of: chat.messages.count) {
                    if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

        }
        .navigationBarTitleDisplayMode(.inline)
        .hideTabBar()
        .navigationBarBackButtonHidden(true)
        .onAppear {
            chat.chatViewDidAppear()
        }
        .onDisappear {
            chat.chatViewDidDisappear()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showRoomSettings = true
                } label: {
                    HStack(spacing: 4) {
                        Text(chat.activeSessionDisplayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showLeaveConfirm = true } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Leave") }
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                // Combined connection and encryption indicator button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showConnectionCard.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        // Encryption status
                        if chat.keyExchangeInProgress {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Encrypting")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        } else if chat.isEncryptionReady {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("E2EE")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.green)
                        } else if chat.isP2PConnected {
                            Image(systemName: "lock.open.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        // Connection status dot
                        Circle()
                            .fill(chat.isP2PConnected ? Color.green : Color.yellow)
                            .frame(width: 10, height: 10)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    chat.isEncryptionReady ? "End-to-end encrypted" :
                    chat.keyExchangeInProgress ? "Establishing encryption" :
                    chat.isP2PConnected ? "Connected, not encrypted" :
                    "Waiting for connection"
                )
                .accessibilityHint("Tap to show connection details")
            }
        }
        .overlay(alignment: .top) {
            if showConnectionCard {
                ConnectionIndicatorCard()
                    .environmentObject(chat)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showConnectionCard = false
                        }
                    }
            }
        }
        .alert("Leave chat?", isPresented: $showLeaveConfirm) {
            Button("Leave", role: .destructive) {
                // Dismiss first to avoid UI race, then leave/disconnect
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    safeLeave()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will disconnect from this room.")
        }
        .sheet(isPresented: $showRoomSettings) {
            if let session = chat.activeSession {
                NavigationView {
                    RoomSettingsView(session: session)
                        .environmentObject(chat)
                }
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView { location in
                chat.sendLocation(location)
            }
        }
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("OK", role: .cancel) {}
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Task { @MainActor in
                        await UIApplication.shared.open(url)
                    }
                }
            }
        } message: {
            Text(permissionAlertMessage)
        }
        .overlay {
            if showVoiceRecorder {
                VoiceRecordingView { voice in
                    chat.sendVoice(voice)
                } onClose: {
                    showVoiceRecorder = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(3)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showVoiceRecorder)
        .background(DisablePopGesture())
        .safeAreaInset(edge: .bottom) {
            Group {
                let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let canSend = chat.isP2PConnected && chat.isEncryptionReady
                HStack(spacing: 8) {
                    if !hasText {
                        // Voice message button (only when no text)
                        Button {
                            if !permissionManager.canUseVoiceMessages {
                                permissionAlertMessage = "Microphone permission is required to send voice messages. Enable it in Settings > Permissions."
                                showPermissionAlert = true
                            } else {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    showVoiceRecorder = true
                                }
                            }
                        } label: {
                            Image(systemName: "waveform")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.35, blue: 1.0))
                                .frame(width: 20, height: 30)
                        }
                        .buttonStyle(.glass)
                        .disabled(!canSend)
                        .opacity(canSend ? 1 : 0.4)
                        .transition(.scale.combined(with: .opacity))
                        
                        // Location sharing button (only when no text)
                        Button {
                            if !permissionManager.canUseLocationSharing {
                                permissionAlertMessage = "Location permission is required to share your location. Enable it in Settings > Permissions."
                                showPermissionAlert = true
                            } else {
                                showLocationPicker = true
                            }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.35, blue: 1.0))
                                .frame(width: 20, height: 30)
                        }
                        .buttonStyle(.glass)
                        .disabled(!canSend)
                        .opacity(canSend ? 1 : 0.4)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    SearchBarField(
                        text: $input,
                        placeholder: canSend ? "Message" : chat.isP2PConnected ? "Encrypting…" : "Waiting for P2P…",
                        onSubmit: { send() }
                    )
                        .frame(height: 44)
                        .disabled(!canSend)
                        .opacity(canSend ? 1 : 0.6)
                    if hasText && canSend {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.35, blue: 1.0))
                                .frame(width: 20, height: 30)
                        }
                        .transition(.scale.combined(with: .opacity))
                        .buttonStyle(.glass)
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: input)
            }
            .modifier(GlassContainerModifier())
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, chat.isP2PConnected, chat.isEncryptionReady else { return }
        chat.sendMessage(trimmed)
        input = ""
    }

    private func safeLeave() {
        if chat.roomId.isEmpty {
            // Pending session: just leave view; keep session waiting
        } else {
            chat.leave(userInitiated: true)
        }
    }
}


// Helper to disable the interactive pop (swipe-back) gesture so the confirmation can't be bypassed.
private struct DisablePopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Controller()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

struct ChatBubble: View {
    let message: MessageItem
    var showTime: Bool = true
    @State private var showCopied = false

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isFromSelf { Spacer() }
            VStack(alignment: message.isFromSelf ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(10)
                    .foregroundColor(message.isFromSelf ? .white : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(message.isFromSelf ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                    )
                    .onLongPressGesture(minimumDuration: 0.3) {
                        // Copy message instantly on long press
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()
                        
                        UIPasteboard.general.string = message.text
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            showCopied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                showCopied = false
                            }
                        }
                    }
                if showTime {
                    Text(message.time, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .overlay(alignment: .top) {
                if showCopied {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.caption2.weight(.semibold))
                        Text("Copied")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.green)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .offset(y: -44)
                    .fixedSize()
                    .transition(.scale.combined(with: .opacity))
                }
            }
            if !message.isFromSelf { Spacer() }
        }
    }
}

struct MessageItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let isFromSelf: Bool
    let time: Date
}

#Preview {
    NavigationView { ChatView().environmentObject(ChatManager()) }
}

private extension View {
    @ViewBuilder
    func hideTabBar() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(.hidden, for: .tabBar)
        } else {
            self
                .onAppear { UITabBar.appearance().isHidden = true }
                .onDisappear { UITabBar.appearance().isHidden = false }
        }
    }
}

// System UISearchBar wrapped for bottom input, with icon removed
struct SearchBarField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Search"
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISearchBar {
        let sb = UISearchBar(frame: .zero)
        sb.searchBarStyle = .minimal
        sb.placeholder = placeholder
        sb.autocapitalizationType = .none
        sb.autocorrectionType = .no
        sb.enablesReturnKeyAutomatically = true
        sb.delegate = context.coordinator
        // Remove magnifying icon
        let tf = sb.searchTextField
        tf.leftView = nil
        tf.returnKeyType = .send // Show Send key
        return sb
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        if uiView.text != text { uiView.text = text }
        if uiView.placeholder != placeholder { uiView.placeholder = placeholder }
    }

    class Coordinator: NSObject, UISearchBarDelegate {
        var parent: SearchBarField
        init(_ parent: SearchBarField) { self.parent = parent }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            parent.onSubmit?()
        }
    }
}
