// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import SwiftUI
import MiddlewareRum

struct MenuView: View {
    @State private var showWebView = false
    @State private var text = ""
    @State private var toggle = true
    @State private var isShowingModal = false
    
    var body: some View {
        Image(systemName: "globe")
            .imageScale(.large)
            .foregroundStyle(.tint)
        Text("Middleware Application")
            .font(/*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/)
            .foregroundStyle(.red)
        Button(action: {makeHttpCall()}) {
            Text("HTTP CALL")
                .padding(15)
                .foregroundColor(.blue)
                .border(Color.blue, width: 2)
        }.buttonStyle(PlainButtonStyle())
        Button(action: {customEvent()}) {
            Text("CUSTOM EVENT")
                .padding(15)
                .foregroundColor(.blue)
                .border(Color.blue, width: 2)
        }.buttonStyle(PlainButtonStyle())
        
        NavigationStack{
            VStack {
                Button(action: {showWebView = true}) {
                    Text("WEB VIEW")
                        .padding(15)
                        .foregroundColor(.blue)
                        .border(Color.blue, width: 2)
                }.buttonStyle(PlainButtonStyle())
            }
        }.navigationDestination(isPresented: $showWebView) {
            WebView()
        }
        
        Button(action: {crashApp()}) {
            Text("CRASH APP")
                .padding(15)
                .foregroundColor(.blue)
                .border(Color.blue, width: 2)
        }.buttonStyle(PlainButtonStyle())
        Button(action: {
            customException()}) {
                Text("CUSTOM EXCEPTION")
                    .padding(15)
                    .foregroundColor(.blue)
                    .border(Color.blue, width: 2)
            }.buttonStyle(PlainButtonStyle())
        HStack {
            TextField("Text", text: $text)
                .padding()
                .keyboardType(.numberPad)
            Button(action: { hideKeyboard() } , label: {
                Text("OK")
            })
        }
        HStack {
            Toggle(isOn: $toggle) {
                Text("Toggle")
            }
            // Perhaps add a button to dismiss it
            Button("Modal") {
                isShowingModal.toggle()
            }.sheet(isPresented: $isShowingModal, content: {
                VStack {
                    Text("MODAL SHEET")
                    Text("PLEASE IGNORE")
                    Button("Dismiss") {
                        isShowingModal.toggle()
                    }
                }
            })
        }
    }
}

func makeHttpCall() {
    MiddlewareRum.info("Started HTTP CALL")
    let session = URLSession(configuration: .default)
    guard let url = URL(string: "https://demo.mw.dev/api/products?currencyCode=USD") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    let task = session.dataTask(with: request) {
        data, response, error in
        if let data = data {
            print(String(data: data, encoding: .utf8)!)
        } else {
            print("No data")
        }
    }
    task.resume()
    MiddlewareRum.info("Ended HTTP CALL")
}

func customEvent() {
    MiddlewareRum.info("Sending Custom Event")
    MiddlewareRum.addEvent(name: "I am custom event", attributes: ["customerId": "12345"])
    MiddlewareRum.info("Done Custom Event")
    
}

enum MyError: Error {
    case runtimeError(String)
}

func crashApp() {
    let null = UnsafePointer<UInt8>(bitPattern: 0)
    _ = null!.pointee
}

func customException()  {
    MiddlewareRum.addException(e: NSException(name: NSExceptionName(rawValue: "RuntimeException"), reason: "I am custom exception"))
}

func hideKeyboard() {
    print("hideKeyboard")
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    
}


#Preview {
    MenuView()
}
