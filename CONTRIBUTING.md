# Contributing to Proton Drive Tauri

Thank you for your interest in contributing! This guide will help you understand the project structure and how to get started.

## Project Structure

```
protondrive-tauri/
├── src-tauri/          # Rust backend (Tauri framework)
│   ├── src/main.rs    # IPC commands, system tray, menus
│   ├── Cargo.toml     # Rust dependencies
│   └── tauri.conf.json # Configuration
├── WebClients/        # Git submodule (Proton Drive web app)
│   └── applications/drive/
│       ├── src/       # React/TypeScript source
│       └── build/     # Compiled output
└── scripts/           # Build and setup scripts
```

## Development Workflow

### Setup

1. Clone with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/yourusername/protondrive-tauri.git
   cd protondrive-tauri
   ```

2. Run the setup script:
   ```bash
   bash scripts/setup.sh
   ```

   Or manually:
   ```bash
   npm install
   rustup update
   ```

### Development

1. **Web app changes** (React/TypeScript):
   - Edit files in `WebClients/applications/drive/src/`
   - Changes hot-reload in dev mode

2. **Desktop features** (Rust):
   - Edit `src-tauri/src/main.rs` for IPC commands, system tray, etc.
   - Restart dev server to apply changes

3. **Configuration**:
   - `src-tauri/tauri.conf.json` - Window size, bundles, metadata
   - `src-tauri/Cargo.toml` - Rust dependencies

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
npm run build
```

This creates production binaries in `src-tauri/target/release/bundle/`.

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
            my_new_command,  // Add here
        ])
        // ...
}
```

Then use from the web app (React):

```typescript
import { invoke } from "@tauri-apps/api/tauri";

const result = await invoke("my_new_command", { param: "test" });
```

### Adding system tray actions

Edit the `on_system_tray_event` handler in `src-tauri/src/main.rs`:

```rust
.on_system_tray_event(|app, event| match event {
    SystemTrayEvent::MenuItemClick { id, .. } => {
        match id.as_str() {
            "my_action" => {
                // Handle your action
            }
            _ => {}
        }
    }
    _ => {}
})
```

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

The WebClients repository is a git submodule. To update:

```bash
cd WebClients
git fetch origin
git checkout <tag-or-commit>
cd ..
git add WebClients
git commit -m "Update WebClients to <version>"
git push
```

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

## Troubleshooting

### Build errors related to Tauri dependencies

Update Rust and dependencies:
```bash
rustup update
cd src-tauri && cargo update
```

### WebClients submodule not initialized

```bash
git submodule update --init --recursive
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
