import SwiftUI

@main
struct SpaceMouseUSBControllerApp: App {
    init() {
        // Redirect NSLog (stderr) to a file; readable with: tail -f /tmp/SpaceMouseUSBController.log
        freopen("/tmp/SpaceMouseUSBController.log", "a", stderr)
    }

    var body: some Scene {
        WindowGroup("SpaceMouse USB Controller") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
