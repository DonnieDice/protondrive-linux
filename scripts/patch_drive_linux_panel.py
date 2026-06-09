#!/usr/bin/env python3
"""
Inject the DriveLinuxPanel into the Drive app.

Creates DriveLinuxPanel.tsx inside the drawer components directory and wires
it into DriveWindow.tsx as the customAppSettings for the QUICK_SETTINGS
drawer slot (the Linux-specific entry in the sidebar rail).

The panel is split into two zones:
  • A fixed-height sync-status header that calls Tauri IPC (get_sync_status,
    stop_sync, set_sync_root) — no scroll, always visible.
  • The existing DriveQuickSettings below — scrollable, all Drive settings
    (settings link, clear search, export log, diagnostics) preserved.
"""
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
WEBCLIENTS_DIR = REPO_ROOT / "WebClients"

DRIVE_APP = WEBCLIENTS_DIR / "applications/drive/src/app"
DRAWER_DIR = DRIVE_APP / "components/drawer"
DRIVE_WINDOW_CANDIDATES = [
    DRIVE_APP / "components/layout/DriveWindow.tsx",
    DRIVE_APP / "legacy/components/layout/DriveWindow.tsx",
]

PANEL_COMPONENT = DRAWER_DIR / "DriveLinuxPanel.tsx"

PANEL_SOURCE = '''\
import { useEffect, useState } from 'react';

import { c } from 'ttag';

import { Button } from '@proton/atoms';

import DriveQuickSettings from './DriveQuickSettings';

// ── Tauri bridge ──────────────────────────────────────────────────────────────

type TauriCore = {
    invoke<T = unknown>(command: string, args?: Record<string, unknown>): Promise<T>;
};
type TauriApi = { core?: TauriCore };

const getTauri = (): TauriCore | undefined =>
    ((window as unknown as { __TAURI__?: TauriApi }).__TAURI__ ?? {}).core;

type SyncStatus = {
    enabled: boolean;
    folder_path: string | null;
    poll_interval_seconds: number;
};

// ── Component ─────────────────────────────────────────────────────────────────

/**
 * Linux-specific drawer panel.
 *
 * Shown when the user clicks the Proton Drive Linux button in the sidebar rail.
 * The panel has two zones:
 *   1. Sync status header — fixed height, Tauri IPC, always visible.
 *   2. DriveQuickSettings — scrollable, existing Drive settings preserved.
 */
const DriveLinuxPanel = () => {
    const [status, setStatus] = useState<SyncStatus | null>(null);
    const [busy, setBusy] = useState(false);

    const fetchStatus = () => {
        const core = getTauri();
        if (!core) return;
        core.invoke<SyncStatus>('get_sync_status').then(setStatus).catch(() => {});
    };

    useEffect(() => {
        fetchStatus();
    }, []);

    const handleStopSync = async () => {
        const core = getTauri();
        if (!core || busy) return;
        setBusy(true);
        try {
            await core.invoke('stop_sync');
            fetchStatus();
        } finally {
            setBusy(false);
        }
    };

    const syncLabel = status?.enabled
        ? c('Info').t`Live sync active`
        : c('Info').t`Sync stopped`;

    const folderDisplay = status?.folder_path ?? '';

    return (
        /* Two-zone layout: fixed header + scrollable settings below */
        <div className="h-full flex flex-column overflow-hidden">
            {/* ── Zone 1: Sync status (fixed, no scroll) ── */}
            <div className="shrink-0 p-4 border-bottom border-weak flex flex-column gap-3">
                <h3 className="text-bold text-rg m-0">{c('Title').t`Proton Drive Linux`}</h3>

                <div className="flex items-center gap-2">
                    <span
                        className={`inline-block rounded-full ${status?.enabled ? 'bg-success' : 'bg-weak'}`}
                        style={{ width: '0.5rem', height: '0.5rem', flexShrink: 0 }}
                        aria-hidden
                    />
                    <span className="text-sm">{syncLabel}</span>
                </div>

                {folderDisplay && (
                    <div
                        className="text-sm color-weak text-ellipsis overflow-hidden"
                        title={folderDisplay}
                        aria-label={c('Label').t`Sync folder: ${folderDisplay}`}
                    >
                        {folderDisplay}
                    </div>
                )}

                {status?.enabled && (
                    <Button
                        size="small"
                        shape="outline"
                        color="weak"
                        onClick={handleStopSync}
                        loading={busy}
                        aria-label={c('Action').t`Stop live sync`}
                    >
                        {c('Action').t`Stop sync`}
                    </Button>
                )}

                {!status && getTauri() && (
                    <span className="text-sm color-weak">{c('Info').t`Loading sync status…`}</span>
                )}
                {!getTauri() && (
                    <span className="text-sm color-weak">
                        {c('Info').t`Native sync controls unavailable outside of the desktop app.`}
                    </span>
                )}
            </div>

            {/* ── Zone 2: Existing Drive quick-settings (scrollable) ── */}
            <div className="flex-1 min-h-0 overflow-hidden">
                <DriveQuickSettings />
            </div>
        </div>
    );
};

export default DriveLinuxPanel;
'''


def fail(message: str) -> None:
    print(f"  ❌ {message}", file=sys.stderr)
    sys.exit(1)


def replace_once(content: str, old: str, new: str, label: str) -> str:
    if old not in content:
        fail(f"patch_drive_linux_panel: missing anchor — {label}")
    return content.replace(old, new, 1)


def main() -> None:
    if not DRAWER_DIR.exists():
        fail(f"drawer directory not found: {DRAWER_DIR}")

    # 1. Write DriveLinuxPanel.tsx
    if PANEL_COMPONENT.exists() and "DriveLinuxPanel" in PANEL_COMPONENT.read_text():
        print("  ⚠ DriveLinuxPanel.tsx already present — skipping component write")
    else:
        PANEL_COMPONENT.write_text(PANEL_SOURCE)
        print(f"  ✓ Created {PANEL_COMPONENT.relative_to(WEBCLIENTS_DIR)}")

    # 2. Wire DriveLinuxPanel into DriveWindow.tsx
    drive_window = next((p for p in DRIVE_WINDOW_CANDIDATES if p.exists()), None)
    if drive_window is None:
        fail("DriveWindow.tsx not found")

    content = drive_window.read_text()
    if "DriveLinuxPanel" in content:
        print("  ⚠ DriveWindow.tsx already uses DriveLinuxPanel — skipping")
        return

    # Add import (after the DriveQuickSettings import)
    content = replace_once(
        content,
        "import DriveQuickSettings from '../drawer/DriveQuickSettings';",
        "import DriveQuickSettings from '../drawer/DriveQuickSettings';\n"
        "import DriveLinuxPanel from '../drawer/DriveLinuxPanel';",
        "DriveQuickSettings import anchor",
    )

    # Swap customAppSettings — replace DriveQuickSettings with DriveLinuxPanel
    content = replace_once(
        content,
        "drawerApp={<DrawerApp customAppSettings={<DriveQuickSettings />} />}",
        "drawerApp={<DrawerApp customAppSettings={<DriveLinuxPanel />} />}",
        "customAppSettings anchor",
    )

    drive_window.write_text(content)
    print(
        f"  ✓ Wired DriveLinuxPanel into "
        f"{drive_window.relative_to(WEBCLIENTS_DIR)}"
    )


if __name__ == "__main__":
    main()
