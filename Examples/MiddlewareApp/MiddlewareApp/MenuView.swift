// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Menu tab: coffee catalogue with live API fetch for Network Monitoring.

import SwiftUI
import MiddlewareRum

struct MenuView: View {
    @State private var apiStatus: String = ""
    @State private var isLoadingApi = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: Hero header
                VStack(spacing: 6) {
                    Text("Coffee Cart")
                        .font(.custom("Georgia-Bold", size: 36))
                        .foregroundColor(.espresso)
                    Text("Specialty coffee, crafted for you")
                        .font(.subheadline)
                        .italic()
                        .foregroundColor(.caramel)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color.cream)

                // MARK: Today's pick banner
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.white)
                    Text("Today's Pick: Cold Brew — 20% off")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.caramel)

                // MARK: Product grid
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(coffeeMenu) { product in
                        NavigationLink(value: product) {
                            ProductCard(product: product)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(16)

                // MARK: Live API status card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.caramel)
                        Text("Live Catalog  ·  Network Monitoring")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.espresso)
                        Spacer()
                        Button {
                            fetchApiProducts()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(isLoadingApi ? .secondary : .caramel)
                        }
                        .disabled(isLoadingApi)
                    }

                    if isLoadingApi {
                        HStack(spacing: 8) {
                            ProgressView().tint(.caramel)
                            Text("Fetching from demo.mw.dev…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if !apiStatus.isEmpty {
                        Text(apiStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color.cream)
                .cornerRadius(14)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .background(Color(red: 0.97, green: 0.94, blue: 0.90).ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(for: Product.self) { product in
            ProductDetailView(product: product)
        }
        .onAppear {
            MiddlewareRum.setScreenName("Menu")
            MiddlewareRum.info("MenuView appeared")
            if apiStatus.isEmpty { fetchApiProducts() }
        }
    }

    // MARK: - Network call (exercises Network Monitoring instrumentation)

    private func fetchApiProducts() {
        isLoadingApi = true
        apiStatus = ""
        MiddlewareRum.info("Fetching products from demo.mw.dev API")

        guard let url = URL(string: "https://demo.mw.dev/api/products?currencyCode=USD") else { return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoadingApi = false
                if let error = error {
                    MiddlewareRum.addError("Product API error: \(error.localizedDescription)")
                    apiStatus = "⚠️ API unavailable — showing local catalogue"
                } else if let http = response as? HTTPURLResponse {
                    MiddlewareRum.info("API response: HTTP \(http.statusCode), bytes: \(data?.count ?? 0)")
                    apiStatus = "✓ Live catalogue synced  (HTTP \(http.statusCode))"
                } else {
                    MiddlewareRum.info("Catalogue fetch completed")
                    apiStatus = "✓ Catalogue loaded"
                }
            }
        }.resume()
    }
}

// MARK: - Product Card

struct ProductCard: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(product.emoji)
                .font(.system(size: 48))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.headline)
                    .foregroundColor(.espresso)
                    .lineLimit(1)
                Text(product.formattedPrice)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.caramel)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.espresso.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

#Preview {
    NavigationStack {
        MenuView()
            .environmentObject(CartStore())
    }
}
