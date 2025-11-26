# ProtonDrive Linux Client

An unofficial Linux desktop client for ProtonDrive with a graphical interface, using `rclone` as the backend.

## Important Note

This repository is currently under active development. The application on the `main` branch is not functional and should not be considered stable.

Development is ongoing in the `dev` branch. Please refer to that branch for the latest progress, but be aware it is not fully working yet.

## Planned Features

- **Secure Browser-Based Authentication**: Interactive login via embedded browser to handle CAPTCHA
- **File Synchronization**: Sync local directories with ProtonDrive
- **Remote Browsing**: Browse and manage files on ProtonDrive  
- **Drive Mounting**: Mount ProtonDrive as a local filesystem
- **User-Friendly GUI**: Native Tkinter interface

## Tech Stack

- **Python** - Core application logic
- **Tkinter** - Native GUI
- **pywebview/PyQt6** - Embedded browser for authentication
- **rclone** - Backend for all ProtonDrive operations

## Quick Start (Dev Branch)

```bash
git clone https://github.com/donniedice/protondrive-linux.git
cd protondrive-linux
git checkout dev
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
python3 -m protondrive
```

We are working hard to bring a stable and functional ProtonDrive Linux client. Thank you for your patience!

## License

GPL-3.0 - See [LICENSE](LICENSE)
