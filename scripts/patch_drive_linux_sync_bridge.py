#!/usr/bin/env python3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
WEBCLIENTS_DIR = REPO_ROOT / "WebClients"
BRIDGE_RELATIVE = Path("applications/drive/src/app/store/ProtonDriveLinuxSyncBridge.tsx")
DRIVE_PROVIDER_RELATIVE = Path("applications/drive/src/app/store/DriveProvider.tsx")

BRIDGE_SOURCE = """import { useEffect, useRef } from 'react';

import { DeviceType, getDrive } from '@proton/drive';
import { uploadManager } from '@proton/drive/modules/upload';

type TauriApi = {
    core?: {
        invoke<T = unknown>(command: string, args?: Record<string, unknown>): Promise<T>;
    };
    event?: {
        listen<T = unknown>(
            event: string,
            handler: (payload: { payload: T }) => void
        ): Promise<() => void>;
    };
};

type LiveSyncChangePayload = {
    kind: string;
    rootPath: string;
    relativePaths: string[];
    source: string;
};

type SyncFilePayload = {
    relativePath: string;
    name: string;
    size: number;
    modifiedMs?: number;
    contentBase64: string;
};

const audit = (message: string) => {
    console.log(`[LiveSync][AUDIT] ${message}`);
};

const getTauri = (): TauriApi | undefined => (window as unknown as { __TAURI__?: TauriApi }).__TAURI__;

const decodeBase64 = (value: string): Uint8Array => {
    const binary = window.atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
};

const makeUploadFile = (payload: SyncFilePayload): File => {
    const bytes = decodeBase64(payload.contentBase64);
    const buffer = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(buffer).set(bytes);
    const file = new File([buffer], payload.name, {
        lastModified: payload.modifiedMs || Date.now(),
    });
    Object.defineProperty(file, 'webkitRelativePath', {
        value: payload.relativePath,
        configurable: true,
    });
    return file;
};

const resolveLinuxDeviceRoot = async (): Promise<string> => {
    const tauri = getTauri();
    if (!tauri?.core) {
        throw new Error('tauri api unavailable');
    }

    const deviceName = await tauri.core.invoke<string>('get_sync_device_name');
    const drive = getDrive();
    for await (const device of drive.iterateDevices()) {
        if (device.type !== DeviceType.Linux || !device.name.ok) {
            continue;
        }
        if (device.name.value === deviceName) {
            return device.rootFolderUid;
        }
    }

    const device = await drive.createDevice(deviceName, DeviceType.Linux);
    return device.rootFolderUid;
};

export const ProtonDriveLinuxSyncBridge = () => {
    const deviceRootPromise = useRef<Promise<string> | undefined>(undefined);
    const queue = useRef<Promise<void>>(Promise.resolve());

    useEffect(() => {
        const tauri = getTauri();
        if (!tauri?.core || !tauri?.event) {
            return;
        }
        const { core, event } = tauri;

        const processChange = async (payload: LiveSyncChangePayload) => {
            if (payload.kind === 'remove') {
                audit('local delete skipped reason=remote-id-mapping-missing');
                return;
            }
            if (payload.kind !== 'create' && payload.kind !== 'modify') {
                return;
            }

            if (!deviceRootPromise.current) {
                deviceRootPromise.current = resolveLinuxDeviceRoot();
            }
            const parentUid = await deviceRootPromise.current;

            for (const relativePath of payload.relativePaths || []) {
                try {
                    const filePayload = await core.invoke<SyncFilePayload>('read_sync_file', {
                        rootPath: payload.rootPath,
                        relativePath,
                    });
                    await uploadManager.upload([makeUploadFile(filePayload)], parentUid);
                    audit(`local ${payload.kind} result=queued scope=computers`);
                } catch (error) {
                    audit(`local ${payload.kind} result=skipped reason=file-unavailable`);
                }
            }
        };

        let unlisten: (() => void) | undefined;
        void event.listen<LiveSyncChangePayload>('live-sync://local-change', (listenerEvent) => {
            queue.current = queue.current.catch(() => undefined).then(() => processChange(listenerEvent.payload));
        }).then((cleanup) => {
            unlisten = cleanup;
            audit('local bridge active scope=computers');
        });

        return () => {
            unlisten?.();
        };
    }, []);

    return null;
};
"""


def fail(message: str) -> None:
    raise SystemExit(f"❌ {message}")


def patch_drive_provider(path: Path) -> None:
    source = path.read_text()
    if "ProtonDriveLinuxSyncBridge" not in source:
        source = source.replace(
            "import { PublicSessionProvider } from './_api';\n",
            "import { PublicSessionProvider } from './_api';\nimport { ProtonDriveLinuxSyncBridge } from './ProtonDriveLinuxSyncBridge';\n",
        )
        source = source.replace(
            "                                <UploadProvider>\n                                    <SearchProvider>",
            "                                <UploadProvider>\n                                    <ProtonDriveLinuxSyncBridge />\n                                    <SearchProvider>",
        )
    path.write_text(source)


def main() -> None:
    if not WEBCLIENTS_DIR.exists():
        fail("WebClients directory is missing")

    bridge_path = WEBCLIENTS_DIR / BRIDGE_RELATIVE
    provider_path = WEBCLIENTS_DIR / DRIVE_PROVIDER_RELATIVE
    if not provider_path.exists():
        fail("Unable to find DriveProvider.tsx in current WebClients layout")

    bridge_path.write_text(BRIDGE_SOURCE)
    patch_drive_provider(provider_path)
    print("  ✓ Installed Proton Drive Linux sync bridge")


if __name__ == "__main__":
    main()
