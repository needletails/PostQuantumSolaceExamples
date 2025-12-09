import SwiftUI

// MARK: - Cross‑platform symbol helpers

extension Image: @retroactive Hashable {
    
    public nonisolated func hash(into hasher: inout Hasher) {
        // Use the image's textual description for a stable hash.
        hasher.combine(String(describing: self))
    }
    
    public nonisolated static func == (lhs: Image, rhs: Image) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}

// MARK: - App‑specific images used in Skip demo

extension Image {
    /// App logo used on the registration screen.
    /// Requires a `logo` image in `Module.xcassets`.
    static var appLogo: Self {
        .init("post_quantum_solace", bundle: .module)
    }
    
    /// "Add contact" person+ badge icon on the register button.
    static var appRegisterPersonBadgePlus: Self {
    #if os(Android)
        // SVG/asset name you provide on Android.
        .init("person_add_person_add_fill1_symbol", bundle: .module)
    #else
        .init(systemName: "person.badge.plus")
    #endif
    }
    
    /// Empty state icon for "No Contacts or Channels".
    static var appEmptyContacts: Self {
    #if os(Android)
        .init("group_group_fill1_symbol", bundle: .module)
    #else
        .init(systemName: "person.2")
    #endif
    }
    
    /// Toolbar "+" for adding a contact.
    static var appToolbarAddContact: Self {
    #if os(Android)
        .init("add_add_fill1_symbol", bundle: .module)
    #else
        .init(systemName: "plus")
    #endif
    }
    
    /// Back chevron in the create‑channel navigation bar.
    static var appBackChevron: Self {
    #if os(Android)
        .init("arrow_back_ios_new_arrow_back_ios_new_fill1_symbol", bundle: .module)
    #else
        .init(systemName: "chevron.left")
    #endif
    }
    
    /// Magnifying glass icon in the create‑channel search bar.
    static var appSearch: Self {
    #if os(Android)
        .init("search_search_fill1_symbol", bundle: .module)
    #else
        .init(systemName: "magnifyingglass")
    #endif
    }
    
    /// Clear‑search "x" icon in the search bar.
    static var appClearSearch: Self {
    #if os(Android)
        .init("x_circle_x_circle_fill1_symbol", bundle: .module)
    #else
        .init(systemName: "xmark.circle.fill")
    #endif
    }
    
    /// Empty contacts icon used in create‑channel list when there are no contacts.
    static var appEmptyContactsSlash: Self {
    #if os(Android)
        .init("group_off_group_off_fill1_symbol", bundle: .module)
    #else
        .init(systemName: "person.2.slash")
    #endif
    }
    
    /// Checkmark used in contact selection rows.
    static var appCheckmark: Self {
    #if os(Android)
        .init("check_check_fill1_symbol", bundle: .module)
    #else
        .init(systemName: "checkmark")
    #endif
    }
}


