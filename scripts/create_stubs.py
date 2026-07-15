#!/usr/bin/env python3
"""
create_stubs.py — Create stub npm packages for private Proton modules.

When building WebClients, yarn resolves npm packages from the public registry. Some
Proton packages (e.g. @proton/collect-metrics, @proton/proton-foundation-search) are
private and never published there. This script creates minimal stub packages under
WebClients/node_modules/ so yarn resolves them locally instead of failing.

Each stub consists of:
  - package.json  — identity and version (0.0.0-stub)
  - index.js      — no-op JS exports matching the real API surface

Run this AFTER `yarn install` in WebClients so the stubs are in place before the build step.
Requires WebClients/ to exist with a completed yarn install.
"""

import json
from pathlib import Path

STUB_PACKAGES = {
    '@proton/collect-metrics': {
        'name': '@proton/collect-metrics',
        'version': '0.0.0-stub',
        'main': 'index.js',
        'description': 'Stub package for CI builds'
    },
    '@proton/proton-foundation-search': {
        'name': '@proton/proton-foundation-search',
        'version': '0.0.0-stub',
        'main': 'index.js',
        'description': 'Stub package for CI builds'
    }
}

STUB_CONTENTS = {}

STUB_CONTENTS['@proton/collect-metrics'] = '''// Stub for private Proton package
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

STUB_CONTENTS['@proton/proton-foundation-search'] = '''// Stub for private Proton package
class StubExecution {
    next() { return undefined; }
    free() {}
}

class StubWrite {
    insert() {}
    remove() {}
    commit() { return new StubExecution(); }
    free() {}
}

class StubQuery {
    withStructuredExpression() { return this; }
}

class Engine {
    static builder() {
        return {
            withBuiltinProcessor() { return this; },
            build() { return new Engine(); }
        };
    }
    write() { return new StubWrite(); }
    query() { return new StubQuery(); }
    free() {}
}

class ProcessorConfig {
    withMaxLength() { return this; }
}

class Document {
    constructor(id) { this.id = id; this.attributes = []; }
    addAttribute(name, value) { this.attributes.push([name, value]); }
}

class Value {
    static tag(value) { return { kind: 'tag', value }; }
    static text(value) { return { kind: 'text', value }; }
    static bool(value) { return { kind: 'boolean', value }; }
    static int(value) { return { kind: 'integer', value }; }
}

class TermValue {
    static int(value) { return new TermValue(value); }
    static text(value) { return new TermValue(value); }
    static bool(value) { return new TermValue(value); }
    static wild() { return new TermValue(''); }
    constructor(value) { this.value = value; }
    then(value) { this.value = `${this.value}${value}`; return this; }
    wildcard() { return this; }
}

class Expression {
    static attr(name, func, value) { return new Expression(name, func, value); }
    constructor(name, func, value) { this.name = name; this.func = func; this.value = value; }
    and(other) { return this; }
    or(other) { return this; }
}

class Cached {
    serialize() { return new Uint8Array(); }
}

const Func = { Equals: 'Equals', Matches: 'Matches' };
const SerDes = { Cbor: 'Cbor' };
const CleanupEventKind = { Load: 0, Save: 1, Release: 2, Stats: 3 };
const ExportEventKind = { Load: 0, Save: 1, Stats: 2 };
const QueryEventKind = { Load: 0, Stats: 1, Result: 2 };
const WriteEventKind = { Load: 0, Save: 1, Stats: 2 };

async function init() { return {}; }
function initSync() { return {}; }

module.exports = {
    default: init,
    init,
    initSync,
    ProcessorConfig,
    Engine,
    Document,
    Value,
    TermValue,
    Expression,
    Cached,
    Func,
    SerDes,
    CleanupEventKind,
    ExportEventKind,
    QueryEventKind,
    WriteEventKind
};
'''


def stub_dir_for(webclients_dir: Path, pkg_name: str) -> Path:
    parts = pkg_name.split('/')
    if len(parts) == 2:
        scope, name = parts
        return webclients_dir / 'node_modules' / scope / name
    return webclients_dir / 'node_modules' / pkg_name


def write_stub(webclients_dir: Path, pkg_name: str) -> Path:
    stub_dir = stub_dir_for(webclients_dir, pkg_name)
    stub_dir.mkdir(parents=True, exist_ok=True)
    (stub_dir / 'package.json').write_text(
        json.dumps(STUB_PACKAGES[pkg_name], indent=2) + '\n', encoding="utf-8"
    )
    (stub_dir / 'index.js').write_text(STUB_CONTENTS[pkg_name], encoding="utf-8")
    return stub_dir


def main() -> None:
    print("Creating stubs for private Proton packages...")
    webclients_dir = Path('WebClients')
    for pkg_name in STUB_PACKAGES:
        write_stub(webclients_dir, pkg_name)
        print(f"  Created stub for {pkg_name}")
    print("✅ Private package stubs created")


if __name__ == "__main__":
    main()
