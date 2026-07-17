// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Login screen: capture username and set RUM global attributes.

import SwiftUI
import MiddlewareRum

struct LoginView: View {
    @EnvironmentObject var userSession: UserSession
    @State private var username = ""
    @State private var isLoggingIn = false
    @FocusState private var focused: Bool

    private var canContinue: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Text("☕")
                        .font(.system(size: 64))
                    Text("Coffee Cart")
                        .font(.custom("Georgia-Bold", size: 36))
                        .foregroundColor(.espresso)
                    Text("Sign in to start ordering")
                        .font(.subheadline)
                        .foregroundColor(.caramel)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Username")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.espresso)

                    TextField("Enter your username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.latteBeige, lineWidth: 1)
                        )
                        .foregroundColor(.espresso)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { login() }

                    Button(action: login) {
                        HStack {
                            if isLoggingIn {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Continue")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canContinue ? Color.caramel : Color.caramel.opacity(0.4))
                        .cornerRadius(12)
                    }
                    .disabled(!canContinue || isLoggingIn)
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            MiddlewareRum.setScreenName("Login")
            MiddlewareRum.info("Login screen viewed")
            focused = true
        }
    }

    private func login() {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoggingIn = true
        userSession.login(username: trimmed)
        MiddlewareRum.info("User logged in as \(trimmed)")
        MiddlewareRum.addEvent(name: "user_login", attributes: [
            "username": trimmed,
            "screen": "Login",
        ])
        isLoggingIn = false
    }
}

#Preview {
    LoginView()
        .environmentObject(UserSession())
}
