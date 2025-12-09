# Post-Quantum Solace Examples

<div align="center">
  <img width="400" alt="Post-Quantum Solace Logo" src="Apple/PostQuantumSolaceDemo/post_quantum_solace%20copy@3x.png">
  <h2>End-to-End Post-Quantum Secure Messaging</h2>
</div>

[![Apple Platforms](https://img.shields.io/badge/Apple-iOS%20%7C%20macOS-000000?logo=apple&logoColor=white)](#apple-postquantumsolacedemo)
[![Android](https://img.shields.io/badge/Android-%20-3DDC84?logo=android&logoColor=white)](#skip-cross--platform-demo)
[![Linux](https://img.shields.io/badge/Linux-%20-FCC624?logo=linux&logoColor=black)](#servers)
[![GNOME](https://img.shields.io/badge/GNOME-desktop-4A86CF?logo=gnome&logoColor=white)](#gnome-demo)

## 🎯 Purpose

This repository demonstrates the **[PostQuantumSolace SDK](https://github.com/needletails/post-quantum-solace)** - a complete end-to-end encrypted messaging system designed to be resistant to quantum computer attacks. These examples were created specifically to showcase how to integrate and use the PostQuantumSolace SDK across multiple platforms and transport mechanisms.

### What is Post-Quantum Solace?

The **PostQuantumSolace SDK** is a messaging framework that provides:
- **🔐 Post-Quantum Cryptography**: Uses cryptographic algorithms resistant to quantum computer attacks
- **🔄 Double Ratchet Protocol**: Implements forward secrecy and post-compromise security
- **📱 Cross-Platform Support**: Native apps for iOS, macOS, Android, and Linux/GNOME
- **🌐 Multiple Transport Mechanisms**: Demonstrates both WebSocket and IRC protocols for message delivery
- **⚡ Real-Time Messaging**: WebSocket-based communication with instant message delivery
- **📡 IRC Integration**: IRC-compatible server for existing infrastructure compatibility
- **👥 Contact Management**: Secure contact discovery and friendship management
- **🔒 Zero-Knowledge Architecture**: Server doesn't store message content or user keys

## 📱 Projects Overview

These examples demonstrate **PostQuantumSolace SDK integration** across different platforms and use cases:

### Client Applications

#### 🍎 Apple/PostQuantumSolaceDemo
**Native iOS and macOS messaging app using PostQuantumSolace SDK**
- **Platform**: iOS 16+, macOS 13+
- **Framework**: SwiftUI with native Swift packages
- **SDK Integration**: Direct integration with PostQuantumSolace SDK
- **Features**: 
  - User registration with secret names
  - Contact management and discovery
  - Real-time encrypted messaging
  - Post-quantum cryptographic key exchange
- **Purpose**: Demonstrates native Apple platform integration with PostQuantumSolace SDK

#### 🤖 Skip/post-quantum-solace-skip-demo  
**Cross-platform iOS and Android app using PostQuantumSolace SDK**
- **Platform**: iOS 16+, Android API 24+
- **Framework**: [Skip](https://skip.tools) for shared Swift codebase
- **SDK Integration**: PostQuantumSolace SDK via Skip framework
- **Features**:
  - Single codebase targeting both iOS and Android
  - Native UI components on each platform
  - Full PostQuantumSolace SDK functionality
- **Purpose**: Shows how to integrate PostQuantumSolace SDK in cross-platform apps

#### 🐧 Gnome/post-quantum-solace-gnome-demo-app
**Linux desktop messaging app using PostQuantumSolace SDK**
- **Platform**: Linux with GNOME desktop
- **Framework**: Adwaita for Swift (GTK4)
- **SDK Integration**: Direct integration with PostQuantumSolace SDK
- **Features**:
  - Native GNOME desktop integration
  - Flatpak distribution ready
  - Complete PostQuantumSolace SDK client
- **Purpose**: Demonstrates PostQuantumSolace SDK integration on Linux desktop

### Server Infrastructure

> **Important**: The server implementations (`pqs-server` and `pqs-irc-server`) are **independent of the PostQuantumSolace SDK**. They serve as reference implementations demonstrating how to build servers that can work with PostQuantumSolace clients, but they are not part of the core SDK.

#### 🌐 Servers/pqs-server
**WebSocket transport messaging server**
- **Tech Stack**: 
  - **[Hummingbird](https://github.com/hummingbird-project/hummingbird)**: Swift web framework for HTTP/WebSocket server
  - **[HummingbirdWebSocket](https://github.com/hummingbird-project/hummingbird-websocket)**: WebSocket implementation with compression support
  - **[HummingbirdHTTP2](https://github.com/hummingbird-project/hummingbird)**: HTTP/2 support
  - **[HummingbirdRouter](https://github.com/hummingbird-project/hummingbird)**: REST API routing
  - **[Swift Crypto](https://github.com/apple/swift-crypto)**: Cryptographic operations
  - **[BSON](https://github.com/OpenKitten/BSON)**: Binary JSON for data serialization
- **Transport Protocol**: WebSocket-based real-time communication
- **Features**:
  - User registration and authentication
  - Message routing and delivery via WebSocket connections
  - Contact discovery services
  - Zero-knowledge architecture (no message storage)
  - REST API endpoints for additional operations
- **Purpose**: Demonstrates WebSocket as a transport mechanism for PQS messaging

#### 📡 Servers/pqs-irc-server  
**IRC transport messaging server**
- **Tech Stack**:
  - **[SwiftNIO](https://github.com/apple/swift-nio)**: High-performance networking framework
  - **[NIOSSL](https://github.com/apple/swift-nio-ssl)**: TLS/SSL support for secure connections
  - **[NeedleTailIRC](https://github.com/needletails/needletail-irc)**: IRC protocol implementation
  - **[ConnectionManagerKit](https://github.com/needletails/connection-manager-kit)**: Connection management and event handling
  - **[Swift Crypto](https://github.com/apple/swift-crypto)**: Cryptographic operations
- **Transport Protocol**: IRC protocol with PQS cryptographic extensions
- **Features**:
  - Standard IRC commands and channels
  - Post-quantum encrypted private messages over IRC
  - Backward compatibility with existing IRC clients
  - IRC as transport layer for secure messaging
  - Multi-threaded event loop for high concurrency
- **Purpose**: Demonstrates IRC as an alternative transport mechanism for PQS messaging

---

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   iOS/macOS     │    │   Android       │    │   Linux/GNOME   │
│   SwiftUI App   │    │   Skip App      │    │   Adwaita App   │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌─────────────┴─────────────┐
                    │   Transport Layer         │
                    │  ┌─────────────────────┐  │
                    │  │   WebSocket Server   │  │
                    │  │  (Real-time PQS)     │  │
                    │  └─────────────────────┘  │
                    │  ┌─────────────────────┐  │
                    │  │    IRC Server       │  │
                    │  │  (IRC + PQS Ext.)   │  │
                    │  └─────────────────────┘  │
                    └───────────────────────────┘
```

### Transport Mechanisms

This repository demonstrates **two distinct transport mechanisms** for post-quantum secure messaging:

#### 🌐 **WebSocket Transport** (`pqs-server`)
- **Protocol**: WebSocket over HTTP/HTTPS
- **Client Packages**: [`ConnectionManagerKit`](https://github.com/needletails/connection-manager-kit) (WebSocket client management)
- **Server Packages**: [`HummingbirdWebSocket`](https://github.com/hummingbird-project/hummingbird-websocket) (WebSocket server implementation)
- **Use Case**: Modern web applications, mobile apps, real-time communication
- **Benefits**: 
  - Low latency, bidirectional communication
  - Built-in connection management
  - Easy integration with web technologies
  - REST API for additional operations

#### 📡 **IRC Transport** (`pqs-irc-server`)
- **Protocol**: Internet Relay Chat (IRC) with cryptographic extensions
- **Client Packages**: [`NeedleTailIRC`](https://github.com/needletails/needletail-irc) (IRC protocol implementation), [`ConnectionManagerKit`](https://github.com/needletails/connection-manager-kit) (connection management)
- **Server Packages**: [`NeedleTailIRC`](https://github.com/needletails/needletail-irc) (IRC server implementation)
- **Use Case**: Legacy system integration, existing IRC infrastructure
- **Benefits**:
  - Backward compatibility with IRC clients
  - Leverages existing IRC server infrastructure
  - Channel-based communication support
  - Familiar protocol for many developers

### Key Components
- **[PostQuantumSolace](https://github.com/needletails/post-quantum-solace)**: Quantum-resistant encryption sessions
- **[Double Ratchet](https://github.com/needletails/double-ratchet-kit)**: Double Ratchet Mechanism with Quantum Resistance Capabilities
- **[NeedleTailIRC](https://github.com/needletails/needletail-irc)**: IRC protocol handling and transport layer
- **[ConnectionManagerKit](https://github.com/needletails/connection-manager-kit)**: Unified connection management for both WebSocket and IRC transports
- **[HummingbirdWebSocket](https://github.com/hummingbird-project/hummingbird-websocket)**: WebSocket server implementation
- **Transport Abstraction**: Unified interface supporting multiple transport mechanisms

---

### Repository layout
- `Apple/PostQuantumSolaceDemo` – Xcode app project and Swift sources
- `Servers/pqs-server` – Swift package (executable + library: `PQSServerCore`)
- `Servers/pqs-irc-server` – Swift package (executable + library: `PQSIRCCore`)
- `Skip/post-quantum-solace-skip-demo` – Skip workspace targeting iOS + Android

---

## 🚀 Quick Start

### Prerequisites
- **Swift 6+** (for all projects)
- **Xcode 16+** (for Apple projects)
- **GNOME Builder** (for GNOME project)
- **Java/JDK** (for Android builds)

### Running Client Applications

#### 🍎 Apple Demo (iOS/macOS)
```bash
# Open in Xcode
open Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo.xcodeproj

# Select target (iOS Simulator or macOS)
# Build and run (⌘+R)
```

#### 🤖 Skip Cross-Platform Demo
```bash
# For iOS/macOS
open Skip/post-quantum-solace-skip-demo/Darwin/PostQuantumSolaceSkipDemo.xcodeproj

# For Android
cd Skip/post-quantum-solace-skip-demo/Android
./gradlew assembleDebug
```

#### 🐧 GNOME Desktop Demo
```bash
# Install GNOME Builder
# Open project in GNOME Builder
# Build and run from IDE

# Or build manually
cd Gnome/post-quantum-solace-gnome-demo-app
flatpak-builder build com.needletails.PQSDemoApp.json
```

### Running Server Infrastructure

#### 🌐 Core PQS Server
```bash
cd Servers/pqs-server
swift run pqs-server
# Server runs on localhost:8080 (WebSocket + REST API)
```

#### 📡 IRC-Compatible Server
```bash
cd Servers/pqs-irc-server  
swift run pqs-irc-server
# Server runs on localhost:6667 (IRC protocol)
```

### Configuration Required

⚠️ **Important**: Before running any client application, you must configure:

1. **Server endpoints** in `Sources/Configuration/AppConfiguration.swift`
2. **Bundle identifiers** (replace `com.needletails.PQSDemoApp`)
3. **Application metadata** (name, description, etc.)

See individual project READMEs for detailed configuration instructions.

---

## 🔐 Security Features

### Post-Quantum Cryptography
This repository uses the **PostQuantumSolace** package which implements post-quantum cryptographic algorithms. The specific algorithms and their implementation details, including the **PQXDH** (Post-Quantum Extended Diffie-Hellman) key exchange protocol, can be found in the `postquantumsolace` package.

**Key Cryptographic Components:**
- **PQXDH**: Post-quantum extension of the X3DH key agreement protocol
- **Post-Quantum Key Exchange**: Quantum-resistant key establishment
- **Post-Quantum Signatures**: Quantum-resistant digital signatures
- **Hybrid Cryptography**: Combines classical and post-quantum algorithms for security

### Messaging Security
- **End-to-End Encryption**: Messages encrypted before leaving device
- **Forward Secrecy**: Past messages remain secure if keys are compromised
- **Post-Compromise Security**: System recovers from key compromise
- **Perfect Forward Secrecy**: Each message uses unique encryption keys
- **Zero-Knowledge Architecture**: Servers cannot read message content

### Privacy Features
- **Secret Names**: Users identified by chosen names, not real identities
- **No Message Storage**: Servers don't store message content
- **Contact Discovery**: Secure method to find and add contacts
- **Metadata Protection**: Minimal metadata exposure

---

## 📚 Learning Resources

This repository is designed for:
- **Developers** learning post-quantum cryptography implementation
- **Security Researchers** studying quantum-resistant protocols
- **Students** understanding end-to-end encryption systems
- **Organizations** evaluating post-quantum messaging solutions

### Key Learning Areas
- **PostQuantumSolace SDK Integration**: How to integrate the core SDK into applications
- **Server Architecture Patterns**: Building servers that work with PostQuantumSolace clients
- **Transport Mechanism Implementation**: WebSocket vs IRC transport layers
- **Cross-Platform Development**: Native iOS, Android, and Linux implementations
- **Zero-Knowledge Server Design**: Server patterns that don't store message content
- **Protocol Abstraction**: Supporting multiple transport mechanisms
- **Reference Implementation Study**: Understanding how to build compatible servers

> **Note**: The server implementations serve as **reference examples** showing how to build servers compatible with PostQuantumSolace clients, but they are not part of the core SDK.

---

## 📄 License

The MIT License in this repository applies to the example applications and demo code only. See `LICENSE` for full text. 

**Note**: Components or dependencies located in `Servers/` or fetched via Swift Package Manager may have their own licenses; review those individually.

---

## 💖 Sponsor Us

Support the development of Post-Quantum Solace and other NeedleTails projects!

**NeedleTails** is dedicated to building high-performance Swift applications and websites that empower users and enhance their experiences. Your sponsorship helps us:

- **Enhance Open Source Projects**: Continue improving our open-source projects, making them more robust and feature-rich
- **Develop High-Quality Software**: Maintain and enhance both open-source and proprietary software solutions
- **Invest in Research & Development**: Explore new technologies and implement best practices
- **Support Our Community**: Deliver high-quality code and create valuable educational resources

### How You Can Help

1. **🌟 Become a Sponsor**: Your financial support directly impacts our development capabilities
2. **📢 Spread the Word**: Share our projects with your network
3. **🤝 Contribute**: Provide feedback, contribute code, or report issues
4. **💬 Engage**: Follow us and join discussions

**[Support NeedleTails on GitHub Sponsors →](https://github.com/sponsors/needletails)**

---

## 🤝 Contributing

This repository serves as a reference implementation and learning resource. Contributions that improve documentation, add examples, or enhance security are welcome.

For questions or discussions about Post-Quantum Solace, please refer to the individual project documentation or create an issue in this repository.
