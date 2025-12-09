//
//  CreateChannelView.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 11/27/25.
//
import SwiftUI
import SampleCore

struct CreateChannelView: View {
    
    let session: SessionManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Environment(MessageReceiverManager.self) var receiver
    @State var searchText: String = ""
    @State var isLoading: Bool = false
    @Binding var selectedContacts: Set<Contact>
    @State var showChannelNameAlert: Bool = false
    @State var channelName: String = ""
    @State var showCreateChannelFailed: Bool = false
    @State var showGroupSizeLimitAlert: Bool = false
    @State var isCreating: Bool = false
    
    private let minGroupSize = 2
    private let maxGroupSize = 1000
    
    init(
        session: SessionManager,
        selectedContacts: Binding<Set<Contact>>
    ) {
        self.session = session
        self._selectedContacts = selectedContacts
    }
    
    
    public var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            navigationBar
            
            // Search Bar
            searchBar
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
            
            // Selected Contacts Count
            selectedContactsHeader
                .padding(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            
            // Contacts List
            contactsList
            
            createButton
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        }
        .alert("Give your Channel a name!", isPresented: $showChannelNameAlert) {
            TextField("Channel Name...", text: $channelName)
            Button("Create", role: .destructive) {
                createChannel()
            }
            Button("Cancel", role: .cancel) {
                channelName = ""
            }
        }
        .alert("You cannot create a group chat with only one person", isPresented: $showCreateChannelFailed) {
            Button("OK", role: .cancel) {
                showCreateChannelFailed = false
            }
        }
        .alert("Group Size Limit", isPresented: $showGroupSizeLimitAlert) {
            Button("OK", role: .cancel) {
                showGroupSizeLimitAlert = false
            }
        } message: {
            Text("Groups are limited to \(maxGroupSize) members to ensure optimal performance and security.")
        }
    }
    
    // MARK: - Navigation Bar
    @ViewBuilder
    var navigationBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 16, weight: .medium))
                }
            }
            
            Spacer()
            
            Text("Select Contacts")
                .font(.system(size: 18, weight: .semibold))
            
            Spacer()
            
            // Placeholder for balance
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text("Back")
                    .font(.system(size: 16, weight: .medium))
            }
            .opacity(0)
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }
    
    // MARK: - Search Bar
    @ViewBuilder
    var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
            
            TextField("Search contacts...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16))
                .foregroundColor(.primary)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
    
    // MARK: - Selected Contacts Header
    @ViewBuilder
    var selectedContactsHeader: some View {
        HStack {
            Text("\(selectedContacts.count) of \(maxGroupSize) selected")
                .font(.system(size: 14, weight: .medium))
            
            Spacer()
            
            Button {
                selectedContacts.removeAll()
            } label: {
                Text("Clear")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
            }
        }
    }
    
    // MARK: - Contacts List
    @ViewBuilder
    var contactsList: some View {
        if filteredContacts.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "person.2.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
                Text(searchText.isEmpty ? "No contacts available" : "No contacts found")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredContacts) { contact in
                        ContactSelectionRow(
                            contact: contact,
                            isSelected: selectedContacts.contains(contact),
                            isDisabled: !selectedContacts.contains(contact) && selectedContacts.count >= maxGroupSize,
                            colorScheme: colorScheme
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(for: contact)
                        }
                        .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
        }
    }
    
    private var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return receiver.contacts
        } else {
            return receiver.contacts.filter { contact in
                contact.secretName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // MARK: - Create Button
    @ViewBuilder
    var createButton: some View {
        if isCreating {
            HStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Spacer()
            }
            .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
        } else {
            Button {
                if selectedContacts.count < minGroupSize {
                    showCreateChannelFailed = true
                } else if selectedContacts.count > maxGroupSize {
                    showGroupSizeLimitAlert = true
                } else {
                    showChannelNameAlert = true
                }
            } label: {
                Text("Create Group")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canCreateGroup ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!canCreateGroup)
        }
    }
    
    private var canCreateGroup: Bool {
        let count = selectedContacts.count
        return count >= minGroupSize && count <= maxGroupSize
    }
    
    // MARK: - Helper Methods
    private func createChannel() {
        guard selectedContacts.count >= minGroupSize else {
            showCreateChannelFailed = true
            return
        }
        
        guard selectedContacts.count <= maxGroupSize else {
            showGroupSizeLimitAlert = true
            return
        }
        
        guard !channelName.isEmpty else {
            return
        }
        
        isCreating = true
        
        Task {
            do {
                let contactSecretNames = selectedContacts.map { $0.secretName }
                
                // Ensure channel name starts with #
                var finalChannelName = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalChannelName.hasPrefix("#") {
                    finalChannelName = "#\(finalChannelName)"
                }
                
                guard let admin = await session.pqsSession.sessionContext?.sessionUser.secretName else {
                    print("Cannot create channel: session context not available")
                    await MainActor.run {
                        isCreating = false
                        showCreateChannelFailed = true
                    }
                    return
                }
                
                guard let channel = NeedleTailChannel(finalChannelName) else {
                    print("Invalid channel name: \(finalChannelName)")
                    await MainActor.run {
                        isCreating = false
                        showCreateChannelFailed = true
                    }
                    return
                }
                
                let packet = NeedleTailChannelPacket(
                    name: channel,
                    channelOperatorAdmin: admin,
                    channelOperators: [admin],
                    members: Set(contactSecretNames))
                try await session.joinChannel(packet, createChannel: true)
                
                await MainActor.run {
                    isCreating = false
                    channelName = ""
                    selectedContacts.removeAll()
                    dismiss()
                }
            } catch {
                print("Failed to create channel: \(error)")
                await MainActor.run {
                    isCreating = false
                }
            }
        }
    }
    
    private func toggleSelection(for contact: Contact) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedContacts.contains(contact) {
                selectedContacts.remove(contact)
            } else {
                // Check if we've reached the maximum group size
                if selectedContacts.count >= maxGroupSize {
                    showGroupSizeLimitAlert = true
                } else {
                    selectedContacts.insert(contact)
                }
            }
        }
    }
}

// MARK: - Contact Selection Row
struct ContactSelectionRow: View {
    let contact: Contact
    let isSelected: Bool
    let isDisabled: Bool
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                Text(String(contact.secretName.prefix(2)).uppercased())
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
            }
            
            // Contact Info
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.secretName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Selection Indicator
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue.opacity(0.1) : (isDisabled ? Color.gray.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}
