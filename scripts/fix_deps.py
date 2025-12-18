import json
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
                    # Remove known problematic packages
                    if any(bad in k.lower() for bad in ['rowsncolumns', 'problematic-package']):
                        print(f"  Removing {k} from {pkg}")
                        del data[section][k]
                        modified = True
                        count += 1

        if modified:
            pkg.write_text(json.dumps(data, indent=2) + '\n')

    except Exception as e:
        print(f"  Warning: Could not process {pkg}: {e}")

print(f"✅ Patched {count} dependencies")

# Configure yarn for better reliability and compatibility
print("\nConfiguring Yarn settings...")
yarnrc_path = Path('WebClients/.yarnrc.yml')
yarnrc_content = yarnrc_path.read_text() if yarnrc_path.exists() else ""

# Add official npm registry configuration if not already present
if 'npmRegistryServer' not in yarnrc_content:
    yarnrc_content += "\nnpmRegistryServer: \"https://registry.npmjs.org\"\n"
    print("  Added official npm registry configuration")

# Disable immutable installs mode to allow lockfile generation after patching
if 'enableImmutableInstalls' not in yarnrc_content:
    yarnrc_content += "enableImmutableInstalls: false\n"
    print("  Disabled immutable installs mode")

yarnrc_path.write_text(yarnrc_content)
print("✅ Yarn configured with npm registry and immutable mode disabled")