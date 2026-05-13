#!/bin/bash
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export GDK_GL=software
export WEBKIT_NETWORK_PROCESS_PATH="$SNAP/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/WebKitNetworkProcess"
export WEBKIT_WEB_PROCESS_PATH="$SNAP/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/WebKitWebProcess"
export WEBKIT_GPU_PROCESS_PATH="$SNAP/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/WebKitGPUProcess"
export WEBKIT_INJECTED_BUNDLE_PATH="$SNAP/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/injected-bundle"
exec "$SNAP/usr/bin/proton-drive" "$@"
