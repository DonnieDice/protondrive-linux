#!/usr/bin/env python3
"""
fix_deps.py — Patch dependency issues in the WebClients build.

WebClients is a monorepo with Proton-internal dependencies and registries that are
inaccessible from CI/build environments. This script performs several fixups:

1. REMOVE PROBLEMATIC DEPS — Strips rowsnColumns, proton-meet, electron, and
   proton-foundation-search from dependency sections in all WebClients package.json
   files. These packages either don't exist on public npm or aren't needed for
   the Drive desktop build.

2. PATCH DRIVE BUILD — Changes appMode from 'sso' to 'standalone' (SSO expects
   Proton's domain; standalone works with any origin like tauri://). Removes any
   --api flag (Tauri IPC handles API calls). Adds --no-sri because WebKitGTK
   rejects script integrity attributes on the tauri:// protocol.

3. DISABLE SRI FOR ACCOUNT/VERIFY — Same WebKitGTK tauri:// SRI rejection affects
   the account and verify apps; adds --no-sri to their build:web scripts.

4. CONFIGURE YARN — Removes npmScopes and npmRegistries sections (internal Proton
   registries unreachable from CI), overrides npmRegistryServer to the public
   registry, and disables immutable installs for CI compatibility.

Run BEFORE `yarn install` in WebClients. Requires WebClients/ to exist (cloned).
"""
import json
import re
import sys
from pathlib import Path

# Check if WebClients directory exists
webclient_dir = Path('WebClients')
if not webclient_dir.exists():
    print("❌ ERROR: WebClients directory not found!")
    print("   Please clone WebClients first:")
    print("   git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients")
    sys.exit(1)

print("Scanning for problematic dependencies...")
count = 0

for pkg in Path('WebClients').rglob('package.json'):
    if 'node_modules' in str(pkg) or '.yarn' in str(pkg):
        continue
    try:
        data = json.loads(pkg.read_text())
        modified = False

        for section in ('dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies'):
            if section in data:
                for k in list(data[section].keys()):
                    if any(bad in k.lower() for bad in ['rowsncolumns', 'proton-meet', 'electron', 'proton-foundation-search']):
                        print(f"  Removing {k} from {pkg}")
                        del data[section][k]
                        modified = True
                        count += 1

        if modified:
            pkg.write_text(json.dumps(data, indent=2) + '\n')

    except Exception as e:
        print(f"  Warning: Could not process {pkg}: {e}")

print(f"✅ Patched {count} dependencies")

# Patch Proton Drive to use standalone mode for desktop wrapper
# SSO mode expects to run on Proton's domain, standalone mode works with any origin
# No --api flag needed: Tauri IPC intercepts all fetch/XHR calls to Proton domains
print("\nPatching Proton Drive build configuration...")
drive_pkg_path = Path('WebClients/applications/drive/package.json')
if drive_pkg_path.exists():
    drive_data = json.loads(drive_pkg_path.read_text())
    if 'scripts' in drive_data and 'build:web' in drive_data['scripts']:
        old_script = drive_data['scripts']['build:web']
        # Change appMode from sso to standalone for desktop wrapper
        new_script = re.sub(r'--appMode=sso', '--appMode=standalone', old_script)
        # Remove any --api override - Tauri IPC handles API calls via fetch interception
        new_script = re.sub(r'\s*--api=\S+', '', new_script)
        # Disable SRI: WebKitGTK rejects script integrity attributes on tauri:// protocol,
        # causing "Loading chunk X failed" even when the fetch returns HTTP 200.
        if '--no-sri' not in new_script:
            new_script = new_script.rstrip() + ' --no-sri'
        if old_script != new_script:
            drive_data['scripts']['build:web'] = new_script
            drive_pkg_path.write_text(json.dumps(drive_data, indent=4) + '\n')
            print("  Changed appMode to standalone, disabled SRI (WebKitGTK tauri:// incompatibility)")
        else:
            print("  build:web already configured")
    else:
        print("  Warning: Could not find build:web script")
else:
    print("  Warning: Could not find drive package.json")

# Disable SRI for account and verify apps (same WebKitGTK tauri:// SRI rejection issue)
for app_name, app_pkg_path in [
    ('account', Path('WebClients/applications/account/package.json')),
    ('verify', Path('WebClients/applications/verify/package.json')),
]:
    if app_pkg_path.exists():
        app_data = json.loads(app_pkg_path.read_text())
        if 'scripts' in app_data and 'build:web' in app_data['scripts']:
            old_script = app_data['scripts']['build:web']
            if '--no-sri' not in old_script:
                new_script = old_script.rstrip() + ' --no-sri'
                app_data['scripts']['build:web'] = new_script
                app_pkg_path.write_text(json.dumps(app_data, indent=4) + '\n')
                print(f"  Disabled SRI for {app_name} app")
            else:
                print(f"  {app_name} SRI already disabled")
    else:
        print(f"  Warning: Could not find {app_name} package.json")

# Configure yarn for better reliability and compatibility
print("\nConfiguring Yarn settings...")
yarnrc_path = Path('WebClients/.yarnrc.yml')
yarnrc_content = yarnrc_path.read_text() if yarnrc_path.exists() else ""

# Parse and rewrite .yarnrc.yml
lines = yarnrc_content.split('\n')
new_lines = []
skip_until_dedent = False
skip_depth = 0

for line in lines:
    stripped = line.lstrip()
    current_indent = len(line) - len(stripped)

    if stripped.startswith('npmScopes:'):
        skip_until_dedent = True
        skip_depth = current_indent
        print("  Removing npmScopes (internal Proton registries)")
        continue

    if stripped.startswith('npmRegistries:'):
        skip_until_dedent = True
        skip_depth = current_indent
        print("  Removing npmRegistries (internal registry auth)")
        continue

    if skip_until_dedent:
        if stripped and current_indent <= skip_depth:
            skip_until_dedent = False
        else:
            continue

    if stripped.startswith('npmRegistryServer:'):
        new_lines.append('npmRegistryServer: "https://registry.npmjs.org"')
        print("  Overriding npmRegistryServer to use public npm registry")
        continue

    new_lines.append(line)

yarnrc_content = '\n'.join(new_lines)

if 'npmRegistryServer' not in yarnrc_content:
    yarnrc_content += '\nnpmRegistryServer: "https://registry.npmjs.org"\n'
    print("  Added official npm registry configuration")

if 'enableImmutableInstalls' not in yarnrc_content:
    yarnrc_content += 'enableImmutableInstalls: false\n'
    print("  Disabled immutable installs mode")

yarnrc_path.write_text(yarnrc_content)
print("✅ Yarn configured with public npm registry")