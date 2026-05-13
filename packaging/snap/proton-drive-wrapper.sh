#!/bin/bash
export LD_LIBRARY_PATH="$SNAP/lib:$SNAP/usr/lib:$SNAP/lib/x86_64-linux-gnu:$SNAP/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
export WEBKIT_INJECTED_BUNDLE_PATH="$SNAP/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/injected-bundle"
export GDK_GL=disable
export LIBGL_ALWAYS_SOFTWARE=1
export GSK_RENDERER=cairo
exec "$SNAP/usr/bin/proton-drive" "$@"
