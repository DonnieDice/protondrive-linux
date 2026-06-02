#!/bin/bash
# Restore WebClients from CI cache if available; otherwise clone from GitHub.
# Cache key is WEBCLIENTS_COMMIT so the same pinned commit is never re-cloned.
set -e

COMMIT="${WEBCLIENTS_COMMIT:-}"
REF="${WEBCLIENTS_REF:-main}"
TARGET="WebClients"

if [ -d "$TARGET/.git" ] && [ -n "$COMMIT" ]; then
    if git -C "$TARGET" cat-file -e "${COMMIT}^{commit}" 2>/dev/null; then
        echo "WebClients: cache hit — ${COMMIT}"
        git -C "$TARGET" checkout --detach "$COMMIT" --quiet 2>/dev/null || true
        exit 0
    fi
fi

echo "WebClients: cloning (cache miss — ${COMMIT:-<branch $REF>})"
rm -rf "$TARGET"
git clone --filter=blob:none --no-checkout https://github.com/ProtonMail/WebClients.git "$TARGET"

if [ -n "$COMMIT" ]; then
    git -C "$TARGET" fetch --depth=1 origin "$COMMIT"
    git -C "$TARGET" checkout --detach "$COMMIT"
else
    git -C "$TARGET" fetch --depth=1 origin "$REF"
    git -C "$TARGET" checkout --detach FETCH_HEAD
fi
