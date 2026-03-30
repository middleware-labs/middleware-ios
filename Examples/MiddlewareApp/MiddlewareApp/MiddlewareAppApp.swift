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
        MiddlewareRumBuilder()
            .globalAttributes(["name" : "Archish"])
                .target("<target>")
            .serviceName("Mobile-SDK-iOS")
            .projectName("Mobile-SDK-iOS")
                .rumAccessToken("<rum-token>")
            .deploymentEnvironment("PROD")
            .build()
    }
    var body: some Scene {
        WindowGroup {
            SampleView()
        }
    }
}
