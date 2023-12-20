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
            .globalAttributes(["some" : "value"])
                .target("<target>")
            .serviceName("Mobile-SDK-Android")
            .projectName("Mobile-SDK-Android")
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
