// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Cart tab: item list with qty steppers, order summary, checkout CTA.

import SwiftUI
import MiddlewareRum

struct CartView: View {
    @EnvironmentObject var cartStore: CartStore

    var body: some View {
        Group {
            if cartStore.items.isEmpty {
                EmptyCartView()
            } else {
                FilledCartView()
            }
        }
        .navigationTitle("Your Cart")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.cream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            MiddlewareRum.setScreenName("Cart")
            MiddlewareRum.info("Cart viewed — \(cartStore.totalCount) items, total \(cartStore.formattedTotal)")
        }
    }
}

// MARK: - Empty State

struct EmptyCartView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("☕")
                .font(.system(size: 72))
                .padding(.bottom, 4)
            Text("Your cart is empty")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.espresso)
            Text("Browse the menu and add your favourite coffees.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.97, green: 0.94, blue: 0.90).ignoresSafeArea())
    }
}

// MARK: - Filled Cart

struct FilledCartView: View {
    @EnvironmentObject var cartStore: CartStore

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(cartStore.items) { item in
                    CartItemRow(item: item)
                        .listRowBackground(Color.white)
                        .listRowSeparatorTint(Color.latteBeige)
                }
                .onDelete { offsets in
                    MiddlewareRum.info("Cart: item removed")
                    cartStore.remove(at: offsets)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.97, green: 0.94, blue: 0.90))

            // MARK: Order summary + CTA
            VStack(spacing: 14) {
                HStack {
                    Text("Subtotal")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(cartStore.formattedTotal)
                        .fontWeight(.semibold)
                        .foregroundColor(.espresso)
                }
                HStack {
                    Text("Delivery")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("$2.00")
                        .fontWeight(.semibold)
                        .foregroundColor(.espresso)
                }
                Divider().background(Color.latteBeige)
                HStack {
                    Text("Total")
                        .font(.headline)
                        .foregroundColor(.espresso)
                    Spacer()
                    Text(String(format: "$%.2f", cartStore.totalPrice + 2.00))
                        .font(.headline)
                        .foregroundColor(.espresso)
                }

                NavigationLink(destination: CheckoutView()) {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard.fill")
                        Text("Proceed to Checkout")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.espresso)
                    .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(20)
            .background(Color.white)
            .shadow(color: Color.espresso.opacity(0.10), radius: 10, x: 0, y: -4)
        }
        .background(Color(red: 0.97, green: 0.94, blue: 0.90).ignoresSafeArea())
    }
}

// MARK: - Cart Item Row

struct CartItemRow: View {
    let item: CartItem
    @EnvironmentObject var cartStore: CartStore

    var body: some View {
        HStack(spacing: 14) {
            Text(item.product.emoji)
                .font(.system(size: 38))
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.product.name)
                    .font(.headline)
                    .foregroundColor(.espresso)
                Text("\(item.size.displayName)  ·  \(String(format: "$%.2f", item.unitPrice))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(item.formattedSubtotal)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.espresso)

                HStack(spacing: 10) {
                    Button {
                        cartStore.adjustQuantity(for: item, delta: -1)
                        MiddlewareRum.debug("Cart: qty decreased for \(item.product.name)")
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.caramel)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Text("\(item.quantity)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .frame(minWidth: 22)
                        .foregroundColor(.espresso)

                    Button {
                        cartStore.adjustQuantity(for: item, delta: 1)
                        MiddlewareRum.debug("Cart: qty increased for \(item.product.name)")
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.caramel)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        CartView()
            .environmentObject({
                let s = CartStore()
                s.add(product: coffeeMenu[0], size: .medium)
                s.add(product: coffeeMenu[2], size: .large)
                return s
            }())
    }
}
