import SwiftUI

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

struct ItemCardView: View {
    let imageName: String
    let title: String
    let unit: String
    let price: Double
    let onAdd: () -> Void

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)

                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(String(format: "$%.2f", price))
                            .font(.headline)

                        Spacer()

                        Button {
                            onAdd()
                        } label: {
                            Label("Add", systemImage: "cart.badge.plus")
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}
