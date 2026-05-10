import Foundation
import AppKit

/// Wraps SPUSBObject (ObjC model) and publishes state for SwiftUI.
final class SpaceMouseUSBViewModel: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var isConnected  = false
    @Published var rotScale:   Float = 10.0
    @Published var transScale: Float = 3.0

    // MARK: - Private model

    private let mouse = SPUSBObject()!

    // MARK: - Init

    override init() {
        super.init()

        mouse.setFrontend(self)

        rotScale   = mouse.rotScale()
        transScale = mouse.transScale()

        // Observe HID connect/disconnect
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceConnected(_:)),
            name: .SPUSBDeviceConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDisconnected(_:)),
            name: .SPUSBDeviceDisconnected,
            object: nil
        )

        // Open HID manager; device-match callback fires asynchronously.
        _ = mouse.connectToDevice()

        // Save prefs and close on quit.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            _ = self.mouse.prefsToDisk()
            _ = self.mouse.disconnectFromDevice()
        }
    }

    // MARK: - Actions

    static let scaleRange: ClosedRange<Float> = 0.1 ... 100.0

    func applyScales() {
        rotScale   = min(max(rotScale,   Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        transScale = min(max(transScale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        _ = mouse.setRotScale(rotScale)
        _ = mouse.setTransScale(transScale)
    }

    /// Re-open the HID manager (e.g. after explicit disconnect).
    func reconnect() {
        _ = mouse.connectToDevice()
    }

    // MARK: - HID notifications

    @objc private func deviceConnected(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
        }
    }

    @objc private func deviceDisconnected(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
    }
}
