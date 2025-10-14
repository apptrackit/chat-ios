import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var chat: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var showLeaveConfirm = false
    @State private var showConnectionCard = false
    @State private var showRoomSettings = false

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
                            } else {
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
                connectionCard
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
        .background(DisablePopGesture())
        .safeAreaInset(edge: .bottom) {
            Group {
                let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let canSend = chat.isP2PConnected && chat.isEncryptionReady
                HStack(spacing: 8) {
                    SearchBarField(
                        text: $input,
                        placeholder: canSend ? "Message" : chat.isP2PConnected ? "Encrypting…" : "Waiting for P2P…",
                        onSubmit: { send() }
                    )
                        .frame(height: 36)
                        .disabled(!canSend)
                        .opacity(canSend ? 1 : 0.6)
                    if hasText && canSend {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.35, blue: 1.0))
                                .frame(width: 36, height: 36)
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

    private var connectionCard: some View {
        VStack(spacing: 10) {
            // Connection path info or waiting status
            if chat.isP2PConnected {
                HStack(spacing: 10) {
                    Image(systemName: iconForPath(chat.connectionPath))
                        .foregroundColor(colorForPath(chat.connectionPath))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.connectionPath.displayName)
                            .font(.caption.weight(.semibold))
                        Text(latencyHint)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(chat.connectionPath.shortLabel)
                        .font(.caption2.weight(.bold))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(colorForPath(chat.connectionPath).opacity(0.15)))
                }
            } else {
                // Waiting for P2P connection
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for Peer")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.yellow)
                        Text("Establishing P2P connection…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("WAITING")
                        .font(.caption2.weight(.bold))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(Color.yellow.opacity(0.15)))
                        .foregroundColor(.yellow)
                }
            }
            
            // Encryption status
            if chat.isEncryptionReady || chat.keyExchangeInProgress {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: chat.isEncryptionReady ? "lock.shield.fill" : "lock.rotation")
                        .foregroundColor(chat.isEncryptionReady ? .green : .orange)
                        .symbolEffect(.pulse, options: .repeating, isActive: chat.keyExchangeInProgress)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.isEncryptionReady ? "End-to-End Encrypted" : "Establishing Encryption")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(chat.isEncryptionReady ? .green : .orange)
                        Text(chat.isEncryptionReady ? "Messages are secure" : "Exchanging keys…")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    
                    if chat.keyExchangeInProgress {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if chat.isEncryptionReady {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    chat.isEncryptionReady ? Color.green.opacity(0.3) :
                    chat.keyExchangeInProgress ? Color.orange.opacity(0.3) :
                    chat.isP2PConnected ? colorForPath(chat.connectionPath).opacity(0.25) :
                    Color.yellow.opacity(0.3),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection: \(chat.isP2PConnected ? chat.connectionPath.displayName : "Waiting"). Encryption: \(chat.isEncryptionReady ? "Active" : chat.keyExchangeInProgress ? "In progress" : "None")")
    }

    private func iconForPath(_ path: ChatManager.ConnectionPath) -> String {
        switch path {
        case .directLAN: return "wifi"
        case .directReflexive: return "arrow.left.and.right"
        case .relayed: return "cloud"
        case .possiblyVPN: return "network.badge.shield.half.filled"
        case .unknown: return "questionmark"
        }
    }
    private func colorForPath(_ path: ChatManager.ConnectionPath) -> Color {
        switch path {
        case .directLAN: return .green
        case .directReflexive: return .teal
        case .relayed: return .orange
        case .possiblyVPN: return .purple
        case .unknown: return .gray
        }
    }
    private var latencyHint: String {
        switch chat.connectionPath {
        case .directLAN: return "Lowest latency"
        case .directReflexive: return "NAT optimized"
        case .relayed: return "Relayed (higher latency)"
        case .possiblyVPN: return "VPN may affect performance"
        case .unknown: return "Resolving path…"
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
