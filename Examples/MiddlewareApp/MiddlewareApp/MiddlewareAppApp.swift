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
            .target("https://p2i13hg.middleware.io")
              .serviceName("middleware-ios")
              .projectName("middleware-ios")
              .rumAccessToken("htfxwzzwtwcifogcmmpuqhrxudcknjimyfbb")
            .deploymentEnvironment("PROD")
            .build()
    }
    var body: some Scene {
        WindowGroup {
            SampleView()
        }
    }
}
