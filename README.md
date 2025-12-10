# ProtonDrive Linux Client

## Zero-Trust Privacy and Local Encryption

The ProtonDrive Linux client is built with a **zero-trust privacy philosophy**, ensuring that your data remains encrypted even on your local machine. This means:
- **All local data is encrypted**: Your database, cache, and temporary files are always encrypted using strong cryptographic standards.
- **No plaintext leakage**: Sensitive information like filenames or file content is never stored in plaintext on disk or in logs.
- **Enhanced security**: Even if an attacker gains access to your local filesystem, they will find only encrypted data.

## **Migration Note: Pivot to Go/Fyne Stack**

This project has undergone a significant architectural pivot from a TypeScript/Electron stack to a Go/Fyne stack. This change was made to leverage Go's performance, concurrency features, and the existing Proton-API-Bridge for a more efficient and native Linux client experience.

## Core Features
- **Two-way File Synchronization**: Seamlessly sync files between your local machine and ProtonDrive.
- **End-to-End Encryption**: Leverage ProtonDrive's secure E2E encryption for cloud storage.
- **Local Data Encryption**: All local data (database, cache, temporary files) is encrypted, ensuring zero-trust privacy.
- **Selective Sync**: Choose specific folders to sync.
- **Conflict Resolution**: Handle file conflicts intelligently.
- **Offline Mode Support**: Access and modify files offline, with changes syncing once online.
- **Native GUI**: A fast, responsive, and native user interface built with Fyne.

## **Go/Fyne Stack**

This project is built using the Go programming language and the Fyne GUI toolkit. It leverages several key libraries to interact with ProtonDrive and manage local data.

### Dependencies

-   **[Proton-API-Bridge](https://github.com/henrybear327/Proton-API-Bridge)**: A Go library that provides a bridge to interact with the ProtonDrive API, handling authentication, encryption, and file transfers.
-   **[Fyne](https://fyne.io/)**: A cross-platform GUI toolkit for Go, used to build the native user interface.
-   **[go-sqlcipher/v4](https://github.com/mutecomm/go-sqlcipher/v4)**: A Go driver for SQLCipher, providing encrypted SQLite database storage for local metadata.
-   **[testify](https://github.com/stretchr/testify)**: A set of Go test assertion libraries, used for writing more expressive and readable tests.

### Build Instructions

To build the project:

1.  **Install Go**: If you don't have Go installed, follow the official instructions: [https://golang.org/doc/install](https://golang.org/doc/install)
2.  **Clone the repository**:
    ```bash
    git clone https://github.com/yourusername/protondrive-linux.git
    cd protondrive-linux
    ```
3.  **Download dependencies**:
    ```bash
    go mod tidy
    ```
4.  **Build the application**:
    ```bash
    go build -o protondrive-linux
    ```

### Run the application

```bash
./protondrive-linux
```

### Development

To run tests:

```bash
go test ./...
```
