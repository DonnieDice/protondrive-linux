# Rollback / Incident Process

If a bad release ships, each publish channel has a different pull/supersede mechanism.
None of them let you delete a tag from user systems — the goal is always to push a
superceding version as fast as possible.

---

## Decision tree

```
Bad release confirmed
│
├── Security vulnerability?
│   └── YES → follow SECURITY.md private disclosure + patch immediately, skip RC
│
├── Data-loss or corruption risk?
│   └── YES → yank from stores if possible (see per-store below), patch as hotfix
│
└── Functional regression, no data risk
    └── Fix via normal MR → tag flow (RC gate still required)
```

A hotfix bypasses the RC stage only for security or data-loss class bugs. Everything
else goes through the normal RC gate.

---

## Per-store rollback

### AUR

AUR does not support yanking. Users pull and build the latest PKGBUILD. To supersede:

1. Push a new `vX.Y.Z+1` tag — this triggers the full pipeline.
2. After CI passes, trigger `publish:aur` manually. The AUR repo git push updates
   the PKGBUILD and `.SRCINFO`; `pacman -Syu` will pick up the fix.
3. The bad build stays in users' local caches but `pacman` won't install it on a
   fresh system once the PKGBUILD version is bumped.

There is no way to force-remove a version from users who already installed it. If the
bug is severe, file a security advisory and contact the Arch security team at
`security@archlinux.org`.

### Flathub

Flathub supports a stale-build block. To supersede:

1. Push a new version tag → pipeline → `publish:flatpak` (manual).
2. Flathub serves the new `.flatpakref` immediately on merge. Users get the update
   via `flatpak update`.

To block a bad build before superseding: open a PR against `flathub/com.proton.drive`
and set `end-of-life: true` + `end-of-life-rebase: com.proton.drive//stable` in the
appstream metadata. This marks the app as EOL on older versions and pushes the rebase
message to users via GNOME Software / KDE Discover. Revert that commit once the fix is
published.

The `FLATHUB_SSH_PRIVATE_KEY` secret controls the git push. If the key is compromised,
rotate it immediately (see Secret Rotation below) and re-add the new public key to the
`flathub/com.proton.drive` repo deploy keys.

### Snap Store

**Note: Snap publishing is currently blocked** (see issues #83 and #19, snapcraft CLI /
Snap Store API inconsistency). When unblocked, the rollback mechanism is:

1. In the Snap Store dashboard, promote the last known-good revision to the `stable`
   channel: `snapcraft promote --from-channel=stable --to-channel=stable <revision>`.
2. Or revert via `snapcraft release proton-drive <good-revision> stable`.
3. Push a fixed version tag → pipeline → `publish:snap` to restore forward progress.

The bad revision stays in the store but is no longer served to `stable` channel users.

---

## Hotfix branch flow

For security / data-loss class bugs that must skip the RC gate:

```
1. Branch from the bad tag: git checkout -b fix/N-hotfix-description vX.Y.Z
2. Apply the minimal fix — no unrelated changes.
3. MR → main, gates must be green.
4. Bump version to vX.Y.Z+1 (patch bump).
5. Tag vX.Y.Z+1 directly — no RC tag.  Document the bypass in the tag message.
6. Trigger publish jobs manually after CI passes.
7. File a post-mortem (see below).
```

Document the bypass in the tag annotation:
```
git tag -a vX.Y.Z+1 -m "hotfix: <one-line description>; RC skipped — security class"
```

---

## Post-mortem

Any hotfix or store-yank triggers a post-mortem. File it as a GitLab issue with:

- Timeline (when shipped, when detected, when mitigated)
- Root cause
- What the RC gate missed and why
- Action item to prevent recurrence (add a test, add a smoke check, update the
  release checklist)

A post-mortem is not a blame document. Its output is one concrete checklist item.

---

## Secret rotation (on suspected compromise)

See the secret rotation section in `docs/SECURITY.md`. Rotate immediately; do not wait
for the next scheduled rotation.

After rotating any publish key, re-run the affected publish job with the new secret to
confirm connectivity before the next release.
