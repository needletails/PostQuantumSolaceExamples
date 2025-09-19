import Adwaita
import PQSSession

struct AddContactDialogAdw: View {

	let session: SessionManager
	let receiver: MessageReceiverManager?
	@Binding var visible: Bool
	@Binding var contacts: [Contact]
	@State private var contactName: String = ""

    var view: Body {
        VStack(spacing: 12) {
            Form {
                EntryRow("Contact Name", text: $contactName)
            }
            HStack(spacing: 8) {
                Button("Cancel") {
                    visible = false
                }
                Button("Add") {
                    addAndDismiss()
                }
                    .suggested()
                    .insensitive(contactName.isEmpty)
            }
            .halign(.end)
        }
        .padding(12)
    }

	private func addAndDismiss() {
		Task {
			try? await session.createContact(secretName: contactName.lowercased())
			if let receiver {
                await MainActor.run {
                    contacts = receiver.contacts
                }
			}
			visible = false
		}
	}
}


