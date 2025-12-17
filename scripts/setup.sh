#!/bin/bash
set -e

echo "Setting up protondrive-tauri..."

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v node &> /dev/null; then
    echo "Error: Node.js not found. Install from https://nodejs.org/"
    exit 1
fi

if ! command -v rustc &> /dev/null; then
    echo "Error: Rust not found. Install from https://rustup.rs/"
    exit 1
fi

# Detect OS and install build dependencies
OS_TYPE="$(uname -s)"
case "$OS_TYPE" in
    Linux*)
        echo "Detected Linux. Installing build dependencies..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y build-essential libssl-dev pkg-config
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y gcc pkg-config openssl-devel
        elif command -v pacman &> /dev/null; then
            sudo pacman -S base-devel openssl
        else
            echo "Warning: Could not detect package manager. Please install manually:"
            echo "  - build-essential (or equivalent)"
            echo "  - libssl-dev (or openssl-devel)"
            echo "  - pkg-config"
        fi
        ;;
    Darwin*)
        echo "Detected macOS. Installing Xcode Command Line Tools..."
        xcode-select --install || true
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "Detected Windows. Please ensure Visual Studio Build Tools are installed."
        ;;
    *)
        echo "Unknown OS: $OS_TYPE"
        exit 1
        ;;
esac

# Initialize submodules
echo "Initializing git submodules..."
git submodule update --init --recursive

# Install Node dependencies
echo "Installing Node dependencies..."
npm install

echo "Setup complete! You can now run:"
echo "  npm run dev      - Start development server"
echo "  npm run build    - Build for release"
echo "  npm run build:web - Build web app only"
