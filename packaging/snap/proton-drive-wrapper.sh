#!/bin/bash
export LIBGL_ALWAYS_SOFTWARE=1
export __EGL_VENDOR_LIBRARY_FILENAMES="$SNAP/usr/share/glvnd/egl_vendor.d/50_mesa.json"
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export JSC_useWasmIPInt=false
export WEBKIT_NETWORK_PROCESS_PATH="$SNAP/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/WebKitNetworkProcess"
export WEBKIT_WEB_PROCESS_PATH="$SNAP/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/WebKitWebProcess"
export WEBKIT_GPU_PROCESS_PATH="$SNAP/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/WebKitGPUProcess"
export WEBKIT_INJECTED_BUNDLE_PATH="$SNAP/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/injected-bundle"
export GDK_GL=software
export GSK_RENDERER=cairo
exec "$SNAP/usr/bin/proton-drive" "$@"
