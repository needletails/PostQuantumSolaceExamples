<p align="center">
  <img width="256" alt="PQS Demo App Icon" src="data/icons/com.needletails.PQSDemoApp.svg">
  <h1 align="center">PQS Demo App</h1>
</p>

_PQS Demo App_ is a template application for the [Adwaita for Swift package](https://adwaita-swift.aparoksha.dev/documentation/adwaita/).

## Table of Contents

- [Installation](#Installation)
- [Configuration](#Configuration)
- [Usage](#Usage)
- [Thanks](#Thanks)

## Installation

Install the [GNOME Builder](https://flathub.org/apps/org.gnome.Builder) IDE.

For designing an app icon, [App Icon Preview](https://flathub.org/apps/org.gnome.design.AppIconPreview) and [Inkscape](https://flathub.org/apps/org.inkscape.Inkscape) are recommended.

> [!NOTE]
> You do not have to install any dependencies of Adwaita for Swift, including Swift, on your system.
> The PQS Demo App runs in a [Flatpak](https://flatpak.org/).
> The GNOME Builder will automatically download dependencies from [Flathub](https://flathub.org).
> You can also use [Visual Studio Code](https://code.visualstudio.com/) with a Docker [dev container](https://code.visualstudio.com/docs/devcontainers/containers) hosting the Swift toolchain and Adwaita libraries.

## Configuration

Before testing the application, you **MUST** update the following configuration settings to match your testing environment:

### Required Configuration Changes

#### 1. Server Configuration (`Sources/Configuration/AppConfiguration.swift`)
Update the server endpoints to point to your testing servers:

```swift
struct Server {
    static let host = "{your-host-name}.local"  // ← Change to your server hostname/IP
    static let port: Int = 6667                 // ← Update if using different port
    static let enableTLS = false                // ← Set to true if using TLS
    // ... other settings
}

struct API {
    static let baseURL = "http://{your-host-name}.local:8080"  // ← Change to your API server
    // ... other settings
}
```

#### 2. Bundle Identifiers
Replace `com.needletails.PQSDemoApp` with your own bundle identifier throughout the project:

**Files to update:**
- `com.needletails.PQSDemoApp.json` (Flatpak manifest)
- `data/com.needletails.PQSDemoApp.metainfo.xml` (Application metadata)
- `data/com.needletails.PQSDemoApp.desktop` (Desktop entry)
- Icon files in `data/icons/` directory (rename files and update references)

**Example:** Replace `com.needletails.PQSDemoApp` with `com.yourcompany.PQSDemoApp`

#### 3. Application Metadata
Update application information in these files:

**`data/com.needletails.PQSDemoApp.metainfo.xml`:**
- `<id>` - Must match your bundle identifier
- `<name>` - Your application name
- `<summary>` - Brief description
- `<description>` - Detailed description

**`data/com.needletails.PQSDemoApp.desktop`:**
- `Name=` - Display name for the application
- `Comment=` - Brief description
- `Icon=` - Must match your bundle identifier

#### 4. Development Team Settings
If you plan to distribute the application:
- Update developer information in metadata files
- Configure proper signing certificates for Flatpak distribution
- Update license information if needed

### Configuration Checklist

Before building and running the application, ensure you have:

- [ ] Updated server hostnames/IPs in `AppConfiguration.swift`
- [ ] Replaced all instances of `com.needletails.PQSDemoApp` with your bundle identifier
- [ ] Renamed all icon files to match your bundle identifier
- [ ] Updated application name and description in metadata files
- [ ] Configured correct server ports and TLS settings
- [ ] Set up your testing server environment

> [!IMPORTANT]
> **Critical:** The application will not connect to servers or function properly without updating the server configuration. The placeholder values `{your-host-name}.local` must be replaced with actual server addresses.

> [!WARNING]
> **Bundle Identifier Conflicts:** Using the default `com.needletails.PQSDemoApp` identifier may cause conflicts if multiple testers are using the same system. Always use a unique identifier for your testing environment.

## Usage

1. Open this project in the GNOME Builder. It will start downloading the dependencies.
    - GNOME Builder will start downloading dependencies when opened.
    - For Visual Studio Code, enable the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers), the [Swift extension](https://marketplace.visualstudio.com/items?itemName=sswg.swift-lang) and the [CodeLLDB extension](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb) and reopen the project window with the dev container. It may take a couple minutes to build.
2. Build and run the application.
    - For GNOME Builder, use the "run" icon in the toolbar.
    - For Visual Studio Code, select the "run and debug" tab in the leftmost sidebar, and then tap the run icon next to "Debug PQSDemoApp".
3. Change the app's name and other information about the application in the following files (and file names):
    - `README.md`
    - `Package.swift`
    - `com.needletails.PQSDemoApp.json`
    - `Sources/PQSDemoApp.swift`
    - `data/com.needletails.PQSDemoApp.metainfo.xml`
    - `data/com.needletails.PQSDemoApp.desktop`
    - `data/icons/com.needletails.PQSDemoApp.Source.svg`
    - `data/icons/com.needletails.PQSDemoApp.svg`
    - `data/icons/com.needletails.PQSDemoApp-symbolic.svg`
4. Edit the code. Help is available [here](https://adwaita-swift.aparoksha.dev/), ask questions in the [forums](https://forums.aparoksha.dev/).
5. You can edit the app's icons using the previously installed tools according to [this](https://blogs.gnome.org/tbernard/2019/12/30/designing-an-icon-for-your-app/) tutorial.
6. In GNOME Builder, click on the dropdown next to the hammer and then on `Export`. Wait until the file manager appears, open the `.flatpak` file and install the app on your device!
7. If you want to publish your app, replace `debug` in the following build commands by `release`:
```
"swift build -c debug --static-swift-stdlib",
"install -Dm755 .build/debug/PQSDemoApp /app/bin/PQSDemoApp",
```

### Flatpak SPM Generator

If you want to e.g. publish your app on Flathub where no internet connection is allowed while running the build commands,
you can use [this tool](https://github.com/flatpak/flatpak-builder-tools/tree/master/spm) that lets you generate a Flatpak manifest JSON from a Swift package.

## Thanks

### Dependencies
- [Adwaita for Swift](https://git.aparoksha.dev/aparoksha/adwaita-swift) licensed under the [MIT License](https://git.aparoksha.dev/aparoksha/adwaita-swift/src/branch/main/LICENSE.md)
- [Localized](https://git.aparoksha.dev/aparoksha/localized) licensed under the [MIT License](https://git.aparoksha.dev/aparoksha/localized/src/branch/main/LICENSE.md)
