import SwiftUI

struct SearchView: View {
    @State private var query: String = ""
    @FocusState private var focusSearch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search", text: $query)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($focusSearch)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
            .padding(.horizontal)
            .padding(.top)

            // Placeholder content area
            VStack(spacing: 12) {
                if query.isEmpty {
                    Text("Type to search…")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                } else {
                    Text("No results for ‘\(query)’")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemGroupedBackground))
        }
        .navigationTitle("Search")
        .onAppear {
            // Focus after the view appears to reliably summon the keyboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusSearch = true
            }
        }
    }
}

#Preview {
    NavigationView { SearchView() }
}
