import Adwaita
import PQSSession
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HomeViewAdw: View {

	let app: AdwaitaApp
	let window: AdwaitaWindow
	@Binding var isRegistered: Bool
	@Binding var showingAddContact: Bool
	let receiver: MessageReceiverManager
	let session: SessionManager
    @State private var selectedId: UUID = .init()
	@State private var contacts: [Contact] = []
	@State private var wide = true

	var view: Body {
        OverlaySplitView(visible: .constant(true)) {
            ScrollView {
                List(contacts.map { IdentifiedContact(contact: $0) }, selection: $selectedId) { item in
					Text(item.contact.secretName)
						.padding()
				}
				.sidebarStyle()
            }
            .hscrollbarPolicy(.never)
            .vexpand()
            .hexpand()
        } content: {
            if let contact = contacts.first(where: { $0.id == selectedId }) {
                ChatViewAdw(receiver: receiver, contact: contact, session: session)
                    .vexpand()
                    .hexpand()
			} else {
				StatusPage(
					"No Chat Selected",
                    icon: .default(icon: .applicationXExecutable),
					description: "Select a contact from the sidebar"
                ) { }
                .vexpand()
                .hexpand()
			}
        }
        .vexpand()
        .hexpand()
        .breakpoint(minWidth: 600, matches: $wide)
        .onAppear {
            contacts = receiver.contacts
            Task {
                logger.log(level: .info, message: "Contact Stream \(receiver.contactStream)")
                for await contact in receiver.contactStream {
                    logger.log(level: .info, message: "Streamed Contact \(contact)")
                    contacts.append(contact)
                }
            }
        }
        .dialog(visible: $showingAddContact, title: "Add Contact") {
            AddContactDialogAdw(session: session, receiver: receiver, visible: $showingAddContact, contacts: $contacts)
        }
	}
}

private struct IdentifiedContact: Identifiable, Equatable {
	let contact: Contact
	var id: UUID { contact.id }
}


