//
//  MiddlewareAppApp.swift
//  MiddlewareApp
//
//  Created by Archish Thakkar on 12/18/23.
//

import SwiftUI
import MiddlewareRum


@main
struct MiddlewareAppApp: App {
    init() {
        do {
            try MiddlewareRumBuilder()
                .target("<target>")
                .serviceName("Mobile-SDK-iOS")
                .projectName("Mobile-SDK-iOS")
                .rumAccessToken("<rum-token>")
                .deploymentEnvironment("PROD")
                .build()
        } catch {
            print("Failed to initialize \(error)")
        }
        
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
