//
//  ContactListView.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//

import SwiftUI
import PQSSession

extension Contact: @retroactive Identifiable {}

struct ContactListView: View {
    let session: SessionManager
    @Environment(MessageReceiverManager.self) var receiver
    @State var contacts: [Contact] = []
    @State var showingAddContact = false
    @Binding var isRegistered: Bool
    
    var body: some View {
        NavigationStack {
            VStack {
                if contacts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Contacts")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Text("Add your first contact to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(contacts) { contact in
                        NavigationLink(destination: ChatView(contact: contact, session: session)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contact.secretName)
                                    .font(.headline)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .onChange(of: receiver.contacts, { _, newValue in
                self.contacts = newValue
            })
            .navigationTitle("Contacts")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        showingAddContact = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: {
                        isRegistered = false
                    }) {
                        Text("Sign Out")
                    }
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactView(session: session, contacts: $contacts)
            }
        }
    }
}
