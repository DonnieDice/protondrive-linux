# Contributing to Proton Drive Linux

Thank you for your interest in contributing! This guide will help you understand the project structure and how to get started.

## Project Structure

```
protondrive-linux/
├── src-tauri/            # Rust backend (Tauri framework)
│   ├── src/main.rs       # IPC commands, system tray, menus
│   ├── Cargo.toml        # Rust dependencies
│   └── tauri.conf.json   # Configuration
├── WebClients/           # Proton Drive web app (cloned at build time, NOT a submodule)
│   └── applications/drive/
│       ├── src/          # React/TypeScript source
│       └── build/        # Compiled output
├── patches/              # Distro-specific patches (applied before cargo build)
├── scripts/              # Build and packaging scripts
├── packaging/            # Compatibility map and packaging templates
├── docs/                 # Documentation
└── aur/                  # AUR PKGBUILD
```

## Development Workflow

### Setup

1. Clone the repository:
```bash
git clone https://github.com/DonnieDice/protondrive-linux.git
cd protondrive-linux
```

2. Clone the WebClients repository (needed for builds):
```bash
git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients
```

3. Install dependencies:
```bash
npm install
rustup update
```

Install system dependencies for your distribution:

```bash
# Fedora
sudo dnf install webkit2gtk4.1-devel gtk3-devel libayatana-appindicator-gtk3-devel openssl-devel

# Debian / Ubuntu
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev libssl-dev

# Arch / Manjaro
sudo pacman -S webkit2gtk-4.1 gtk3 libayatana-appindicator
```

### Development

1. **Web app changes** (React/TypeScript):
- Edit files in `WebClients/applications/drive/src/`
- Changes hot-reload in dev mode

2. **Desktop features** (Rust):
- Edit `src-tauri/src/main.rs` for IPC commands, system tray, etc.
- Restart dev server to apply changes
- **Do NOT add distro-specific env vars or DISTRO_TYPE branching in `main.rs`** — these belong in `patches/`

3. **Configuration**: Edit `src-tauri/tauri.conf.json` for window size, bundles, and metadata.

### Running in Development

```bash
npm run dev
```

This will:
- Start a dev server at `http://localhost:5173`
- Launch the Tauri window
- Enable hot-reload for web app changes

### Building

```bash
npm run build:web         # Build web frontend only
npm run build:appimage    # Build AppImage
npm run build:deb         # Build DEB package
npm run build:rpm         # Build RPM package
```

For more package types, use the scripts in `scripts/`:

```bash
scripts/appimage/build-local-appimage.sh
scripts/deb/build-local-deb.sh
scripts/rpm/build-local-rpm.fedora.43.sh
scripts/flatpak/build-local-flatpak.sh
scripts/snap/build-local-snap.sh
scripts/build-local-aur.sh
```

Built packages are created in `src-tauri/target/release/bundle/`.

## Code Style

### Rust

- Follow [Rust naming conventions](https://rust-lang.github.io/api-guidelines/naming.html)
- Use `cargo fmt` to format:
```bash
cd src-tauri && cargo fmt
```
- Use `cargo clippy` to lint:
```bash
cd src-tauri && cargo clippy -- -D warnings
```

### TypeScript/React

- Inherited from WebClients. Follow their conventions in `WebClients/applications/drive/`

## Adding Desktop Features

### Adding a new Tauri IPC command

Edit `src-tauri/src/main.rs`:

```rust
#[tauri::command]
async fn my_new_command(param: String) -> Result<String, String> {
    // Your logic here
    Ok(format!("Processed: {}", param))
}

fn main() {
    // ...
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            show_notification,
            open_file_dialog,
            get_app_version,
            check_for_updates,
            my_new_command, // Add here
        ])
    // ...
}
```

Then use from the web app (React):

```typescript
import { invoke } from "@tauri-apps/api/tauri";

const result = await invoke("my_new_command", { param: "test" });
```

### Adding a new distro patch

1. Create the patch file in `patches/<package>/<runtime>.patch`
2. Add the workflow in `.github/workflows/`
3. Add the target to `packaging/compatibility-map.yml`
4. Update `docs/compatibility.md` and `docs/packaging.md`

See existing patches for the patch convention. Patches are named by runtime/ABI target, not host distro.

## Testing

### Manual testing

1. Run `npm run dev`
2. Test features in the app window
3. Check system tray, notifications, dialogs

### Automated testing

Tests for the web app are in `WebClients/applications/drive/`. Run them:

```bash
cd WebClients/applications/drive
npm test
```

## Updating WebClients

The WebClients repository is cloned at build time (not a submodule). To update the version used:

1. Edit the clone command or branch reference in `scripts/build-webclients.sh`
2. Re-run the build

## Submitting Changes

1. Create a feature branch:
```bash
git checkout -b feature/my-feature
```

2. Commit with clear messages:
```bash
git commit -m "Add system tray icon support"
```

3. Push and create a pull request:
```bash
git push origin feature/my-feature
```

## Building for Distribution

### AppImage (Linux, all distributions)

```bash
npm run build:appimage
```

Output: `src-tauri/target/release/bundle/appimage/Proton Drive_*.AppImage`

### DEB (Debian/Ubuntu)

```bash
npm run build:deb
```

Output: `src-tauri/target/release/bundle/deb/proton-drive_*.deb`

### RPM (Fedora/RHEL)

```bash
npm run build:rpm
```

Output: `src-tauri/target/release/bundle/rpm/proton-drive-*.rpm`

### Flatpak

```bash
scripts/flatpak/build-local-flatpak.sh
```

### Snap

```bash
scripts/snap/build-local-snap.sh
```

### AUR

```bash
scripts/build-local-aur.sh
```

## Troubleshooting

### Build errors related to Tauri dependencies

Update Rust and dependencies:
```bash
rustup update
cd src-tauri && cargo update
```

### WebClients not present

```bash
git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients
```

### Node.js version too old

Node.js 20+ is required. Check your version:
```bash
node -v
```

### Port 5173 already in use

Kill the process or change the port in `tauri.conf.json`:

```json
"devPath": "http://localhost:5174"
```

## Need Help?

- [Tauri Documentation](https://tauri.app/en/docs/)
- [Proton Drive GitHub](https://github.com/ProtonMail/WebClients)
- Check existing issues or open a new one

Thank you for contributing!
