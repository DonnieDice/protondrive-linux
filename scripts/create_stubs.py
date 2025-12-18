#!/usr/bin/env python3
"""Create stub packages for private Proton modules not available on public npm."""

import json
from pathlib import Path

print("Creating stubs for private Proton packages...")

# @proton/collect-metrics is required by webpack plugins but not on public npm
stub_packages = {
    '@proton/collect-metrics': {
        'name': '@proton/collect-metrics',
        'version': '0.0.0-stub',
        'main': 'index.js',
        'description': 'Stub package for CI builds'
    }
}

stub_index_content = '''// Stub for private Proton package
class WebpackCollectMetricsPlugin {
    constructor(options) {}
    apply(compiler) {}
}

module.exports = {
    WebpackCollectMetricsPlugin,
    collectMetrics: () => {},
    reportMetrics: () => {},
    default: WebpackCollectMetricsPlugin
};
'''

for pkg_name, pkg_json in stub_packages.items():
    # Create in WebClients/node_modules/@proton/collect-metrics
    parts = pkg_name.split('/')
    if len(parts) == 2:
        scope, name = parts
        stub_dir = Path(f'WebClients/node_modules/{scope}/{name}')
    else:
        stub_dir = Path(f'WebClients/node_modules/{pkg_name}')

    stub_dir.mkdir(parents=True, exist_ok=True)
    (stub_dir / 'package.json').write_text(json.dumps(pkg_json, indent=2) + '\n')
    (stub_dir / 'index.js').write_text(stub_index_content)
    print(f"  Created stub for {pkg_name}")

print("✅ Private package stubs created")