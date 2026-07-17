// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Checkout: delivery details, payment fields (.sensitive()), order placement.

import SwiftUI
import MiddlewareRum

struct CheckoutView: View {
    @EnvironmentObject var cartStore: CartStore
    @EnvironmentObject var userSession: UserSession

    @State private var name        = ""
    @State private var email       = ""
    @State private var address     = ""
    @State private var cardNumber  = ""
    @State private var expiry      = ""
    @State private var cvv         = ""

    @State private var isPlacingOrder = false
    @State private var orderPlaced    = false
    @State private var orderError: String?

    private var isFormValid: Bool {
        !name.isEmpty && !email.isEmpty && !address.isEmpty &&
        !cardNumber.isEmpty && !expiry.isEmpty && !cvv.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // MARK: Delivery details
                SectionCard(title: "Delivery Details", icon: "mappin.circle.fill") {
                    VStack(spacing: 12) {
                        StyledField("Full Name", text: $name)
                        StyledField("Email Address", text: $email, keyboard: .emailAddress)
                        StyledField("Delivery Address", text: $address)
                    }
                }

                // MARK: Payment — card fields use .sensitive() for session recording blur
                SectionCard(title: "Payment", icon: "creditcard.fill") {
                    VStack(alignment: .leading, spacing: 12) {

                        // Card Number — .sensitive() blurs this field in session recordings
                        TextField("Card Number", text: $cardNumber)
                            .keyboardType(.numberPad)
                            .sensitive()
                            .padding(12)
                            .background(Color.cream)
                            .cornerRadius(10)
                            .foregroundColor(.espresso)

                        HStack(spacing: 12) {
                            // Expiry — sensitive
                            TextField("MM/YY", text: $expiry)
                                .keyboardType(.numberPad)
                                .sensitive()
                                .padding(12)
                                .background(Color.cream)
                                .cornerRadius(10)
                                .foregroundColor(.espresso)

                            // CVV — sensitive
                            TextField("CVV", text: $cvv)
                                .keyboardType(.numberPad)
                                .sensitive()
                                .padding(12)
                                .background(Color.cream)
                                .cornerRadius(10)
                                .foregroundColor(.espresso)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.caramel)
                            Text("Card fields are masked in session recordings")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: Order summary
                SectionCard(title: "Order Summary", icon: "list.bullet.clipboard.fill") {
                    VStack(spacing: 10) {
                        ForEach(cartStore.items) { item in
                            HStack {
                                Text("\(item.product.emoji) \(item.product.name) (\(item.size.rawValue)) ×\(item.quantity)")
                                    .font(.subheadline)
                                    .foregroundColor(.espresso)
                                Spacer()
                                Text(item.formattedSubtotal)
                                    .font(.subheadline)
                                    .foregroundColor(.caramel)
                            }
                        }
                        Divider().background(Color.latteBeige)
                        HStack {
                            Text("Total (incl. delivery)")
                                .font(.headline)
                                .foregroundColor(.espresso)
                            Spacer()
                            Text(String(format: "$%.2f", cartStore.totalPrice + 2.00))
                                .font(.headline)
                                .foregroundColor(.espresso)
                        }
                    }
                }

                // MARK: Error banner
                if let err = orderError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(10)
                }

                // MARK: Place Order
                Button { placeOrder() } label: {
                    HStack(spacing: 10) {
                        if isPlacingOrder {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "bag.fill")
                        }
                        Text(isPlacingOrder ? "Placing Order…" : "Place Order")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isFormValid ? Color.espresso : Color.secondary.opacity(0.5))
                    .cornerRadius(14)
                }
                .disabled(!isFormValid || isPlacingOrder)
                .padding(.bottom, 36)
            }
            .padding(16)
        }
        .background(Color(red: 0.97, green: 0.94, blue: 0.90).ignoresSafeArea())
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $orderPlaced) {
            OrderConfirmationView()
        }
        .onAppear {
            if name.isEmpty {
                name = userSession.username
            }
            MiddlewareRum.setScreenName("Checkout")
            MiddlewareRum.info("Checkout screen opened — \(cartStore.totalCount) items for \(userSession.username)")
        }
    }

    // MARK: - Place Order

    private func placeOrder() {
        isPlacingOrder = true
        orderError = nil

        MiddlewareRum.info("Order placement started — total: \(cartStore.formattedTotal)")
        MiddlewareRum.addEvent(name: "checkout_started", attributes: [
            "item_count": String(cartStore.totalCount),
            "total":      String(format: "%.2f", cartStore.totalPrice),
        ])

        // Network call: demonstrates Network Monitoring on checkout path
        guard let url = URL(string: "https://demo.mw.dev/api/products?currencyCode=USD") else { return }
        URLSession.shared.dataTask(with: url) { _, response, error in
            DispatchQueue.main.async {
                isPlacingOrder = false

                if let error = error {
                    MiddlewareRum.addError("Order network error: \(error.localizedDescription)")
                    MiddlewareRum.addException(e: NSException(
                        name: NSExceptionName(rawValue: "OrderNetworkException"),
                        reason: error.localizedDescription
                    ))
                    MiddlewareRum.warning("Order failed due to network error")
                    orderError = "Network error. Please check your connection and try again."
                    return
                }

                MiddlewareRum.info("Order placed successfully for customer: \(name)")
                MiddlewareRum.addEvent(name: "order_placed", attributes: [
                    "item_count": String(cartStore.totalCount),
                    "total":      String(format: "%.2f", cartStore.totalPrice),
                    "customer":   name,
                ])
                cartStore.clear()
                orderPlaced = true
            }
        }.resume()
    }
}

// MARK: - Shared UI Components (used by CheckoutView & AccountView)

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title   = title
        self.icon    = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.caramel)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.espresso)
            }
            content
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.espresso.opacity(0.06), radius: 6, x: 0, y: 3)
    }
}

struct StyledField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    init(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) {
        self.placeholder = placeholder
        self._text       = text
        self.keyboard    = keyboard
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .padding(12)
            .background(Color.cream)
            .cornerRadius(10)
            .foregroundColor(.espresso)
    }
}

#Preview {
    NavigationStack {
        CheckoutView()
            .environmentObject({
                let s = CartStore()
                s.add(product: coffeeMenu[0], size: .medium)
                s.add(product: coffeeMenu[5], size: .large)
                return s
            }())
    }
}
