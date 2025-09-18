//
//  AddContactView.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import SwiftUI
import PQSSession

struct AddContactView: View {
    
    let session: SessionManager
    
    init(session: SessionManager, contacts: Binding<[Contact]>) {
        self.session = session
        self._contacts = contacts
    }
    
    @State var contactName = ""
    @Binding var contacts: [Contact]
    @Environment(\.dismiss) var dismiss
    @FocusState var focusedField: Field?
    
    enum Field { case contact, secret }
    
    var canAdd: Bool { !contactName.isEmpty }
    
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
    }
    
    // MARK: - iOS
    private var iOSContent: some View {
        NavigationStack {
            formContent
                .navigationTitle("Add Contact")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { addAndDismiss() }
                            .disabled(!canAdd)
                    }
                }
#else
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { addAndDismiss() }
                            .disabled(!canAdd)
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
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    addAndDismiss()
                }
                    .disabled(!canAdd)
                    .buttonStyle(.borderedProminent)
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
                Button("Add Contact") { addAndDismiss() }
                    .disabled(!canAdd)
            }
        }
#endif
    }
    
    private func addAndDismiss() {
        Task {
            try? await session.createContact(secretName: contactName.lowercased())
            dismiss()
        }
    }
}
