### Post-Quantum Solace Examples

![Post Quantum Solace Banner](Apple/PostQuantumSolaceDemo/post_quantum_solace%20copy@3x.png)

[![Apple Platforms](https://img.shields.io/badge/Apple-iOS%20%7C%20macOS-000000?logo=apple&logoColor=white)](#apple-postquantumsolacedemo)
[![Android](https://img.shields.io/badge/Android-%20-3DDC84?logo=android&logoColor=white)](#skip-cross--platform-demo)
[![Linux](https://img.shields.io/badge/Linux-%20-FCC624?logo=linux&logoColor=black)](#servers)
[![GNOME](https://img.shields.io/badge/GNOME-desktop-4A86CF?logo=gnome&logoColor=white)](#servers)

A collection of runnable examples showcasing end-to-end, post-quantum–ready messaging using Solace and NeedleTails components across Apple (iOS, macOS), Android (via Skip), and Linux/desktop (including GNOME).

---

### What's inside
- **Apple/PostQuantumSolaceDemo**: SwiftUI demo app for iOS and macOS using local Swift packages and remote dependencies.
- **Skip/post-quantum-solace-skip-demo**: Cross-platform app powered by [Skip](https://skip.tools) that targets iOS and Android from a shared Swift codebase.
- **Servers**:
  - `pqs-server`: Core server components (WebSocket + controllers) as Swift packages.
  - `pqs-irc-server`: IRC-compatible server components as Swift packages.

> Note: This repo is structured for learning and experimentation—each project is intentionally small and focused.

---

### Repository layout
- `Apple/PostQuantumSolaceDemo` – Xcode app project and Swift sources
- `Servers/pqs-server` – Swift package (executable + library: `PQSServerCore`)
- `Servers/pqs-irc-server` – Swift package (executable + library: `PQSIRCCore`)
- `Skip/post-quantum-solace-skip-demo` – Skip workspace targeting iOS + Android

---

### Quick start

#### Apple: PostQuantumSolaceDemo
- Open `Apple/PostQuantumSolaceDemo/PostQuantumSolaceDemo.xcodeproj` in Xcode 16+
- Select your destination (iOS Simulator or macOS)
- Configure signing locally if prompted
- Build & run

#### Skip: Cross‑platform demo
- Requirements: Homebrew, Java (for Android SDK), and `skip`
- Open `Skip/post-quantum-solace-skip-demo/Darwin/PostQuantumSolaceSkipDemo.xcodeproj` for Apple targets
- For Android, build via the included Gradle wrapper from the `Android/` directory

#### Gnome(Adwaita): Gnome demo

#### Servers (Linux/macOS)
- Requirements: Swift 6+
- Example run (pqs-server):
  - `cd Servers/pqs-server && swift run pqs-server`
- Example run (pqs-irc-server):
  - `cd Servers/pqs-irc-server && swift run pqs-irc-server`

### License
The MIT License in this repository applies to the Example applications and demo code only. See `LICENSE` for full text. Components or dependencies located in `Servers/` or fetched via Swift Package Manager may have their own licenses; review those individually.
