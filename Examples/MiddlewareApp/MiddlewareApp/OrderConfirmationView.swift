// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Order confirmation screen shown after successful checkout.

import SwiftUI
import MiddlewareRum

struct OrderConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var orderNumber = Int.random(in: 10000...99999)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Success icon
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.green)
                }

                // Headline
                VStack(spacing: 10) {
                    Text("Order Confirmed!")
                        .font(.custom("Georgia-Bold", size: 30))
                        .foregroundColor(.espresso)
                    Text("Your coffee is being crafted with care.\nEstimated delivery: 15–20 minutes.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }

                // Order number badge
                VStack(spacing: 4) {
                    Text("Order Number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("#\(orderNumber)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.caramel)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 32)
                .background(Color.cream)
                .cornerRadius(14)

                // Enjoy message
                HStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundColor(.caramel)
                    Text("Sit back and enjoy the aroma ☕")
                        .font(.subheadline)
                        .foregroundColor(.espresso)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.latteBeige)
                .cornerRadius(12)
            }
            .padding(.horizontal, 32)

            Spacer()

            // Continue Shopping
            Button {
                // Pop back to cart root; cart was already cleared in CheckoutView
                dismiss()
            } label: {
                Text("Continue Shopping")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.espresso)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.97, green: 0.94, blue: 0.90).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            MiddlewareRum.setScreenName("OrderConfirmation")
            MiddlewareRum.info("Order confirmation shown — order #\(orderNumber)")
            MiddlewareRum.addEvent(name: "order_confirmed", attributes: [
                "order_number": String(orderNumber),
            ])
        }
    }
}

#Preview {
    NavigationStack {
        OrderConfirmationView()
    }
}
