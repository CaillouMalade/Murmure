import AppKit
import Darwin

@main
enum MurmureApplication {
    @MainActor
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let application = NSApplication.shared
        let controller = AppController()
        application.delegate = controller
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(controller) { application.run() }
    }
}
