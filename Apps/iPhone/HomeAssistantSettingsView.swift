// SPDX-License-Identifier: MPL-2.0
import AlarmCore
import SwiftUI
import VisionKit

struct HomeAssistantSettingsView: View {
    @Bindable var bridge: HomeAssistantBridge
    @State private var scanning = false
    @State private var candidate: HomeAssistantPairing?
    @State private var confirming = false
    @State private var issue: String?
    @State private var busy = false

    var body: some View {
        Form {
            if bridge.paired {
                Text(bridge.host)
                Button("Sync now") { Task { await bridge.synchronize() } }
                Button("Disconnect", role: .destructive) {
                    Task {
                        busy = true
                        defer { busy = false }
                        do { try await bridge.disconnect() } catch { issue = "Could not revoke pairing. Use Home Assistant options." }
                    }
                }
            } else {
                Button("Scan pairing code") {
                    guard DataScannerViewController.isSupported && DataScannerViewController.isAvailable else {
                        issue = "QR scanning is unavailable. Allow camera access in iPhone Settings."
                        return
                    }
                    scanning = true
                }
            }
            if let text = issue ?? bridge.message { Text(text).foregroundStyle(.secondary) }
        }
        .disabled(busy)
        .navigationTitle("Home Assistant")
        .sheet(isPresented: $scanning, onDismiss: { if candidate != nil { confirming = true } }) {
            NavigationStack {
                PairingScanner { text in
                    scanning = false
                    do {
                        guard text.utf8.count <= 4096 else { throw AlarmError.invalidSettings }
                        let pairing = try JSONDecoder().decode(HomeAssistantPairing.self, from: Data(text.utf8))
                        try pairing.validate()
                        candidate = pairing
                    } catch { issue = "Invalid Alarm Beans pairing code." }
                }
                .navigationTitle("Scan pairing code")
                .toolbar { ToolbarItem { Button("Cancel") { scanning = false } } }
            }
        }
        .confirmationDialog("Pair with \(candidate?.url.host ?? "Home Assistant")?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Pair") {
                guard let candidate else { return }
                self.candidate = nil
                Task {
                    busy = true
                    defer { busy = false }
                    do { try await bridge.pair(candidate); issue = nil }
                    catch { issue = "Pairing failed. Generate a new code in Home Assistant." }
                }
            }
            Button("Cancel", role: .cancel) { candidate = nil }
        }
    }
}

private struct PairingScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var delivered = false
        init(_ onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for case .barcode(let barcode) in addedItems {
                if let code = barcode.payloadStringValue {
                    delivered = true
                    dataScanner.stopScanning()
                    onCode(code)
                    break
                }
            }
        }
    }
}
