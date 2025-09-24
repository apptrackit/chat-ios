//
//  LLMView.swift
//  Inviso
//
//  Created on 9/24/25.
//
//  Placeholder view for upcoming on-device LLM features.
//

import SwiftUI

struct LLMView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 54))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text("On-Device LLM")
                .font(.title.bold())
            Text("This area will host local AI features in a future update.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("LLM")
    }
}

#Preview {
    NavigationStack { LLMView() }
}
