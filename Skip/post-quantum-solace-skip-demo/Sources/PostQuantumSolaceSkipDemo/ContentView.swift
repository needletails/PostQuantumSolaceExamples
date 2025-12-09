//
//  ContentView.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//

import SwiftUI
import SampleCore

struct RegistrationView: View {
    @State var secretName: String = ""
    @State var password: String = AppConfiguration.Session.defaultAppPassword
    @Binding var isRegistered: Bool
    @State var isRegistering: Bool = false
    
    let store: PQSSessionCache
    let session: SessionManager
    
    init(store: PQSSessionCache, session: SessionManager, isRegistered: Binding<Bool>) {
        self.store = store
        self.session = session
        self._isRegistered = isRegistered
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                // Header Section
                VStack(spacing: 8) {
                    Image.appLogo
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                    
                    Text("Create Account")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Enter your details to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Form Section
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Secret Name")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("Enter your secret name", text: $secretName)
                            .textFieldStyle(.roundedBorder)
#if os(iOS)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
#endif
                            .font(.body)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        SecureField("Enter your password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                }
                .padding(.horizontal, 24)
                
                // Register Button
                Button(action: {
                    Task {
                        await register(name: secretName, password: password)
                    }
                }) {
                    HStack {
                        Image.appRegisterPersonBadgePlus
                        Text("Register")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(secretName.isEmpty || password.isEmpty)
                .opacity(secretName.isEmpty || password.isEmpty ? 0.6 : 1.0)
                .padding(.horizontal, 24)
                
                Spacer()
            }
            
            // Loading overlay
            if isRegistering {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
#if os(iOS) || os(macOS) || os(tvOS)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
#else
                        .progressViewStyle(CircularProgressViewStyle())
#endif
                    
                    Text("Registering...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
#if os(iOS) || os(macOS) || os(tvOS)
                        .fill(.ultraThinMaterial)
#else
                        .fill(Color.white.opacity(0.9))
#endif
                        .shadow(radius: 10)
                )
            }
        }
        .padding(.top, 40)
#if os(iOS)
        .background(Color(.systemBackground))
#endif
    }
    
    private func register(name: String, password: String) async {
        do {
            isRegistering = true
            try await session.createSession(
                secretName: name.lowercased(),
                appPassword: password,
                store: store)
            isRegistering = false
            isRegistered = true
        } catch {
            logger.log(level: .error, message: "There was an error registering: \(error)")
        }
    }
}

struct ContentView: View {
    @State var isRegistered = false
    let store = PQSSessionCache()
    let session: SessionManager
    
    init(session: SessionManager) {
        self.session = session
    }
    
    var body: some View {
        Group {
            if isRegistered {
                ContactListView(session: session, isRegistered: $isRegistered)
            } else {
                RegistrationView(store: store, session: session, isRegistered: $isRegistered)
            }
        }
    }
}
