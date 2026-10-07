import AppKit

// AppKit owns startup so CEF can use the required NSApplication subclass.
MainActor.assumeIsolated {
    let application = PaperApplication.shared
    precondition(application is PaperApplication)
    let delegate = PaperAppDelegate()
    application.delegate = delegate
    application.run()
}
