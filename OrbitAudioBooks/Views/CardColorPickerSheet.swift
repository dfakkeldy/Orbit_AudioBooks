import SwiftUI

/// Compact color picker for a single card. Reuses the same swatches as ReaderSettingsSheet.
struct CardColorPickerSheet: View {
    let blockID: String
    let onSelect: (String, String?) -> Void  // (blockID, colorHex or nil for reset)
    @Environment(\.dismiss) private var dismiss

    private let colorSwatches: [(String, String)] = [
        ("#F5F0E8", "Sepia"),
        ("#FFF8E7", "Cream"),
        ("#FFFFFF", "White"),
        ("#F0F0F0", "Light Gray"),
        ("#2C2C2C", "Dark"),
        ("#000000", "Black"),
        ("#E8F5E9", "Soft Green"),
        ("#E3F2FD", "Soft Blue"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Choose a background color for this card.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 4), spacing: 16) {
                    ForEach(colorSwatches, id: \.0) { (hex, name) in
                        Button {
                            onSelect(blockID, hex)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                                Text(name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Button("Reset to Default", role: .destructive) {
                    onSelect(blockID, nil)
                    dismiss()
                }
                .padding(.top, 8)
            }
            .padding(.vertical)
            .navigationTitle("Card Color")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
