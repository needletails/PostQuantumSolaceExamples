<p align="center">
  <img width="256" alt="PQS Demo App Icon" src="data/icons/com.needletails.PQSDemoApp.svg">
  <h1 align="center">PQS Demo App</h1>
</p>

_PQS Demo App_ is a template application for the [Adwaita for Swift package](https://adwaita-swift.aparoksha.dev/documentation/adwaita/).

## Table of Contents

- [Installation](#Installation)
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
