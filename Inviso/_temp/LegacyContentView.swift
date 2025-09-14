// Backup of the original ContentView before UI redesign.
// Do not ship this file; it's here for reference during the rewrite.

import SwiftUI

struct LegacyContentView: View {
    @StateObject private var chatManager = ChatManager()
    @State private var messageText = ""
    @State private var roomId = ""
    @State private var deviceID = DeviceIDManager.shared.id

    var body: some View {
        NavigationView {
            VStack {
                // Connection Status
                HStack {
                    Circle()
                        .fill(chatManager.connectionStatus == .connected ? .green :
                              chatManager.connectionStatus == .connecting ? .orange : .red)
                        .frame(width: 12, height: 12)
                    Text(chatManager.connectionStatus.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)

                // Device ID
                HStack {
                    Text("Device ID:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(deviceID)
                        .font(.caption2)
                        .textSelection(.enabled)
                    #if DEBUG
                    Spacer(minLength: 8)
                    Button("Reset") {
                        DeviceIDManager.shared.reset()
                        deviceID = DeviceIDManager.shared.id
                    }
                    .font(.caption)
                    #endif
                    Spacer()
                }
                .padding(.horizontal)

                // Room Connection
                if chatManager.connectionStatus == .disconnected || chatManager.roomId.isEmpty {
                    VStack {
                        TextField("Enter Room ID", text: $roomId)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)

                        Button("Join Room") {
                            let finalRoomId = roomId.isEmpty ? "default" : roomId
                            chatManager.connect()
                            chatManager.joinRoom(roomId: finalRoomId)
                        }
                        .disabled(roomId.trimmingCharacters(in: .whitespaces).isEmpty && roomId != "")
                        .padding()
                    }
                    .padding()
                } else {
                    // Chat Interface
                    VStack {
                        Text("Room: \(chatManager.roomId)")
                            .font(.headline)
                            .padding(.top)

                        Button(role: .destructive) {
                            chatManager.leave()
                            messageText = ""
                        } label: {
                            Text("Leave Room")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)

                        if !chatManager.isP2PConnected {
                            Text("Waiting for P2P connection...")
                                .foregroundColor(.orange)
                                .padding()
                        }

                        // Messages List
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(chatManager.messages) { message in
                                        HStack {
                                            if message.isFromSelf {
                                                Spacer()
                                                Text(message.text)
                                                    .padding(8)
                                                    .background(Color.blue)
                                                    .foregroundColor(.white)
                                                    .cornerRadius(12)
                                            } else {
                                                Text(message.text)
                                                    .padding(8)
                                                    .background(Color.gray.opacity(0.2))
                                                    .cornerRadius(12)
                                                Spacer()
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            .onChange(of: chatManager.messages.count) { _ in
                                if let lastMessage = chatManager.messages.last {
                                    withAnimation {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                        }

                        // Message Input
                        HStack {
                            TextField("Type a message...", text: $messageText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onSubmit {
                                    sendMessage()
                                }

                            Button("Send") {
                                sendMessage()
                            }
                            .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || !chatManager.isP2PConnected)
                        }
                        .padding()
                    }
                }

                Spacer()
            }
            .navigationTitle("P2P Chat")
            .onAppear {
                if chatManager.connectionStatus == .disconnected {
                    chatManager.connect()
                }
            }
        }
    }

    private func sendMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespaces)
        if !trimmedMessage.isEmpty {
            chatManager.sendMessage(trimmedMessage)
            messageText = ""
        }
    }
}

#Preview {
    LegacyContentView()
}
