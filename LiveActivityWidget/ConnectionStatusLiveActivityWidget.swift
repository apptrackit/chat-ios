//
//  ConnectionStatusLiveActivityWidget.swift
//  Inviso Live Activity Widget
//
//  Created by GitHub Copilot on 9/28/25.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct ConnectionActivityView: View {
    let context: ActivityViewContext<ConnectionAttributes>

    var body: some View {
        HStack(spacing: 12) {
            IndicatorCircle(isConnected: context.state.isConnected)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.roomName)
                    .font(.headline)
                    .bold()
                Text(context.state.statusText)
                    .font(.subheadline)
                    .foregroundStyle(context.state.isConnected ? Color.green : Color.yellow)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ConnectionStatusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConnectionAttributes.self) { context in
            ConnectionActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IndicatorCircle(isConnected: context.state.isConnected)
                        .padding(.vertical, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.isConnected ? "Clients linked" : "Waiting on peer")
                            .font(.footnote)
                            .bold()
                        Text(context.attributes.roomName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Image(systemName: context.state.isConnected ? "link" : "hourglass")
                        Text(context.state.isConnected ? "Secure P2P channel live." : "Leave this running; we’ll notify when connected.")
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            } compactLeading: {
                IndicatorCircle(isConnected: context.state.isConnected)
            } compactTrailing: {
                Text(context.state.isConnected ? "ON" : "…")
                    .font(.caption2)
            } minimal: {
                IndicatorCircle(isConnected: context.state.isConnected)
            }
        }
    }
}

struct ConnectionStatusLiveActivityWidget_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionStatusLiveActivity()
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
