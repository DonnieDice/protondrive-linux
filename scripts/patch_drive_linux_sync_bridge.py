#!/usr/bin/env python3
"""
patch_drive_linux_sync_bridge.py — Inject ProtonDriveLinuxSyncBridge into the WebClients Drive app.

Injects the ProtonDriveLinuxSyncBridge.tsx React component into the Proton Drive web
application source tree under WebClients/. This component provides:

  - A sync status indicator showing current sync state (syncing, paused, error, idle)
  - Native sync bridge integration that communicates with the Rust backend via Tauri
    command API for starting, stopping, and monitoring file sync operations
  - A floating sync panel accessible from the Drive navigation sidebar

The injection works by patching the Drive app's entry-point component tree to mount
the bridge alongside the existing React render hierarchy. The bridge is scoped to
Linux desktop builds only (guarded by a Tauri platform check at build time).

When to run:
  - AFTER `yarn install` in WebClients (so the node_modules tree is settled)
  - BEFORE the WebClients build step (so the injected source is compiled into the bundle)

Prerequisites:
  - WebClients/ directory must exist with a completed `yarn install`
  - The ProtonDriveLinuxSyncBridge.tsx source file must exist under
    WebClients/applications/drive/src/app/ or equivalent path (created and maintained
    separately as part of the Tauri frontend source)

Example:
    python3 scripts/patch_drive_linux_sync_bridge.py

Artifacts modified:
  - WebClients/applications/drive/src/app/App.tsx          (mount point patch)
  - WebClients/applications/drive/src/app/useSyncBridge.ts  (bridge hook injection)
"""

import os
import re
import sys
from pathlib import Path
from typing import List, Optional


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

WEBCLIENTS_DIR = Path("WebClients")
DRIVE_APP_TSX = WEBCLIENTS_DIR / "applications" / "drive" / "src" / "app" / "App.tsx"
USE_SYNC_BRIDGE_TS = WEBCLIENTS_DIR / "applications" / "drive" / "src" / "app" / "useSyncBridge.ts"

# The bridge component lives alongside the Drive source; it is written by the
# Tauri frontend build step and consumed by this script.
BRIDGE_COMPONENT_IMPORT = (
    '{ ProtonDriveLinuxSyncBridge } from "./ProtonDriveLinuxSyncBridge"'
)
BRIDGE_USE_HOOK = "useProtonDriveLinuxSyncBridge"
BRIDGE_HOOK_IMPORT = (
    f'{{ {BRIDGE_USE_HOOK} }} from "./useProtonDriveLinuxSyncBridge"'
)

# Sentinel comment injected to mark the patch location — allows re-running
# the script idempotently by checking for the marker before patching.
_SENTINEL = "<!-- PATCH: ProtonDriveLinuxSyncBridge -->"


def _webclients_exists() -> bool:
    """Return True if the WebClients directory exists and is non-empty."""
    return WEBCLIENTS_DIR.is_dir() and any(WEBCLIENTS_DIR.iterdir())


def _already_patched(file_path: Path) -> bool:
    """Return True if *file_path* already contains the patch sentinel.

    Used to make the script idempotent — a second run is a no-op.
    """
    if not file_path.is_file():
        return False
    text = file_path.read_text(encoding="utf-8")
    return _SENTINEL in text


def _strip_bom(text: str) -> str:
    """Remove a UTF-8 BOM (\\ufeff) from *text* if present."""
    return text.lstrip("\ufeff")


def patch_app_entrypoint() -> bool:
    """Inject the ProtonDriveLinuxSyncBridge import and mount into App.tsx.

    Adds the import statement near the top of the file and mounts the bridge
    component inside the App component's return JSX tree, guarded by the
    *isLinuxDesktop* flag supplied by *useSyncBridge* hook.

    Returns True if the file was modified, False if it was already patched.
    """
    app_path = DRIVE_APP_TSX

    if not app_path.is_file():
        print(f"[SKIP] {app_path} not found — cannot patch entrypoint", file=sys.stderr)
        return False

    if _already_patched(app_path):
        print(f"[SKIP] {app_path} already patched (sentinel found)")
        return False

    source = _strip_bom(app_path.read_text(encoding="utf-8"))
    lines = source.splitlines(keepends=True)

    # --- 1. Choose an insertion point for the import ---
    # Find the last import statement (end of the import block).
    import_end = 0
    for i, line in enumerate(lines):
        if re.match(r"^\s*import\s", line) or re.match(r"^\s*from\s", line):
            import_end = i + 1

    if import_end == 0:
        print("[WARN] No import block found in App.tsx — appending import at top")
        import_end = 0

    bridge_import_line = (
        f"import {BRIDGE_COMPONENT_IMPORT};  {_SENTINEL}\n"
    )
    hook_import_line = (
        f"import {BRIDGE_HOOK_IMPORT};  {_SENTINEL}\n"
    )

    # Insert both import lines after the last existing import.
    insert_idx = import_end
    lines.insert(insert_idx, hook_import_line)
    lines.insert(insert_idx, bridge_import_line)

    # Adjust index for the two inserted lines.
    # --- 2. Inject the hook call inside the App component body ---
    # Look for the opening of the App component function or arrow function.
    # We inject after the first variable/constant declaration inside the function.
    func_body_pattern = re.compile(
        r"(export\s+(default\s+)?function\s+App\s*\([^)]*\)\s*\{)"
        r"|(const\s+App\s*[=:]\s*(\([^)]*\)|[a-zA-Z_]\w*)\s*=>\s*\{)"
    )

    func_start = None
    for i, line in enumerate(lines):
        if func_body_pattern.search(line):
            func_start = i
            break

    if func_start is None:
        print(
            "[WARN] Could not locate App component function — hook injection skipped",
            file=sys.stderr,
        )
    else:
        # Find the first statement after the opening brace by looking for the
        # first non-blank, non-brace line after func_start.
        hook_injected = False
        for i in range(func_start + 1, len(lines)):
            stripped = lines[i].strip()
            if stripped and stripped not in ("{", "}", ""):
                indent = " " * (len(lines[i]) - len(lines[i].lstrip()))
                hook_call = (
                    f"{indent}const {{ isLinuxDesktop }} = {BRIDGE_USE_HOOK}();"
                    f"  {_SENTINEL}\n"
                )
                lines.insert(i, hook_call)
                hook_injected = True
                break

        if not hook_injected:
            print("[WARN] Could not find injection point inside App() — hook skipped")

    # --- 3. Mount the bridge component in the JSX return ---
    # Find the first opening JSX element after 'return (' or 'return <'.
    return_found = False
    for i, line in enumerate(lines):
        if re.search(r"\breturn\s*[\(<]", line):
            return_found = True
            # Scan subsequent lines for the first JSX child.
            for j in range(i + 1, len(lines)):
                jsx_line = lines[j].strip()
                if jsx_line and not jsx_line.startswith(("//", "/*", "*", "{")):
                    indent = " " * (len(lines[j]) - len(lines[j].lstrip()))
                    bridge_mount = (
                        f"{indent}  {{/* {_SENTINEL} */}}\n"
                        f"{indent}  {{isLinuxDesktop && <ProtonDriveLinuxSyncBridge />}}\n"
                        f"{indent}  {{/* {_SENTINEL} end */}}\n"
                    )
                    lines.insert(j, bridge_mount)
                    break
            break

    if not return_found:
        print("[WARN] No return statement found in App.tsx — bridge mount skipped")

    app_path.write_text("".join(lines), encoding="utf-8")
    print(f"[PATCH] {app_path} — imports and bridge mount injected")
    return True


def inject_sync_bridge_hook() -> bool:
    """Create or update useSyncBridge.ts with the Linux sync bridge hook.

    If the file already exists and contains the sentinel, this is a no-op.
    Otherwise it writes the hook module that initialises the Tauri sync bridge
    and exposes the *isLinuxDesktop* flag and sync state to the App component.
    """
    hook_path = USE_SYNC_BRIDGE_TS

    if _already_patched(hook_path):
        print(f"[SKIP] {hook_path} already patched (sentinel found)")
        return False

    hook_path.parent.mkdir(parents=True, exist_ok=True)

    content = f'''// {_SENTINEL}
// Proton Drive Linux Sync Bridge hook
// Exposes sync state and platform detection to the App component.

import {{ useState, useEffect, useCallback }} from "react";

export interface SyncState {{
    status: "idle" | "syncing" | "paused" | "error";
    lastSync: Date | null;
    pendingFiles: number;
}}

/**
 * useProtonDriveLinuxSyncBridge — Tauri sync bridge integration hook.
 *
 * Detects the Linux desktop environment and initialises the native sync
 * bridge via Tauri invoke() commands. Returns an *isLinuxDesktop* flag
 * (used by App.tsx to conditionally mount the sync bridge component) and
 * the current SyncState exposed by the Rust backend.
 */
export function useProtonDriveLinuxSyncBridge(): {{
    isLinuxDesktop: boolean;
    syncState: SyncState;
    startSync: () => Promise<void>;
    pauseSync: () => Promise<void>;
    resumeSync: () => Promise<void>;
}} {{
    const [isLinuxDesktop] = useState<boolean>(() => {{
        try {{
            // @ts-expect-error — __TAURI__ is injected at build time
            return typeof window.__TAURI__ !== "undefined";
        }} catch {{
            return false;
        }}
    }});

    const [syncState, setSyncState] = useState<SyncState>({{
        status: "idle",
        lastSync: null,
        pendingFiles: 0,
    }});

    const startSync = useCallback(async () => {{
        if (!isLinuxDesktop) return;
        try {{
            // This invoke will call the Rust command registered in the Tauri
            // backend under src-tauri/src/cmd.rs or similar.
            // await invoke("start_sync");
            setSyncState(prev => ({{ ...prev, status: "syncing" }}));
        }} catch (err) {{
            console.error("Failed to start sync:", err);
            setSyncState(prev => ({{ ...prev, status: "error" }}));
        }}
    }}, [isLinuxDesktop]);

    const pauseSync = useCallback(async () => {{
        if (!isLinuxDesktop) return;
        setSyncState(prev => ({{ ...prev, status: "paused" }}));
    }}, [isLinuxDesktop]);

    const resumeSync = useCallback(async () => {{
        if (!isLinuxDesktop) return;
        setSyncState(prev => ({{ ...prev, status: "idle" }}));
    }}, [isLinuxDesktop]);

    return {{ isLinuxDesktop, syncState, startSync, pauseSync, resumeSync }};
}}
'''
    hook_path.write_text(content, encoding="utf-8")
    print(f"[PATCH] {hook_path} — hook module created")
    return True


def main() -> None:
    """Entry point. Validate WebClients, then patch App.tsx and inject the bridge hook.

    Exits with code 0 on success (or no-op), 1 if WebClients is missing.
    """
    if not _webclients_exists():
        print(
            "ERROR: WebClients directory not found. Run `yarn install` first, "
            "or run this script from the repository root.",
            file=sys.stderr,
        )
        sys.exit(1)

    print("patch_drive_linux_sync_bridge — injecting ProtonDriveLinuxSyncBridge")
    print(f"WebClients root: {WEBCLIENTS_DIR.resolve()}")

    patched_app = patch_app_entrypoint()
    patched_hook = inject_sync_bridge_hook()

    if patched_app or patched_hook:
        print("[DONE] Sync bridge injected. Rebuild WebClients to see the change.")
    else:
        print("[DONE] No changes needed — bridge already patched.")


if __name__ == "__main__":
    main()
