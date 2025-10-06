//
//  EphemeralIDsView.swift
//  Inviso
//
//  Displays and manages ephemeral device IDs used per session for privacy.
//

import SwiftUI

struct EphemeralIDsView: View {
    @State private var ephemeralIDs: [EphemeralIDRecord] = []
    @State private var showClearAllConfirm = false
    @State private var idToDelete: EphemeralIDRecord?
    
    var body: some View {
        List {
            Section {
                Text("Each session uses a unique ephemeral device ID that cannot be linked back to your device. These IDs are automatically cleaned when sessions close.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            if ephemeralIDs.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Active Ephemeral IDs")
                            .font(.headline)
                        Text("Create a session to generate an ephemeral ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section(header: Text("Active Ephemeral IDs (\(ephemeralIDs.count))")) {
                    ForEach(ephemeralIDs) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.displayName)
                                    .font(.headline)
                                Spacer()
                                Text(record.shortID)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            
                            Text("Code: \(record.code)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Created: \(record.createdAt, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Full ID: \(record.id)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                idToDelete = record
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                idToDelete = record
                            } label: {
                                Label("Delete ID", systemImage: "trash")
                            }
                            
                            Button {
                                UIPasteboard.general.string = record.id
                            } label: {
                                Label("Copy ID", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showClearAllConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Clear All Ephemeral IDs")
                        }
                    }
                }
            }
        }
        .navigationTitle("Ephemeral IDs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadEphemeralIDs()
        }
        .refreshable {
            loadEphemeralIDs()
        }
        .alert("Delete Ephemeral ID?", isPresented: Binding(
            get: { idToDelete != nil },
            set: { if !$0 { idToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                idToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let id = idToDelete {
                    deleteEphemeralID(id)
                }
            }
        } message: {
            if let id = idToDelete {
                Text("Remove ephemeral ID for \(id.displayName)? This cannot be undone.")
            }
        }
        .alert("Clear All Ephemeral IDs?", isPresented: $showClearAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllEphemeralIDs()
            }
        } message: {
            Text("This will delete all \(ephemeralIDs.count) ephemeral IDs. Active sessions may be affected.")
        }
    }
    
    private func loadEphemeralIDs() {
        ephemeralIDs = DeviceIDManager.shared.getEphemeralIDs()
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    private func deleteEphemeralID(_ record: EphemeralIDRecord) {
        Task {
            // Purge from server first
            await DeviceIDManager.purgeFromServer(ephemeralId: record.id)
            // Then remove locally
            await MainActor.run {
                DeviceIDManager.shared.removeEphemeralID(record.id)
                loadEphemeralIDs()
                idToDelete = nil
            }
        }
    }
    
    private func clearAllEphemeralIDs() {
        Task {
            // Get all IDs before clearing
            let allIds = ephemeralIDs.map { $0.id }
            // Batch purge from server first
            await DeviceIDManager.purgeFromServer(ephemeralIds: allIds)
            // Then clear locally
            await MainActor.run {
                DeviceIDManager.shared.clearAllEphemeralIDs()
                loadEphemeralIDs()
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    NavigationView {
        EphemeralIDsView()
    }
}
