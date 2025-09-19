import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var chat: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var showLeaveConfirm = false

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
                .onChange(of: chat.messages.count) { _ in
                    if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .hideTabBar()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showLeaveConfirm = true } label: {
                    HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Leave") }
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Circle()
                    .fill(chat.isP2PConnected ? Color.green : Color.yellow)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(chat.isP2PConnected ? "Connected" : "Waiting")
                    .accessibilityHint("P2P signaling state")
            }
        }
        .overlay(alignment: .top) {
            if chat.isP2PConnected {
                connectionCard
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
        .background(DisablePopGesture())
        .safeAreaInset(edge: .bottom) {
            Group {
                let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HStack(spacing: 8) {
                    SearchBarField(text: $input, placeholder: chat.isP2PConnected ? "Message" : "Waiting for P2P…", onSubmit: { send() })
                        .frame(height: 36)
                        .disabled(!chat.isP2PConnected)
                        .opacity(chat.isP2PConnected ? 1 : 0.6)
                    if hasText && chat.isP2PConnected {
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
    guard !trimmed.isEmpty, chat.isP2PConnected else { return }
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
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorForPath(chat.connectionPath).opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection path: \(chat.connectionPath.displayName)")
    }

    private func iconForPath(_ path: ChatManager.ConnectionPath) -> String {
        switch path {
        case .directLAN: return "wifi"
        case .directReflexive: return "arrow.left.and.right"
        case .relayed: return "cloud"
        case .unknown: return "questionmark"
        }
    }
    private func colorForPath(_ path: ChatManager.ConnectionPath) -> Color {
        switch path {
        case .directLAN: return .green
        case .directReflexive: return .teal
        case .relayed: return .orange
        case .unknown: return .gray
        }
    }
    private var latencyHint: String {
        switch chat.connectionPath {
        case .directLAN: return "Lowest latency"
        case .directReflexive: return "NAT optimized"
        case .relayed: return "Relayed (higher latency)"
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

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isFromSelf { Spacer() }
            VStack(alignment: message.isFromSelf ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(10)
                    .foregroundColor(message.isFromSelf ? .white : .primary)
                    .background(
                        Group {
                            if message.isFromSelf {
                                Capsule().fill(Color.accentColor)
                            } else {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemBackground))
                            }
                        }
                    )
                if showTime {
                    Text(message.time, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
        if let tf = sb.searchTextField as? UITextField {
            tf.leftView = nil
            tf.returnKeyType = .send // Show Send key
        }
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
