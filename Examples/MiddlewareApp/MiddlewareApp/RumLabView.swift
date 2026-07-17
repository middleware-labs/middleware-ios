// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — RUM Lab: interactive demo of every MiddlewareRum SDK feature.

import SwiftUI
import MiddlewareRum

struct RumLabView: View {
    @State private var sensitiveText = ""
    @State private var labLog        = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {

                // MARK: Header
                VStack(spacing: 6) {
                    Image(systemName: "flask")
                        .font(.system(size: 44))
                        .foregroundColor(.caramel)
                    Text("RUM Lab")
                        .font(.custom("Georgia-Bold", size: 30))
                        .foregroundColor(.espresso)
                    Text("Exercise every SDK feature")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // MARK: Crash & Exceptions
                LabSection(title: "Crash & Exceptions", icon: "exclamationmark.triangle.fill") {
                    LabButton(label: "💥  Crash App (null deref)", color: .red) {
                        rumCrashApp()
                    }
                    LabButton(label: "🔥  Custom NSException", color: .orange) {
                        rumCustomException()
                        appendLog("NSException sent to RUM")
                    }
                    LabButton(label: "⚠️  Custom Error String", color: Color(red: 0.8, green: 0.4, blue: 0)) {
                        MiddlewareRum.addError("Lab custom error — triggered by user")
                        appendLog("Custom error string sent")
                    }
                }

                // MARK: Custom Events
                LabSection(title: "Custom Events", icon: "star.fill") {
                    LabButton(label: "Send Custom Event", color: .caramel) {
                        MiddlewareRum.addEvent(name: "lab_custom_event", attributes: [
                            "trigger": "manual",
                            "screen":  "RumLab",
                            "ts":      String(Int(Date().timeIntervalSince1970)),
                        ])
                        appendLog("Event 'lab_custom_event' dispatched")
                    }
                }

                // MARK: Logging Levels
                LabSection(title: "Logging Levels", icon: "text.alignleft") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 8
                    ) {
                        ForEach(["Info", "Debug", "Trace", "Warning", "Error"], id: \.self) { level in
                            Button(level) { sendLog(level: level) }
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity)
                                .background(logColor(level).opacity(0.12))
                                .foregroundColor(logColor(level))
                                .cornerRadius(8)
                        }
                    }
                }

                // MARK: Network
                LabSection(title: "Network Call", icon: "network") {
                    LabButton(label: "Trigger HTTP GET (demo.mw.dev)", color: .espresso) {
                        triggerNetworkCall()
                    }
                }

                // MARK: Session Recording — Sensitive Field
                LabSection(title: "Session Recording", icon: "eye.slash.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type below — this field is blurred in session recordings:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Sensitive input…", text: $sensitiveText)
                            .sensitive()
                            .padding(12)
                            .background(Color.cream)
                            .cornerRadius(10)
                            .foregroundColor(.espresso)
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(.caramel)
                            Text(".sensitive() applied — field masked in recordings")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: Lab Output
                if !labLog.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Lab Output")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Clear") { labLog = "" }
                                .font(.caption)
                                .foregroundColor(.caramel)
                        }
                        Text(labLog)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.espresso)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.cream)
                            .cornerRadius(8)
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(14)
                }

                Spacer(minLength: 28)
            }
            .padding(16)
        }
        .background(Color(red: 0.97, green: 0.94, blue: 0.90).ignoresSafeArea())
        .navigationTitle("RUM Lab")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.cream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            MiddlewareRum.setScreenName("RumLab")
            MiddlewareRum.info("RumLab screen opened")
        }
    }

    // MARK: - Helpers

    private func appendLog(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        labLog = "[\(ts)] \(message)\n" + labLog
    }

    private func sendLog(level: String) {
        let msg = "CoffeeCart Lab log — \(level)"
        switch level {
        case "Info":     MiddlewareRum.info(msg)
        case "Debug":    MiddlewareRum.debug(msg)
        case "Trace":    MiddlewareRum.trace(msg)
        case "Warning":  MiddlewareRum.warning(msg)
        case "Error":    MiddlewareRum.error(msg)
        default: break
        }
        appendLog("\(level) log dispatched")
    }

    private func triggerNetworkCall() {
        MiddlewareRum.info("RumLab: triggering manual HTTP call")
        guard let url = URL(string: "https://demo.mw.dev/api/products?currencyCode=USD") else { return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    MiddlewareRum.addError("Lab network error: \(error.localizedDescription)")
                    appendLog("HTTP call failed: \(error.localizedDescription)")
                } else if let http = response as? HTTPURLResponse {
                    MiddlewareRum.info("Lab HTTP response: \(http.statusCode), bytes: \(data?.count ?? 0)")
                    appendLog("HTTP \(http.statusCode) — \(data?.count ?? 0) bytes received")
                }
            }
        }.resume()
        appendLog("HTTP call dispatched…")
    }

    private func logColor(_ level: String) -> Color {
        switch level {
        case "Info":     return Color(red: 0.20, green: 0.50, blue: 0.90)
        case "Debug":    return Color(red: 0.10, green: 0.60, blue: 0.30)
        case "Trace":    return Color(red: 0.40, green: 0.40, blue: 0.80)
        case "Warning":  return Color(red: 0.85, green: 0.55, blue: 0.10)
        case "Error":    return Color(red: 0.80, green: 0.15, blue: 0.15)
        default:         return .secondary
        }
    }
}

// MARK: - Lab UI Components

struct LabSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title   = title
        self.icon    = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.caramel)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.espresso)
            }
            content
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.espresso.opacity(0.06), radius: 6, x: 0, y: 3)
    }
}

struct LabButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color)
                .cornerRadius(10)
        }
    }
}

// MARK: - Global RUM Lab helpers (kept as free functions to match original style)

func rumCrashApp() {
    let null = UnsafePointer<UInt8>(bitPattern: 0)
    _ = null!.pointee
}

func rumCustomException() {
    MiddlewareRum.addException(e: NSException(
        name: NSExceptionName(rawValue: "LabRuntimeException"),
        reason: "User-triggered exception from CoffeeCart RUM Lab"
    ))
}

#Preview {
    NavigationStack {
        RumLabView()
    }
}
