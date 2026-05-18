import SwiftUI

struct LibraryTab: View {
    var body: some View {
        ContentUnavailableView(
            "Library",
            systemImage: "books.vertical",
            description: Text("Browse and manage your audiobook library.")
        )
    }
}
