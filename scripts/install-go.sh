#!/bin/bash
GO_VERSION="1.22.1"
GO_URL="https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"

echo "Downloading Go ${GO_VERSION}..."
curl -L -o go.tar.gz ${GO_URL}

echo "Extracting Go to /usr/local..."
# This may require sudo privileges
tar -C /usr/local -xzf go.tar.gz

rm go.tar.gz

echo "Go ${GO_VERSION} has been installed to /usr/local/go"
echo "To complete the installation, you need to add Go to your PATH."
echo "Please run the following command or add it to your shell's startup file (e.g., ~/.bashrc, ~/.zshrc):"
echo "export PATH=\$PATH:/usr/local/go/bin"
