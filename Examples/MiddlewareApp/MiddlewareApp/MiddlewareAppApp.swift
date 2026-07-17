// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — App entry point with MiddlewareRum initialisation.

import SwiftUI
import MiddlewareRum

@main
struct MiddlewareAppApp: App {
    @StateObject private var cartStore = CartStore()
    @StateObject private var userSession = UserSession()

    init() {
        MiddlewareRumBuilder()
            .globalAttributes(["app": "CoffeeCart-iOS", "version": "1.0"])
            .target("<target>")
            .serviceName("CoffeeCart-iOS")
            .projectName("CoffeeCart-iOS")
            .rumAccessToken("<rum-token>")
            .deploymentEnvironment("PROD")
            .build()

        MiddlewareRum.info("CoffeeCart iOS app launched")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if userSession.isLoggedIn {
                    RootTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(cartStore)
            .environmentObject(userSession)
            .animation(.easeInOut(duration: 0.25), value: userSession.isLoggedIn)
        }
    }
}
