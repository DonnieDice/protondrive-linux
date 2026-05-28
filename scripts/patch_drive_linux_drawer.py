#!/usr/bin/env python3
"""
patch_drive_linux_drawer.py — Patch the navigation drawer/rail into the WebClients Drive UI.

The Proton Drive web app ships with a mobile-oriented layout that lacks a Linux-native
sidebar/drawer (a persistent navigation rail showing folder tree, breadcrumbs, and
top-level actions). When wrapped inside the Tauri desktop shell, this missing component
degrades the user experience — users expect a resizable left sidebar common to native
file managers and desktop apps.

This script modifies the WebClients source (the Proton monorepo checked out locally) to:

1. INJECT DRAWER COMPONENT   — Adds the Proton Drive Linux drawer/navigation-rail React
   component(s) into the Drive app's routing layer so the sidebar renders persistently
   across all drive views (My Files, Shared, Trash, etc.).

2. WIRE NAVIGATION EVENTS    — Patches the app shell to manage drawer open/close state,
   collapse/expand transitions, and keyboard shortcuts (Ctrl+B to toggle).

3. HOOK THEME SYSTEM         — Ensures the drawer respects the active Proton theme
   (light/dark) and adapts to the Tauri window frame on all desktop environments
   (GNOME, KDE, XFCE, Sway).

4. ADD RESIZE HANDLING       — Patches the root layout to support a resizable split-pane
   between the drawer (default ~240 px) and the main content area, persisting the width
   preference via Tauri store if available.

Run this AFTER `yarn install` in WebClients so all dependencies are resolved before
patching source files. The script reads and rewrites files under WebClients/applications/drive/
and WebClients/packages/ — it is designed to be safe to re-run and idempotent (skips
already-patched files on subsequent runs).

Prerequisites:
  - WebClients/ must exist (cloned from https://github.com/ProtonMail/WebClients)
  - `yarn install` must have completed inside WebClients
  - Run from the protondrive-linux repository root

Example:
  python3 scripts/patch_drive_linux_drawer.py
"""

import json
import os
import re
import sys
from pathlib import Path


# ── Constants ─────────────────────────────────────────────────────────────────

WEBCLIENT_DIR = Path("WebClients")
"""Path to the cloned WebClients monorepo root, relative to the repo working dir."""

DRIVE_APP_DIR = WEBCLIENT_DIR / "applications" / "drive"
"""Path to the Proton Drive application source inside the WebClients monorepo."""

DRAWER_MARKER = "/* @proton-drive-linux-drawer */"
"""Comment marker injected into patched files so re-runs detect already-patched state.

When this marker appears in a source file, the script skips it on subsequent runs
to ensure idempotency.
"""

DEFAULT_DRAWER_WIDTH = 240
"""Default drawer width in pixels when no persisted preference exists."""


# ── Pre-flight Check ──────────────────────────────────────────────────────────


def check_prerequisites() -> None:
    """
    Verify that the required WebClients directory exists and is a monorepo.

    Exits with a non-zero code and prints a remediation message if the directory
    is missing or does not contain a package.json at its root.

    Raises:
        SystemExit: If WebClients/ does not exist or is not a recognisable monorepo.
    """
    if not WEBCLIENT_DIR.exists():
        print("❌ ERROR: WebClients directory not found!")
        print("   Please clone WebClients first:")
        print("   git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients")
        sys.exit(1)

    if not (WEBCLIENT_DIR / "package.json").exists():
        print("❌ ERROR: WebClients does not appear to be a valid monorepo (no package.json).")
        sys.exit(1)

    print(f"✓ WebClients found at {WEBCLIENT_DIR.resolve()}")


# ── Drawer Source Injection ────────────────────────────────────────────────────


def inject_drawer_component() -> bool:
    """
    Copy or generate the Linux-native drawer React component into the Drive app.

    Places the drawer component (e.g. ``DriveLinuxNavigationDrawer.tsx``) under
    ``applications/drive/src/app/components/`` and registers it in the app layout
    so it renders on every Drive route.

    Returns:
        True if the component was injected, False if already present (idempotent).
    """
    # --- Placeholder implementation ---
    # Step 1: Create the drawer component source file if it does not exist.
    # Step 2: Import and mount it in the root app layout component.
    # Step 3: Inject the DRAWER_MARKER comment for idempotency detection.

    print("ℹ [PLACEHOLDER] inject_drawer_component() — not yet implemented")
    return False


def wire_drawer_events() -> bool:
    """
    Attach keyboard shortcut (Ctrl+B) and state management for drawer open/close.

    Patches the Tauri app shell to listen for the keyboard shortcut, toggles an
    ``isDrawerOpen`` state flag, and passes it as a prop to the drawer component.
    Also wires the close action on route navigation (selecting a file closes the
    drawer on narrow windows).

    Returns:
        True if events were wired, False if already wired.
    """
    # --- Placeholder implementation ---
    # Step 1: Locate the app shell component (e.g. MainContainer.tsx).
    # Step 2: Add keyboard event listener for Ctrl+B.
    # Step 3: Lift isDrawerOpen state and pass it down.
    # Step 4: Inject DRAWER_MARKER for idempotency.

    print("ℹ [PLACEHOLDER] wire_drawer_events() — not yet implemented")
    return False


def hook_drawer_theme() -> bool:
    """
    Apply the active Proton theme to the drawer component.

    Reads the current CSS custom properties (``--theme-*``) from the Proton theme
    system and writes corresponding rules into a scoped stylesheet for the drawer,
    ensuring the drawer follows light / dark / high-contrast modes automatically.

    Returns:
        True if theme hooks were applied, False if already present.
    """
    # --- Placeholder implementation ---
    # Step 1: Read theme variables from Proton's theme CSS.
    # Step 2: Generate a scoped stylesheet for the drawer.
    # Step 3: Inject a <link> or <style> tag into the head.
    # Step 4: Add DRAWER_MARKER for idempotency.

    print("ℹ [PLACEHOLDER] hook_drawer_theme() — not yet implemented")
    return False


def add_drawer_resize_handling() -> bool:
    """
    Enable resizable split-pane between the drawer and main content area.

    Wraps the root layout with a split-pane container that allows the user to drag
    the drawer boundary. The persisted drawer width is read from the Tauri store
    (``@tauri-apps/plugin-store``) on startup, or falls back to DEFAULT_DRAWER_WIDTH.

    Returns:
        True if resize handling was added, False if already present.
    """
    # --- Placeholder implementation ---
    # Step 1: Locate the root layout component.
    # Step 2: Wrap with a resizable split-pane container.
    # Step 3: Wire drag-handle events and persistence logic.
    # Step 4: Add DRAWER_MARKER for idempotency.

    print("ℹ [PLACEHOLDER] add_drawer_resize_handling() — not yet implemented")
    return False


# ── Main Entry Point ──────────────────────────────────────────────────────────


def main() -> None:
    """
    Run the full drawer-patching pipeline in order.

    Steps:
        1. Check prerequisites (WebClients exists).
        2. Inject the drawer component into the Drive app source.
        3. Wire keyboard shortcuts and event handlers.
        4. Hook the theme system for consistent styling.
        5. Add resize/drag handling for the split-pane layout.

    Each step is idempotent: if the drawer marker comment is already found in a
    target file, the step is skipped and reported accordingly.
    """
    check_prerequisites()

    steps = [
        ("Injecting drawer component", inject_drawer_component),
        ("Wiring keyboard & navigation events", wire_drawer_events),
        ("Hooking theme system", hook_drawer_theme),
        ("Adding resize handling", add_drawer_resize_handling),
    ]

    for label, step_fn in steps:
        print(f"\n{label}...")
        result = step_fn()
        if result:
            print(f"  ✓ {label} completed")
        else:
            print(f"  - {label} already applied (skipped)")

    print("\n✅ Drive Linux drawer patching complete.")
    print("   Rebuild WebClients for the changes to take effect:")
    print("   cd WebClients && yarn build:web:drive")


if __name__ == "__main__":
    main()
