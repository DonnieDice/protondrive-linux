import json
import re
from pathlib import Path

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
                    # Remove known problematic/private packages
                    # - rowsncolumns: known problematic package
                    # - @proton-meet: private Proton packages not on public npm
                    if any(bad in k.lower() for bad in ['rowsncolumns', 'proton-meet']):
                        print(f"  Removing {k} from {pkg}")
                        del data[section][k]
                        modified = True
                        count += 1

        if modified:
            pkg.write_text(json.dumps(data, indent=2) + '\n')

    except Exception as e:
        print(f"  Warning: Could not process {pkg}: {e}")

print(f"✅ Patched {count} dependencies")

# Patch Proton Drive to build in standalone mode with local API proxy
# SSO mode requires cross-app authentication which doesn't work in Tauri
# API is proxied through local server to bypass CORS restrictions
print("\nPatching Proton Drive build mode...")
drive_pkg_path = Path('WebClients/applications/drive/package.json')
if drive_pkg_path.exists():
    drive_data = json.loads(drive_pkg_path.read_text())
    if 'scripts' in drive_data and 'build:web' in drive_data['scripts']:
        old_script = drive_data['scripts']['build:web']
        # Change from SSO mode to standalone mode for desktop compatibility
        new_script = old_script.replace('--appMode=sso', '--appMode=standalone')
        # Use local proxy to bypass CORS (Tauri app runs proxy on port 9543)
        if '--api' not in new_script:
            new_script = new_script + ' --api=http://127.0.0.1:9543'
        else:
            # Replace existing API URL with local proxy
            new_script = re.sub(r'--api=\S+', '--api=http://127.0.0.1:9543', new_script)
        if old_script != new_script:
            drive_data['scripts']['build:web'] = new_script
            drive_pkg_path.write_text(json.dumps(drive_data, indent=4) + '\n')
            print("  Changed build:web to standalone mode with local API proxy")
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

# Parse and rewrite .yarnrc.yml to override internal Proton registries
# Proton uses internal registries (nexus.protontech.ch, gitlab.protontech.ch)
# that are not accessible from GitHub Actions
lines = yarnrc_content.split('\n')
new_lines = []
skip_until_dedent = False
skip_depth = 0

for line in lines:
    stripped = line.lstrip()
    current_indent = len(line) - len(stripped)

    # Skip npmScopes block entirely (internal registry definitions)
    if stripped.startswith('npmScopes:'):
        skip_until_dedent = True
        skip_depth = current_indent
        print("  Removing npmScopes (internal Proton registries)")
        continue

    # Skip npmRegistries block entirely (authentication for internal registries)
    if stripped.startswith('npmRegistries:'):
        skip_until_dedent = True
        skip_depth = current_indent
        print("  Removing npmRegistries (internal registry auth)")
        continue

    # If we're skipping a block, check if we've dedented back
    if skip_until_dedent:
        if stripped and current_indent <= skip_depth:
            skip_until_dedent = False
        else:
            continue

    # Replace existing npmRegistryServer with public registry
    if stripped.startswith('npmRegistryServer:'):
        new_lines.append('npmRegistryServer: "https://registry.npmjs.org"')
        print("  Overriding npmRegistryServer to use public npm registry")
        continue

    new_lines.append(line)

yarnrc_content = '\n'.join(new_lines)

# Ensure settings are present if they weren't already in the file
if 'npmRegistryServer' not in yarnrc_content:
    yarnrc_content += '\nnpmRegistryServer: "https://registry.npmjs.org"\n'
    print("  Added official npm registry configuration")

if 'enableImmutableInstalls' not in yarnrc_content:
    yarnrc_content += 'enableImmutableInstalls: false\n'
    print("  Disabled immutable installs mode")

yarnrc_path.write_text(yarnrc_content)
print("✅ Yarn configured with public npm registry (internal Proton registries removed)")