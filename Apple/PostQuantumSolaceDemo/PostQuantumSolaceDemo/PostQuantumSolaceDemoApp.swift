//
//  PostQuantumSolaceDemoApp.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//

import SwiftUI
import SampleCore

@main
struct PostQuantumSolaceDemoApp: App {
    @State var receiver = MessageReceiverManager()
    var body: some Scene {
        WindowGroup {
            ContentView(session: SessionManager(receiver: receiver, useWebSockets: false))
                .environment(receiver)
        }
    }
}
