# ProtonDrive Linux Client

## **Migration Note: Pivot to Go/Fyne Stack**

This project has undergone a significant architectural pivot from a TypeScript/Electron stack to a Go/Fyne stack. This change was made to leverage Go's performance, concurrency features, and the existing Proton-API-Bridge for a more efficient and native Linux client experience.

## **Go/Fyne Stack**

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
