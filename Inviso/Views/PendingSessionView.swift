import SwiftUI
import UIKit
import Combine

struct PendingSessionView: View {
    @EnvironmentObject private var chat: ChatManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var session: ChatSession

    @State private var goToChat = false
    @State private var isVisible = false
    @State private var ticker = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            NavigationLink(destination: ChatView(), isActive: $goToChat) { EmptyView() }.hidden()
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("Share this code")
                        .font(.headline)
                        .foregroundColor(.primary)
                    HStack(spacing: 8) {
                        ForEach(Array(session.code.enumerated()), id: \.offset) { _, ch in
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15))
                                Text(String(ch))
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                            }
                            .frame(width: 48, height: 56)
                        }
                    }
                    Button {
                        UIPasteboard.general.string = session.code
                    } label: {
                        Label("Copy code", systemImage: "doc.on.doc")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.15))
                )

                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("Leave")
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle(session.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel("Waiting for acceptance")
            }
        }
        .onAppear {
            isVisible = true
            chat.pollPendingAndValidateRooms()
            watchAcceptance()
        }
        .onDisappear { isVisible = false }
        .onChange(of: chat.sessions) { _ in watchAcceptance() }
        .onReceive(ticker) { _ in
            if isVisible && scenePhase == .active {
                chat.pollPendingAndValidateRooms()
            }
        }
    }

    private func watchAcceptance() {
        if let updated = chat.sessions.first(where: { $0.id == session.id }), updated.status == .accepted {
            // Close this view; user can enter chat from Sessions
            dismiss()
        }
    }
}

#Preview {
    NavigationView {
        PendingSessionView(session: ChatSession(name: "Test", code: "123456"))
            .environmentObject(ChatManager())
    }
}