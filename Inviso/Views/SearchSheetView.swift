import SwiftUI

struct SearchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack {
            if #available(iOS 16.0, *) {
                List {
                    Section("Results") {
                        Text("No results")
                            .foregroundColor(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Search")
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            } else {
                VStack(spacing: 12) {
                    TextField("Search", text: $query)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    Text("No results")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .navigationTitle("Search")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    NavigationView { SearchSheetView() }
}
