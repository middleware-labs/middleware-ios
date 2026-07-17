// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Data models, cart store, color theme, and menu catalog.

import Foundation
import SwiftUI
import Combine
import MiddlewareRum

// MARK: - Color Theme

extension Color {
    /// Deep espresso brown — primary brand colour
    static let espresso   = Color(red: 0.243, green: 0.102, blue: 0.031)
    /// Warm caramel — accent colour
    static let caramel    = Color(red: 0.769, green: 0.478, blue: 0.204)
    /// Light cream — background / card colour
    static let cream      = Color(red: 0.980, green: 0.961, blue: 0.929)
    /// Latte beige — secondary surface colour
    static let latteBeige = Color(red: 0.929, green: 0.875, blue: 0.800)
}

// MARK: - Product

struct Product: Identifiable, Hashable {
    let id: Int
    let name: String
    let emoji: String
    let price: Double
    let description: String

    var formattedPrice: String { String(format: "$%.2f", price) }
}

// MARK: - Size

enum CoffeeSize: String, CaseIterable, Identifiable {
    case small  = "S"
    case medium = "M"
    case large  = "L"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }

    var priceModifier: Double {
        switch self {
        case .small:  return 0.00
        case .medium: return 0.75
        case .large:  return 1.25
        }
    }
}

// MARK: - Cart Item

struct CartItem: Identifiable {
    let id = UUID()
    let product: Product
    var size: CoffeeSize
    var quantity: Int

    var unitPrice: Double       { product.price + size.priceModifier }
    var subtotal: Double        { unitPrice * Double(quantity) }
    var formattedSubtotal: String { String(format: "$%.2f", subtotal) }
}

// MARK: - User Session

final class UserSession: ObservableObject {
    private static let usernameKey = "coffee_cart_username"

    @Published var username: String
    @Published var isLoggedIn: Bool

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.usernameKey) ?? ""
        username = saved
        isLoggedIn = !saved.isEmpty
        if isLoggedIn {
            applyRumAttributes(username: saved)
        }
    }

    func login(username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.username = trimmed
        self.isLoggedIn = true
        UserDefaults.standard.set(trimmed, forKey: Self.usernameKey)
        applyRumAttributes(username: trimmed)
    }

    func logout() {
        username = ""
        isLoggedIn = false
        UserDefaults.standard.removeObject(forKey: Self.usernameKey)
        MiddlewareRum.setGlobalAttributes([
            "username": "",
            "customerName": "",
        ])
        MiddlewareRum.info("User logged out")
    }

    private func applyRumAttributes(username: String) {
        MiddlewareRum.setGlobalAttributes([
            "username": username,
            "customerName": username,
            "customerId": username,
        ])
        MiddlewareRum.info("RUM username set to \(username)")
    }
}

// MARK: - Cart Store

final class CartStore: ObservableObject {
    @Published var items: [CartItem] = []

    var totalCount: Int    { items.reduce(0) { $0 + $1.quantity } }
    var totalPrice: Double { items.reduce(0) { $0 + $1.subtotal } }
    var formattedTotal: String { String(format: "$%.2f", totalPrice) }

    func add(product: Product, size: CoffeeSize) {
        if let idx = items.firstIndex(where: { $0.product.id == product.id && $0.size == size }) {
            items[idx].quantity += 1
        } else {
            items.append(CartItem(product: product, size: size, quantity: 1))
        }
    }

    func remove(at offsets: IndexSet) { items.remove(atOffsets: offsets) }

    func adjustQuantity(for item: CartItem, delta: Int) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newQty = items[idx].quantity + delta
        if newQty <= 0 { items.remove(at: idx) }
        else { items[idx].quantity = newQty }
    }

    func clear() { items = [] }
}

// MARK: - Coffee Menu Catalog

let coffeeMenu: [Product] = [
    Product(
        id: 1, name: "Espresso", emoji: "☕", price: 3.50,
        description: "A rich, concentrated shot of pure coffee essence, extracted under pressure for a bold and complex flavour with a lingering crema."
    ),
    Product(
        id: 2, name: "Cappuccino", emoji: "🍵", price: 4.75,
        description: "Equal parts espresso, steamed milk, and velvety foam — the Italian classic that balances boldness with creaminess in every sip."
    ),
    Product(
        id: 3, name: "Latte", emoji: "🥛", price: 5.00,
        description: "Smooth espresso blended with silky steamed milk and a delicate layer of foam. Comforting, approachable, and endlessly customisable."
    ),
    Product(
        id: 4, name: "Flat White", emoji: "☕", price: 4.50,
        description: "A double ristretto with velvety microfoam — stronger than a latte, smoother than a cappuccino. The barista's choice."
    ),
    Product(
        id: 5, name: "Cold Brew", emoji: "🧊", price: 5.50,
        description: "Steeped for 18 hours in cold water for a naturally sweet, ultra-smooth coffee experience with remarkably low acidity."
    ),
    Product(
        id: 6, name: "Mocha", emoji: "🍫", price: 5.25,
        description: "Espresso meets rich dark chocolate in a perfect harmony of coffee and cocoa. Indulgent, warming, and deeply satisfying."
    ),
    Product(
        id: 7, name: "Americano", emoji: "☕", price: 3.75,
        description: "Espresso diluted with hot water — clean, long, and deeply satisfying without the intensity of a straight espresso shot."
    ),
    Product(
        id: 8, name: "Matcha Latte", emoji: "🍵", price: 5.75,
        description: "Ceremonial-grade matcha whisked with steamed oat milk. Earthy, grassy, and beautifully vibrant — a perfect balance of calm energy."
    ),
]
