// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Root tab view (renamed from SampleView).

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var cartStore: CartStore

    init() {
        let cream = UIColor(red: 0.980, green: 0.961, blue: 0.929, alpha: 1.0)
        let espresso = UIColor(red: 0.243, green: 0.102, blue: 0.031, alpha: 1.0)

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = cream

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.selected.iconColor = espresso
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: espresso]
        itemAppearance.normal.iconColor = UIColor.systemGray
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.systemGray]
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            NavigationStack {
                MenuView()
            }
            .tabItem { Label("Menu", systemImage: "cup.and.saucer.fill") }

            NavigationStack {
                CartView()
            }
            .tabItem { Label("Cart", systemImage: "cart.fill") }
            .badge(cartStore.totalCount)

            NavigationStack {
                AccountView()
            }
            .tabItem { Label("Account", systemImage: "person.fill") }

            NavigationStack {
                RumLabView()
            }
            .tabItem { Label("RUM Lab", systemImage: "flask") }
        }
        .tint(Color.espresso)
    }
}

#Preview {
    RootTabView()
        .environmentObject(CartStore())
        .environmentObject(UserSession())
}
