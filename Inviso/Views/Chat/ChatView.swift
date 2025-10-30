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
    @State private var showLifetimeSettings = false
    @State private var showLifetimeProposal = false
    @State private var proposedLifetime: MessageLifetime? = nil
    @State private var proposerName: String = ""
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
    ZStack(alignment: .center) {
            // Messages list (always shown so user can see history)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { item in
                            let index = item.offset
                            let msg = item.element
                            
                            // Show lifetime change indicator BEFORE the message (skip for system messages)
                            if !msg.isSystem {
                                let previousLifetime = getPreviousNonSystemLifetime(at: index)
                                let currentLifetime = msg.lifetime
                                let isFirst = isFirstNonSystemMessage(at: index)
                                
                                if shouldShowLifetimeIndicator(current: currentLifetime, previous: previousLifetime, isFirstMessage: isFirst) {
                                    LifetimeChangeIndicator(lifetime: currentLifetime)
                                        .padding(.vertical, 8)
                                }
                            }
                            
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
                                ChatBubble(
                                    message: MessageItem(id: msg.id, text: msg.text, isFromSelf: msg.isFromSelf, time: msg.timestamp),
                                    showTime: showTime,
                                    chatMessage: msg
                                )
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
                .onAppear {
                    // Scroll to bottom on initial load
                    if let last = chat.messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

        }
        .navigationBarTitleDisplayMode(.inline)
        .hideTabBar()
        .navigationBarBackButtonHidden(true)
        .onAppear {
            chat.chatViewDidAppear()
            setupLifetimeProposalObserver()
        }
        .onDisappear {
            // If there's a pending proposal when leaving, auto-reject it
            if showLifetimeProposal {
                chat.rejectLifetimeProposal()
            }
            chat.chatViewDidDisappear()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
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
                    
                    // Message lifetime indicator (only when connected)
                    if chat.isP2PConnected, let session = chat.activeSession {
                        CompactLifetimeIndicator(
                            lifetime: session.messageLifetime,
                            agreedByBoth: session.lifetimeAgreedByBoth
                        )
                    }
                }
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
        .sheet(isPresented: $showLifetimeSettings) {
            MessageLifetimeSettingsView(chatManager: chat)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLifetimeProposal) {
            if let proposed = proposedLifetime {
                LifetimeProposalSheet(
                    proposedLifetime: proposed,
                    peerName: proposerName,
                    onAccept: {
                        chat.acceptLifetimeProposal(proposed)
                        showLifetimeProposal = false
                    },
                    onReject: {
                        chat.rejectLifetimeProposal()
                        showLifetimeProposal = false
                    }
                )
                .onDisappear {
                    // If dismissed without action, auto-reject
                    if showLifetimeProposal {
                        chat.rejectLifetimeProposal()
                    }
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
    
    private func setupLifetimeProposalObserver() {
        NotificationCenter.default.addObserver(
            forName: .lifetimeProposalReceived,
            object: nil,
            queue: .main
        ) { [self] notification in
            if let lifetime = notification.userInfo?["lifetime"] as? MessageLifetime,
               let peerName = notification.userInfo?["peerName"] as? String {
                proposedLifetime = lifetime
                proposerName = peerName
                showLifetimeProposal = true
            }
        }
    }
    
    private func shouldShowLifetimeIndicator(current: MessageLifetime?, previous: MessageLifetime?, isFirstMessage: Bool) -> Bool {
        // Always show indicator for the first message if it has a lifetime
        if isFirstMessage && current != nil {
            return true
        }
        
        // Show indicator when lifetime changes between consecutive messages
        if current != previous {
            return true
        }
        
        return false
    }
    
    private func getPreviousNonSystemLifetime(at currentIndex: Int) -> MessageLifetime? {
        for i in (0..<currentIndex).reversed() {
            if !chat.messages[i].isSystem {
                return chat.messages[i].lifetime
            }
        }
        return nil
    }
    
    private func isFirstNonSystemMessage(at index: Int) -> Bool {
        return index == chat.messages.firstIndex(where: { !$0.isSystem })
    }
}

// MARK: - Lifetime Change Indicator

struct LifetimeChangeIndicator: View {
    let lifetime: MessageLifetime?
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(displayText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.12))
        )
        .frame(maxWidth: .infinity)
    }
    
    private var iconName: String {
        guard let lifetime = lifetime else { return "eye.slash" }
        switch lifetime {
        case .ephemeral:
            return "eye.slash"
        case .oneHour:
            return "clock"
        case .sixHours:
            return "clock.badge"
        case .oneDay:
            return "calendar"
        case .sevenDays:
            return "calendar"
        case .thirtyDays:
            return "calendar.badge.clock"
        }
    }
    
    private var displayText: String {
        guard let lifetime = lifetime else { return "RAM Only Mode" }
        switch lifetime {
        case .ephemeral:
            return "RAM Only Mode"
        case .oneHour:
            return "1 Hour Message Lifetime"
        case .sixHours:
            return "6 Hours Message Lifetime"
        case .oneDay:
            return "24 Hours Message Lifetime"
        case .sevenDays:
            return "7 Days Message Lifetime"
        case .thirtyDays:
            return "30 Days Message Lifetime"
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
    let chatMessage: ChatMessage
    @State private var showCopied = false
    @State private var showMessageDetails = false

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
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                showCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    showCopied = false
                                }
                            }
                        } label: {
                            Label("Copy Displayed Text", systemImage: "doc.on.doc")
                        }
                        
                        Button {
                            // Copy the raw decrypted text (what was actually received)
                            UIPasteboard.general.string = chatMessage.text
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                showCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    showCopied = false
                                }
                            }
                        } label: {
                            Label("Copy Raw Decrypted Text", systemImage: "text.quote")
                        }
                        
                        Button {
                            showMessageDetails = true
                        } label: {
                            Label("Message Details", systemImage: "info.circle")
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
        .sheet(isPresented: $showMessageDetails) {
            MessageDetailsView(message: chatMessage)
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

// MARK: - Message Details View

struct MessageDetailsView: View {
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Message Content") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Displayed Text:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(message.text)
                            .font(.body)
                            .textSelection(.enabled)
                        
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy Displayed Text", systemImage: "doc.on.doc")
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Raw Decrypted Data") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This is exactly what was decrypted from the encrypted message (before UI processing):")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(message.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                        
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy Raw Decrypted Text", systemImage: "text.quote")
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Security") {
                    HStack {
                        Text("Encryption")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.green)
                            Text("E2EE")
                                .foregroundColor(.green)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    
                    HStack {
                        Text("Message ID")
                        Spacer()
                        Text(message.id.uuidString.prefix(8))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Timing") {
                    HStack {
                        Text("Sent")
                        Spacer()
                        Text(message.timestamp, style: .date)
                            .foregroundColor(.secondary)
                        Text(message.timestamp, style: .time)
                            .foregroundColor(.secondary)
                    }
                    
                    if let expiresAt = message.expiresAt {
                        HStack {
                            Text("Expires")
                            Spacer()
                            if message.isExpired {
                                Text("Expired")
                                    .foregroundColor(.red)
                            } else {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(expiresAt, style: .date)
                                        .foregroundColor(.secondary)
                                    Text(expiresAt, style: .time)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if let timeRemaining = message.timeUntilExpiration, timeRemaining > 0 {
                            HStack {
                                Text("Time Remaining")
                                Spacer()
                                Text(formatTimeRemaining(timeRemaining))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                
                Section("Storage") {
                    HStack {
                        Text("Storage Mode")
                        Spacer()
                        if message.lifetime == .ephemeral {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.slash")
                                Text("RAM Only")
                            }
                            .foregroundColor(.secondary)
                        } else if message.savedLocally {
                            HStack(spacing: 4) {
                                Image(systemName: "externaldrive.fill")
                                Text("Encrypted Storage")
                            }
                            .foregroundColor(.green)
                        } else {
                            Text("RAM")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if let lifetime = message.lifetime {
                        HStack {
                            Text("Retention Policy")
                            Spacer()
                            Text(lifetimeDisplayName(lifetime))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Technical Details") {
                    Button {
                        let jsonData = messageToJSON()
                        UIPasteboard.general.string = jsonData
                    } label: {
                        Label("Copy Full Message Data (JSON)", systemImage: "curlybraces")
                    }
                }
            }
            .navigationTitle("Message Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatTimeRemaining(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86400
        let hours = Int(interval) / 3600 % 24
        let minutes = Int(interval) / 60 % 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func lifetimeDisplayName(_ lifetime: MessageLifetime) -> String {
        switch lifetime {
        case .ephemeral: return "RAM Only (No Persistence)"
        case .oneHour: return "1 Hour"
        case .sixHours: return "6 Hours"
        case .oneDay: return "24 Hours"
        case .sevenDays: return "7 Days"
        case .thirtyDays: return "30 Days"
        }
    }
    
    private func messageToJSON() -> String {
        let dict: [String: Any] = [
            "id": message.id.uuidString,
            "text": message.text,
            "timestamp": ISO8601DateFormatter().string(from: message.timestamp),
            "isFromSelf": message.isFromSelf,
            "isSystem": message.isSystem,
            "savedLocally": message.savedLocally,
            "expiresAt": message.expiresAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "lifetime": message.lifetime?.rawValue ?? NSNull(),
            "isExpired": message.isExpired,
            "encrypted": true,
            "protocol": "E2EE"
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
}
