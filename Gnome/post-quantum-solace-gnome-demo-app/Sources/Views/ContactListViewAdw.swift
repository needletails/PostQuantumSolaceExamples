import Adwaita
import PQSSession
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ContactListViewAdw: View {

	let session: SessionManager
	@State private var contacts: [Contact] = []
	@Binding var showingAddContact: Bool
	@Binding var isRegistered: Bool
	let receiver: MessageReceiverManager
    @State private var selectedContact: Contact?

    var view: Body {
        VStack(spacing: 12) {
			if contacts.isEmpty {
                VStack(spacing: 8) {
					Text("No Contacts").title3()
					Text("Add your first contact to get started").dimLabel()
				}
				.padding(12)
            } else {
                List(contacts.map { IdentifiedContact(contact: $0) }) { item in
                    HStack {
                        Text(item.contact.secretName)
					}
				}
			}
		}
		.padding(12)
		// Inline dialog per Adwaita patterns
		.dialog(visible: $showingAddContact, title: "Add Contact") {
			AddContactDialogAdw(session: session, receiver: receiver, visible: $showingAddContact, contacts: $contacts)
        }
        // Update source of truth from receiver elsewhere or via periodic refresh
        .onAppear {
            Task { @MainActor in
                contacts = receiver.contacts
            }
        }
	}
}

private struct IdentifiedContact: Identifiable {
	let contact: Contact
	var id: UUID { contact.id }
}


