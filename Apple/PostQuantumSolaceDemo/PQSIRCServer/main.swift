//
//  main.swift
//  PQSIRCServer
//
//  Created by Cole M on 9/18/25.
//

import PQSIRCCore
import NeedleTailIRC
import BinaryCodable
import NeedleTailLogger
import Foundation
let logger = NeedleTailLogger("PQSIRCServer")

// Simple in-memory channel cache
actor ChannelCache {
    private var channels: [String: ChannelInfo] = [:]
    
    struct ChannelInfo {
        let packet: NeedleTailChannelPacket
        var members: Set<String>
        let created: Date
        let admin: String
    }
    
    // Create or update channel
    func createChannel(_ packet: NeedleTailChannelPacket, admin: String) {
        let channelName = packet.name.stringValue
        channels[channelName] = ChannelInfo(
            packet: packet,
            members: packet.members,
            created: Date(),
            admin: admin
        )
        logger.log(level: .info, message: "Channel cached: \(channelName) by \(admin)")
    }
    
    // Find channel by name
    func findChannel(_ channelName: String) -> ChannelInfo? {
        return channels[channelName]
    }
    
    // Check if channel exists
    func channelExists(_ channelName: String) -> Bool {
        return channels[channelName] != nil
    }
    
    // Add member to channel
    func addMember(_ channelName: String, member: String) -> Bool {
        guard var channel = channels[channelName] else {
            return false
        }
        channel.members.insert(member)
        channels[channelName] = channel
        logger.log(level: .info, message: "\(member) added to channel: \(channelName)")
        return true
    }
    
    // Remove member from channel
    func removeMember(_ channelName: String, member: String) -> Bool {
        guard var channel = channels[channelName] else {
            return false
        }
        channel.members.remove(member)
        channels[channelName] = channel
        logger.log(level: .info, message: "\(member) removed from channel: \(channelName)")
        return true
    }
    
    // Delete channel
    func deleteChannel(_ channelName: String) {
        channels.removeValue(forKey: channelName)
        logger.log(level: .info, message: "Channel deleted: \(channelName)")
    }
    
    // Get all channels
    func getAllChannels() -> [String: ChannelInfo] {
        return channels
    }
}

let channelCache = ChannelCache()

// MARK: - Channel Handlers

/// Handle JOIN command for channels (dojoin)
/// Flow: Client sends JOIN -> Server processes -> Server sends JOIN response (tags forwarded by PQSIRCCore)
///       -> Client receives JOIN response -> Client sends MODE with tags -> Server processes MODE
///       -> Server sends MODE response (tags forwarded) -> Client creates communication
func doJoin(channel: NeedleTailChannel, tags: [IRCTag]?, origin: String?) async throws {
    guard let origin = origin else {
        logger.log(level: .warning, message: "JOIN command received without origin")
        return
    }
    
    let channelName = channel.stringValue
    
    // Check if channel already exists in cache
    let exists = await channelCache.channelExists(channelName)
    
    // Extract channel packet from tags
    if let channelPacketTag = tags?.first(where: { $0.key == "channel-packet" }),
       let data = Data(base64Encoded: channelPacketTag.value) {
        do {
            let packet = try BinaryDecoder().decode(NeedleTailChannelPacket.self, from: data)
            let isCreate = tags?.contains(where: { $0.key == "create-channel" && $0.value == "true" }) ?? false
            
            if isCreate {
                // Create new channel in cache
                await channelCache.createChannel(packet, admin: packet.channelOperatorAdmin)
                logger.log(level: .info, message: "Channel created via JOIN: \(channelName)")
                // Tags (channel-packet and create-channel) will be automatically forwarded
                // back to the client in the JOIN response by PQSIRCCore
            } else if exists {
                // Join existing channel
                _ = await channelCache.addMember(channelName, member: origin)
            } else {
                // Channel doesn't exist - create it from packet
                await channelCache.createChannel(packet, admin: packet.channelOperatorAdmin)
                _ = await channelCache.addMember(channelName, member: origin)
                logger.log(level: .info, message: "Channel auto-created and joined: \(channelName)")
            }
        } catch {
            logger.log(level: .error, message: "Failed to decode channel packet: \(error)")
            // Fallback: try to join if channel exists
            if exists {
                _ = await channelCache.addMember(channelName, member: origin)
            } else {
                logger.log(level: .warning, message: "Cannot join non-existent channel: \(channelName)")
            }
        }
    } else {
        // No packet in tags - check cache first
        if exists {
            _ = await channelCache.addMember(channelName, member: origin)
        } else {
            logger.log(level: .warning, message: "Attempted to join non-existent channel: \(channelName)")
        }
    }
}

/// Handle PART command for channels (dopart)
func doPart(channels: [NeedleTailChannel], tags: [IRCTag]?, origin: String?) async throws {
    guard let origin = origin else {
        logger.log(level: .warning, message: "PART command received without origin")
        return
    }
    
    // Extract part message from tags
    var destroyChannel = false
    if let partMessageTag = tags?.first(where: { $0.key == "part-message" }),
       let data = Data(base64Encoded: partMessageTag.value) {
        do {
            let partMessage = try BinaryDecoder().decode(PartMessage.self, from: data)
            destroyChannel = partMessage.destroyChannel
        } catch {
            logger.log(level: .error, message: "Failed to decode part message: \(error)")
        }
    }
    
    // Handle each channel
    for channel in channels {
        let channelName = channel.stringValue
        
        // Check if channel exists in cache
        guard let channelInfo = await channelCache.findChannel(channelName) else {
            logger.log(level: .warning, message: "Attempted to part from non-existent channel: \(channelName)")
            continue
        }
        
        // Check if user is admin and wants to destroy
        if destroyChannel && channelInfo.admin == origin {
            await channelCache.deleteChannel(channelName)
            logger.log(level: .info, message: "Channel destroyed: \(channelName) by \(origin)")
        } else {
            // Just remove member
            _ =  await channelCache.removeMember(channelName, member: origin)
        }
    }
}

/// Handle MODE command for channels (domode)
/// Note: Tags are automatically forwarded back to the client by PQSIRCCore
func doMode(
    channel: NeedleTailChannel,
    addMode: IRCChannelPermissions?,
    addParameters: [String]?,
    removeMode: IRCChannelPermissions?,
    removeParameters: [String]?,
    tags: [IRCTag]?,
    origin: String?
) async throws {
    guard let origin = origin else {
        logger.log(level: .warning, message: "MODE command received without origin")
        return
    }
    
    let channelName = channel.stringValue
    
    // Check if this is a channel creation via MODE
    if let channelPacketTag = tags?.first(where: { $0.key == "channel-packet" }),
       let data = Data(base64Encoded: channelPacketTag.value),
       let createTag = tags?.first(where: { $0.key == "create-channel" }),
       createTag.value == "true" {
        do {
            let packet = try BinaryDecoder().decode(NeedleTailChannelPacket.self, from: data)
            
            // Verify the origin is the admin
            if packet.channelOperatorAdmin == origin {
                // Check if channel already exists
                let exists = await channelCache.channelExists(channelName)
                if exists {
                    logger.log(level: .warning, message: "Channel already exists: \(channelName)")
                } else {
                    await channelCache.createChannel(packet, admin: origin)
                    logger.log(level: .info, message: "Channel created via MODE: \(channelName) by \(origin)")
                    // Tags (including channel-packet and create-channel) will be automatically
                    // forwarded back to the client in the MODE response by PQSIRCCore
                }
            } else {
                logger.log(level: .warning, message: "Unauthorized channel creation attempt: \(channelName) by \(origin)")
            }
        } catch {
            logger.log(level: .error, message: "Failed to decode channel packet in MODE: \(error)")
        }
    } else {
        // Regular mode change - verify channel exists in cache
        if await channelCache.channelExists(channelName) {
            logger.log(level: .debug, message: "Mode change for channel \(channelName): add=\(String(describing: addMode)), remove=\(String(describing: removeMode))")
        } else {
            logger.log(level: .warning, message: "Mode change attempted on non-existent channel: \(channelName)")
        }
    }
}

// Run the server
// Note: PQSIRCCore.run() should be extended to accept handlers for dojoin, dopart, domode
// For now, this provides the handler functions that can be integrated
try await PQSIRCCore.run()
