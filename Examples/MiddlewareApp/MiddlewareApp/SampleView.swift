//
//  ContentView.swift
//  MiddlewareApp
//
//  Created by Archish Thakkar on 12/18/23.
//

import SwiftUI

struct SampleView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Middleware Application")
                NavigationLink("Show Menu", destination: MenuView())
            }
            .padding()
        }
    }
}

#Preview {
    SampleView()
}
