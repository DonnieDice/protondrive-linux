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
                    if any(bad in k.lower() for bad in ['rowsncolumns', 'proton-meet', 'electron']):
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
        if old_script != new_script:
            drive_data['scripts']['build:web'] = new_script
            drive_pkg_path.write_text(json.dumps(drive_data, indent=4) + '\n')
            print("  Changed appMode to standalone (API calls intercepted via Tauri IPC)")
        else:
            print("  build:web already configured")
    else:
        print("  Warning: Could not find build:web script")
else:
    print("  Warning: Could not find drive package.json")

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