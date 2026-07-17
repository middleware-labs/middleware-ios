// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Account tab: shows logged-in username, Help, logout.

import SwiftUI
import MiddlewareRum

struct AccountView: View {
    @EnvironmentObject var userSession: UserSession
    @State private var customerEmail = ""
    @State private var attributesSaved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // MARK: Profile header
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.espresso)
                            .frame(width: 88, height: 88)
                        Text(String(userSession.username.prefix(1)).uppercased())
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.cream)
                    }
                    Text(userSession.username)
                        .font(.custom("Georgia-Bold", size: 22))
                        .foregroundColor(.espresso)
                    Text("Signed in")
                        .font(.caption)
                        .foregroundColor(.caramel)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

                // MARK: Profile form
                SectionCard(title: "Your Profile", icon: "person.fill") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Username")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(userSession.username)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.espresso)
                        }
                        .padding(.vertical, 4)

                        StyledField("Email Address", text: $customerEmail, keyboard: .emailAddress)

                        Button { saveProfile() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: attributesSaved ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                                Text(attributesSaved ? "Profile Saved" : "Save Profile")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(attributesSaved ? Color.green : Color.caramel)
                            .cornerRadius(10)
                        }

                        if attributesSaved {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("RUM global attributes updated with your profile")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // MARK: Support links
                SectionCard(title: "Support", icon: "questionmark.circle.fill") {
                    VStack(spacing: 0) {
                        NavigationLink(destination: HelpScreen()) {
                            AccountLinkRow(icon: "safari", title: "Help & FAQ", subtitle: "middleware.io")
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().background(Color.latteBeige).padding(.vertical, 4)

                        Link(destination: URL(string: "https://app.middleware.io")!) {
                            AccountLinkRow(icon: "chart.bar.xaxis", title: "RUM Dashboard", subtitle: "app.middleware.io")
                        }
                    }
                }

                Button {
                    MiddlewareRum.addEvent(name: "user_logout", attributes: [
                        "username": userSession.username,
                    ])
                    userSession.logout()
                } label: {
                    Text("Sign Out")
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.35), lineWidth: 1)
                        )
                }

                VStack(spacing: 4) {
                    Text("CoffeeCart iOS  ·  v1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Powered by MiddlewareRum SDK")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 28)
            }
            .padding(16)
        }
        .background(Color(red: 0.97, green: 0.94, blue: 0.90).ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.cream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            MiddlewareRum.setScreenName("Account")
            MiddlewareRum.info("Account screen viewed for user \(userSession.username)")
        }
    }

    private func saveProfile() {
        MiddlewareRum.setGlobalAttributes([
            "username": userSession.username,
            "customerName": userSession.username,
            "customerId": userSession.username,
            "customerEmail": customerEmail,
        ])
        MiddlewareRum.info("Global attributes refreshed for \(userSession.username)")
        withAnimation { attributesSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { attributesSaved = false }
        }
    }
}

// MARK: - Account Link Row

struct AccountLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.caramel)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.espresso)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        AccountView()
            .environmentObject(UserSession())
    }
}
