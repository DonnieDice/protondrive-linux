🐧 ProtonDrive Linux

Fast, lightweight, and unofficial desktop GUI client for Proton Drive on Linux. Built with Tauri and Rust for a native-performance experience.

This repository contains the source code for the Proton Drive Linux Desktop Client, a secure and private file storage solution for your desktop. Built with a focus on privacy and user control, this application leverages the power of Tauri to deliver a native desktop experience by integrating the official Proton Drive web client.


## Table of Contents

- [Features](#features)
- [Technologies Used](#technologies-used)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Setup](#setup)
  - [Development](#development)
  - [Building for Production](#building-for-production)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

*   **Secure Proton Drive Integration:** Access your encrypted Proton Drive files directly from your Linux desktop.
*   **Native Desktop Experience:** Built with Tauri for seamless integration with your Linux desktop environment.
*   **Multiple Distribution Formats:** Install via deb, rpm, AppImage, Snap, or Flatpak for compatibility with any Linux distribution.
*   **Privacy-Focused:** Leverages Proton's commitment to privacy and end-to-end encryption.

## Technologies Used

The Proton Drive Linux Desktop Client is a hybrid application combining:

*   **Tauri (v2):** A lightweight framework for building native desktop applications, providing the shell for the web client.
*   **Rust:** Powers the secure backend and native functionalities of the Tauri application.
*   **Node.js:** Used for project scripting, dependency management, and building the web client.
*   **Yarn:** For managing JavaScript dependencies within the `WebClients` module.
*   **Python:** Utilized for dependency patching (`fix_deps.py`).
*   **WebClients (Submodule):** Contains the Proton Drive web application that is embedded within the Tauri shell.

## Prerequisites

Before you begin, ensure you have the following installed on your system:

*   **Node.js (LTS version recommended):**
    ```bash
    node --version
    ```
*   **Rust and Cargo:**
    ```bash
    rustc --version
    cargo --version
    ```
    You can install Rust using `rustup`: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
*   **System Build Dependencies:** The `setup.sh` script will attempt to install these, but manual installation may be required depending on your Linux distribution. These typically include `build-essential`, `libssl-dev`, `pkg-config`, `webkit2gtk` development libraries, and `librsvg2` development libraries.

## Getting Started

Follow these instructions to get a copy of the project up and running on your local machine for development and testing purposes.

### Setup

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/DonnieDice/protondrive-linux.git
    cd protondrive-linux
    ```
2.  **Run the Setup Script:**
    This script will install necessary system dependencies (requires `sudo`), initialize Git submodules, and install Node.js dependencies.
    ```bash
    ./scripts/setup.sh
    ```
    *   **Note:** If `scripts/setup.sh` encounters issues installing system dependencies, please refer to your distribution's documentation for installing development tools, `libssl-dev`, `pkg-config`, `webkit2gtk` development libraries, and `librsvg2` development libraries.

### Development

To start the application in development mode with live reloading:

```bash
npm run dev
```

This will build the web client and then launch the Tauri application.

### Building for Production

To create production-ready builds of the application:

1.  **Full Build (Web Client + Tauri App):**
    ```bash
    npm run build
    ```
    This command will first build the `WebClients` module and then compile the Tauri application into an executable.

2.  **Build Web Client Only:**
    If you only need to build the embedded web application without compiling the desktop client:
    ```bash
    npm run build:web
    ```

3.  **Linux Distribution Packages:**
    Build packages for specific Linux distributions:

    *   **DEB Package (Debian/Ubuntu):**
        ```bash
        npm run build:deb
        ```
    *   **RPM Package (Fedora/Red Hat/CentOS):**
        ```bash
        npm run build:rpm
        ```
    *   **AppImage (Universal Linux):**
        ```bash
        npm run build:appimage
        ```

    Built packages will be located in the `src-tauri/target/release/bundle/` directory.

4.  **Available Distribution Channels:**

    The application is available across all major Linux distribution channels:

    **Direct Package Managers:**
    *   **Debian/Ubuntu** - Install DEB package
        ```bash
        sudo apt install proton-drive_*.deb
        ```
    *   **Fedora/RHEL/CentOS** - Install RPM package
        ```bash
        sudo dnf install proton-drive-*.rpm
        ```
    *   **Arch Linux (AUR)** - Build from AUR
        ```bash
        yay -S proton-drive
        ```

    **Container/Sandboxed Formats:**
    *   **Snap** - Available in Snapcraft store
        ```bash
        sudo snap install proton-drive
        ```
    *   **Flatpak** - Available in Flathub
        ```bash
        flatpak install flathub com.proton.drive
        ```

    **Universal Format:**
    *   **AppImage** - Download and run anywhere
        ```bash
        chmod +x proton-drive-*.AppImage
        ./proton-drive-*.AppImage
        ```

    **Fedora Community:**
    *   **COPR** - Fedora Community Build System
        ```bash
        sudo dnf copr enable donniedice/proton-drive
        sudo dnf install proton-drive
        ```

    These are automatically built and published when a new version is tagged.

## Troubleshooting

### White Screen / EGL Error on AppImage

If you see a white screen or get an error like:
```
Could not create default EGL display: EGL_BAD_PARAMETER. Aborting...
```

This is a **known upstream WebKitGTK bug** ([WebKit bug #280239](https://bugs.webkit.org/show_bug.cgi?id=280239)) affecting WebKitGTK versions newer than 2.44. It primarily impacts:
- Arch Linux / Manjaro
- Fedora 40+
- Systems with AMD GPUs on Wayland

**Solutions (in order of recommendation):**

1. **Use Flatpak instead** (Recommended)
   ```bash
   flatpak install proton-drive.flatpak
   ```
   Flatpak bundles its own WebKitGTK runtime and is not affected by this bug.

2. **Try environment variables** (may work on some systems)
   ```bash
   WEBKIT_DISABLE_DMABUF_RENDERER=1 ./proton-drive*.AppImage
   ```
   Or with additional flags:
   ```bash
   GDK_GL=disable WEBKIT_DISABLE_DMABUF_RENDERER=1 ./proton-drive*.AppImage
   ```

3. **Downgrade WebKitGTK** (Arch/Manjaro)
   ```bash
   sudo pacman -U /var/cache/pacman/pkg/webkit2gtk-4.1-2.44*
   ```
   Note: This may break other applications and is not recommended long-term.

**Why this happens:** The AppImage format uses your system's WebKitGTK libraries. If your system has a buggy version, the AppImage will be affected. Flatpak avoids this by bundling its own libraries.

### Application Stuck on Loading Screen

If the app loads but gets stuck on the Proton loading screen:
- Check your internet connection
- The app requires network access to reach Proton's servers
- Try restarting the application

## Contributing

We welcome contributions! Please refer to `CONTRIBUTING.md` for guidelines on how to contribute to this project.

## License

This project is licensed under the AGPL-3.0 License - see the [LICENSE](LICENSE) file for details.
