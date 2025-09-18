import Foundation
import SkipFuse
import SwiftUI

/// A logger for the PostQuantumSolaceSkipDemo module.

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct PostQuantumSolaceSkipDemoRootView : View {
    /* SKIP @bridge */public init() {
    }
    @State var receiver = MessageReceiverManager()
    
    public var body: some View {
            ContentView(session: SessionManager(receiver: receiver, useWebSockets: false))
                .environment(receiver)
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class PostQuantumSolaceSkipDemoAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = PostQuantumSolaceSkipDemoAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        logger.log(level: .debug, message: "onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.log(level: .debug, message: "onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.log(level: .debug, message: "onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.log(level: .debug, message: "onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.log(level: .debug, message: "onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.log(level: .debug, message: "onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.log(level: .debug, message: "onLowMemory")
    }
}
