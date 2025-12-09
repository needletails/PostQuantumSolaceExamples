//
//  AddContactView.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import SwiftUI
import SampleCore

struct AddContactView: View {
    
    let session: SessionManager
    
    init(session: SessionManager, contacts: Binding<[Contact]>) {
        self.session = session
        self._contacts = contacts
    }
    
    @State private var contactName = ""
    @State private var isCreating: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @Binding var contacts: [Contact]
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    private let logger = NeedleTailLogger("AddContactView")
    
    enum Field { case contact, secret }
    
    var canAdd: Bool { !contactName.isEmpty && !isCreating }
    
    var body: some View {
        Group {
#if os(macOS)
            macOSContent
                .frame(minWidth: 420)
#else
            iOSContent
#endif
        }
        .onAppear { focusedField = .contact }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - iOS
    private var iOSContent: some View {
        NavigationView {
            formContent
                .navigationTitle("Add Contact")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Button("Add") { addAndDismiss() }
                                .disabled(!canAdd)
                        }
                    }
                }
#else
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Button("Add") { addAndDismiss() }
                                .disabled(!canAdd)
                        }
                    }
                }
#endif
        }
    }
    
    // MARK: - macOS
    private var macOSContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Contact")
                .font(.title2).bold()
                .padding(.top, 8)
            
            formContent
                .padding(.top, 4)
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                if isCreating {
                    ProgressView()
                } else {
                    Button("Add") { addAndDismiss() }
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(!canAdd)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
    }
    
    // MARK: - Shared Form
    private var formContent: some View {
#if os(macOS)
        VStack(spacing: 12) {
            LabeledContent("Contact Name") {
                TextField("e.g. Alice", text: $contactName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .contact)
                    .onSubmit { if canAdd { addAndDismiss() } }
            }
        }
#else
        Form {
            Section {
                TextField("Contact Name", text: $contactName)
                    .focused($focusedField, equals: .contact)
#if canImport(UIKit)
                    .textInputAutocapitalization(.words)
#endif
            }
            Section {
                if isCreating {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    Button("Add Contact") { addAndDismiss() }
                        .disabled(!canAdd)
                }
            }
        }
        .formStyle(.grouped)
#endif
    }
    
    private func addAndDismiss() {
        Task {
            await MainActor.run {
                isCreating = true
            }
            
            do {
                let secretName = contactName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !secretName.isEmpty else {
                    await MainActor.run {
                        isCreating = false
                    }
                    return
                }
                
                try await session.createContact(secretName: secretName)
                
                await MainActor.run {
                    isCreating = false
                    contactName = ""
                    dismiss()
                }
            } catch {
                logger.log(level: .error, message: "Failed to create contact: \(error)")
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Failed to create contact: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}
