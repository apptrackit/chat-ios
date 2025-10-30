//
//  LifetimeProposalAlert.swift
//  Inviso
//
//  Alert shown when peer proposes a lifetime change
//
//  Created by GitHub Copilot on 10/26/25.
//

import SwiftUI

struct LifetimeProposalAlert: View {
    let proposedLifetime: MessageLifetime
    let peerName: String
    let onAccept: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: proposedLifetime.icon)
                .font(.system(size: 50))
                .foregroundColor(.accentColor)
            
            // Title
            Text("Auto-Delete Change Request")
                .font(.title2)
                .fontWeight(.bold)
            
            // Message
            VStack(spacing: 8) {
                Text("\(peerName) wants to change auto-delete to:")
                    .multilineTextAlignment(.center)
                
                Text(proposedLifetime.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                
                Text(proposedLifetime.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            
            // Warning for ephemeral
            if proposedLifetime == .ephemeral {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Messages will not be saved")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button {
                    onReject()
                } label: {
                    Text("Reject")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                
                Button {
                    onAccept()
                } label: {
                    Text("Accept")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 20)
    }
}

// Sheet wrapper for presenting the alert
struct LifetimeProposalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let proposedLifetime: MessageLifetime
    let peerName: String
    let onAccept: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Dismiss on background tap = reject
                    onReject()
                    dismiss()
                }
            
            LifetimeProposalAlert(
                proposedLifetime: proposedLifetime,
                peerName: peerName,
                onAccept: {
                    onAccept()
                    dismiss()
                },
                onReject: {
                    onReject()
                    dismiss()
                }
            )
            .padding()
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    LifetimeProposalSheet(
        proposedLifetime: .oneDay,
        peerName: "Alice",
        onAccept: { print("Accepted") },
        onReject: { print("Rejected") }
    )
}
