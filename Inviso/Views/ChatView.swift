import SwiftUI
import UIKit

struct ChatView: View {
    // Placeholder UI state (to be replaced when wiring to ChatManager)
    @State private var messages: [MessageItem] = [
        .init(id: UUID(), text: "Welcome to the room.", isFromSelf: false, time: Date()),
        .init(id: UUID(), text: "Thanks!", isFromSelf: true, time: Date()),
    ]
    @State private var input: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                            let showTime = index == 0 || !Calendar.current.isDate(msg.time, equalTo: messages[index - 1].time, toGranularity: .minute)
                            ChatBubble(message: msg, showTime: showTime)
                                .id(msg.id)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .hideTabBar()
        .safeAreaInset(edge: .bottom) {
            Group {
                let hasText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HStack(spacing: 8) {
                    SearchBarField(text: $input, placeholder: "Message", onSubmit: { send() })
                        .frame(height: 36)
                    if hasText {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(red: 0.0, green: 0.35, blue: 1.0))
                                .frame(width: 22, height: 30)
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
        guard !trimmed.isEmpty else { return }
        let new = MessageItem(id: UUID(), text: trimmed, isFromSelf: true, time: Date())
        messages.append(new)
        input = ""
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
    NavigationView { ChatView() }
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
