// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Product detail: size picker, add-to-cart with RUM event.

import SwiftUI
import MiddlewareRum

struct ProductDetailView: View {
    let product: Product
    @EnvironmentObject var cartStore: CartStore
    @State private var selectedSize: CoffeeSize = .medium
    @State private var addedToCart = false

    var currentPrice: Double { product.price + selectedSize.priceModifier }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: Hero banner
                ZStack {
                    LinearGradient(
                        colors: [Color.espresso, Color.espresso.opacity(0.80)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 4) {
                        Text(product.emoji)
                            .font(.system(size: 96))
                        Text(product.name)
                            .font(.custom("Georgia-Bold", size: 26))
                            .foregroundColor(.cream)
                    }
                    .padding(.vertical, 40)
                }
                .frame(maxWidth: .infinity)

                // MARK: Detail body
                VStack(alignment: .leading, spacing: 20) {

                    // Price row
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name)
                                .font(.custom("Georgia-Bold", size: 26))
                                .foregroundColor(.espresso)
                            Text("Starts at \(product.formattedPrice)")
                                .font(.subheadline)
                                .foregroundColor(.caramel)
                        }
                        Spacer()
                        Text(String(format: "$%.2f", currentPrice))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.espresso)
                            .animation(.easeInOut, value: currentPrice)
                    }

                    Divider().background(Color.latteBeige)

                    // Description
                    Text(product.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineSpacing(5)

                    Divider().background(Color.latteBeige)

                    // MARK: Size picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose Your Size")
                            .font(.headline)
                            .foregroundColor(.espresso)
                        HStack(spacing: 10) {
                            ForEach(CoffeeSize.allCases) { size in
                                SizeButton(
                                    size: size,
                                    isSelected: selectedSize == size
                                ) {
                                    selectedSize = size
                                    MiddlewareRum.debug("Size selected: \(size.displayName) for \(product.name)")
                                }
                            }
                        }
                    }

                    // MARK: Tasting notes
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tasting Notes")
                            .font(.headline)
                            .foregroundColor(.espresso)
                        HStack(spacing: 8) {
                            ForEach(tastingNotes(for: product), id: \.self) { note in
                                Text(note)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.latteBeige)
                                    .foregroundColor(.espresso)
                                    .cornerRadius(20)
                            }
                        }
                    }

                    // MARK: Add to cart
                    Button {
                        addToCart()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: addedToCart ? "checkmark.circle.fill" : "cart.badge.plus")
                                .font(.headline)
                            Text(addedToCart
                                 ? "Added to Cart!"
                                 : "Add to Cart — \(String(format: "$%.2f", currentPrice))")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(addedToCart ? Color.green : Color.espresso)
                        .cornerRadius(14)
                        .animation(.easeInOut(duration: 0.2), value: addedToCart)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
                .padding(20)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .onAppear {
            MiddlewareRum.setScreenName("ProductDetail")
            MiddlewareRum.info("Viewing product: \(product.name) (id: \(product.id))")
        }
    }

    // MARK: - Add to Cart

    private func addToCart() {
        cartStore.add(product: product, size: selectedSize)

        MiddlewareRum.addEvent(name: "add_to_cart", attributes: [
            "product_id":   String(product.id),
            "product_name": product.name,
            "size":         selectedSize.displayName,
            "unit_price":   String(format: "%.2f", currentPrice),
        ])
        MiddlewareRum.info("Cart: added \(product.name) (\(selectedSize.displayName)) @ $\(String(format: "%.2f", currentPrice))")

        withAnimation { addedToCart = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { addedToCart = false }
        }
    }

    // MARK: - Tasting Notes

    private func tastingNotes(for product: Product) -> [String] {
        switch product.id {
        case 1: return ["Bold", "Earthy", "Rich"]
        case 2: return ["Creamy", "Balanced", "Smooth"]
        case 3: return ["Mild", "Silky", "Comforting"]
        case 4: return ["Intense", "Velvety", "Strong"]
        case 5: return ["Smooth", "Sweet", "Refreshing"]
        case 6: return ["Chocolatey", "Rich", "Indulgent"]
        case 7: return ["Clean", "Bold", "Crisp"]
        case 8: return ["Earthy", "Grassy", "Vibrant"]
        default: return ["Complex", "Aromatic"]
        }
    }
}

// MARK: - Size Button

struct SizeButton: View {
    let size: CoffeeSize
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(size.rawValue)
                    .font(.headline)
                    .fontWeight(.bold)
                Text(size.priceModifier > 0
                     ? "+\(String(format: "$%.2f", size.priceModifier))"
                     : "Base")
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .white : .espresso)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(isSelected ? Color.espresso : Color.cream)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.espresso, lineWidth: isSelected ? 0 : 1)
            )
        }
    }
}

#Preview {
    NavigationStack {
        ProductDetailView(product: coffeeMenu[0])
            .environmentObject(CartStore())
    }
}
