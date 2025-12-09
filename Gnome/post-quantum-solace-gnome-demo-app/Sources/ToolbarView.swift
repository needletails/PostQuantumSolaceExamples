import Adwaita

struct ToolbarView: View {

    @State private var about = false
    var app: AdwaitaApp
    var window: AdwaitaWindow
    var isRegistered: Binding<Bool>? = nil
    var showingAddContact: Binding<Bool>? = nil
    var showingCreateChannel: Binding<Bool>? = nil

    var view: Body {
        HeaderBar {
            if let isRegistered, isRegistered.wrappedValue {
                Button("Sign Out") {
                    isRegistered.wrappedValue = false
                }
            }
        } end: {
            if let showingAddContact, isRegistered?.wrappedValue == true {
                Button(icon: .default(icon: .listAdd)) {
                    showingAddContact.wrappedValue = true
                }
            }
            if let showingCreateChannel, isRegistered?.wrappedValue == true {
                Button("New Channel") {
                    showingCreateChannel.wrappedValue = true
                }
            }
            Menu(icon: .default(icon: .openMenu)) {
                MenuButton(Loc.newWindow, window: false) {
                    app.addWindow("main")
                }
                .keyboardShortcut("n".ctrl())
                MenuButton(Loc.closeWindow) {
                    window.close()
                }
                .keyboardShortcut("w".ctrl())
                MenuSection {
                    MenuButton(Loc.about, window: false) {
                        about = true
                    }
                }
            }
            .primary()
            .tooltip(Loc.mainMenu)
            .aboutDialog(
                visible: $about,
                app: "PQSDemoApp",
                developer: "NeedleTails",
                version: "demo",
                icon: .custom(name: "com.needletails.PQSDemoApp"),
                website: .init(string: "https://needletails.com")!,
                issues: .init(string: "https://github.com/needletails/post-quantum-solace/issues")!
            )
        }
        .headerBarTitle {
            Text("Post Quantum Solace")
        }
    }

}
