use crate::sync_db::{self, SyncDb, SyncItemState};
use base64::Engine as _;
use notify::{Config, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::{mpsc, Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tauri::{AppHandle, Emitter, Manager};

const ERR_SYNC_SETUP_FAILED: &str = "Failed to start live sync";
const ERR_SYNC_STATE_UNAVAILABLE: &str = "Live sync is temporarily unavailable";
const ERR_SYNC_NOT_ACTIVE: &str = "Live sync is not active";
const ERR_SYNC_INVALID_REMOTE_CONTENT: &str = "Invalid remote file content";
const ERR_SYNC_WRITE_FAILED: &str = "Failed to apply remote file update";
const ERR_SYNC_DELETE_FAILED: &str = "Failed to apply remote file deletion";
const ERR_SYNC_INVALID_TARGET: &str = "Invalid sync target path";
const SUPPRESSION_TTL: Duration = Duration::from_secs(30);
const SUPPRESSION_CACHE_MAX: usize = 4096;
pub const DEFAULT_SYNC_POLL_INTERVAL: Duration = Duration::from_secs(30);

/// A filesystem change event emitted to the frontend over Tauri's event system.
///
/// This is serialized as JSON and sent on the `"live-sync://local-change"` channel
/// when the file watcher detects a local create, modify, or remove event.
#[derive(Debug, Clone, Serialize)]
pub struct LiveSyncEvent {
    /// One of `"create"`, `"modify"`, or `"remove"`.
    pub kind: String,
    /// Absolute paths of the affected files, filtered to exclude
    /// events that originated from remote-applied changes (self-suppression).
    pub paths: Vec<String>,
    pub root_path: String,
    pub relative_paths: Vec<String>,
    pub source: String,
}

/// The current sync state, returned to the frontend for display / UI binding.
#[derive(Debug, Clone, Serialize)]
pub struct LiveSyncStatus {
    /// Whether the watcher is currently running.
    pub enabled: bool,
    /// The root folder being watched, if sync is active.
    pub folder_path: Option<String>,
    pub poll_interval_seconds: u64,
}

/// A remote file change sent by the Proton server, to be applied locally.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteSyncChange {
    /// Relative path from the sync root (e.g. `"Documents/report.pdf"`).
    pub relative_path: String,
    /// One of `"create"`, `"update"`, or `"delete"`.
    pub action: String,
    /// Base64-encoded file content. Required for `"create"` and `"update"` actions;
    /// ignored for `"delete"`.
    pub content_base64: Option<String>,
}

/// Stateful manager for the local filesystem watcher and remote-change applicator.
///
/// Provides start/stop lifecycle, status queries, and remote change application.
/// Uses `notify` under the hood for cross-platform file watching. Internal state
/// is guarded by `Mutex` for thread-safe access from Tauri command handlers.
pub struct LiveSyncManager {
    watcher: Mutex<Option<RecommendedWatcher>>,
    folder: Mutex<Option<PathBuf>>,
    root_canonical: Mutex<Option<PathBuf>>,
    worker: Mutex<Option<JoinHandle<()>>>,
    poller: Mutex<Option<JoinHandle<()>>>,
    poll_stop: Mutex<Option<mpsc::Sender<()>>>,
    known_files: Arc<Mutex<HashMap<PathBuf, Instant>>>,
}

impl Default for LiveSyncManager {
    fn default() -> Self {
        Self {
            watcher: Mutex::new(None),
            folder: Mutex::new(None),
            root_canonical: Mutex::new(None),
            worker: Mutex::new(None),
            poller: Mutex::new(None),
            poll_stop: Mutex::new(None),
            known_files: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

impl LiveSyncManager {
    /// Start the file watcher on `folder`.
    ///
    /// Spawns a background thread that monitors the directory tree recursively.
    /// Local changes are emitted to the frontend as `"live-sync://local-change"` events.
    /// Returns an error if `folder` does not exist, cannot be canonicalized, or the
    /// watcher fails to initialise (e.g. due to `inotify` limits under Linux).
    pub fn start(&self, app: AppHandle, folder: PathBuf) -> Result<(), String> {
        self.start_with_poll_interval(app, folder, DEFAULT_SYNC_POLL_INTERVAL)
    }

    pub fn start_with_poll_interval(
        &self,
        app: AppHandle,
        folder: PathBuf,
        poll_interval: Duration,
    ) -> Result<(), String> {
        if !folder.exists() || !folder.is_dir() {
            return Err("Sync path must be a directory".into());
        }

        let canonical_root = folder.canonicalize().map_err(|e| {
            eprintln!("[LiveSync] canonicalize root failed for {:?}: {e}", folder);
            ERR_SYNC_SETUP_FAILED.to_string()
        })?;
        let app_data_dir = app.path().app_data_dir().map_err(|e| {
            eprintln!("[LiveSync] app data dir unavailable for sync metadata: {e}");
            ERR_SYNC_SETUP_FAILED.to_string()
        })?;
        let sync_db_path = sync_db::sync_db_path(&app_data_dir);
        let root_id = SyncDb::open(&sync_db_path)?.upsert_root(&folder)?;

        self.stop()?;

        let (tx, rx) = mpsc::channel();
        let mut watcher = RecommendedWatcher::new(tx, Config::default()).map_err(|e| {
            eprintln!("[LiveSync] watcher init failed: {e}");
            ERR_SYNC_SETUP_FAILED.to_string()
        })?;

        watcher
            .watch(&folder, RecursiveMode::Recursive)
            .map_err(|e| {
                eprintln!("[LiveSync] watcher start failed for {:?}: {e}", folder);
                ERR_SYNC_SETUP_FAILED.to_string()
            })?;
        println!(
            "[LiveSync] watcher active root={} mode=recursive",
            folder.to_string_lossy()
        );

        let watcher_known_files = Arc::clone(&self.known_files);
        let watcher_app_handle = app.clone();
        let watcher_root = folder.clone();
        let watcher_db_path = sync_db_path.clone();
        let watcher_root_id = root_id.clone();

        let worker = std::thread::Builder::new()
            .name("live-sync-watcher".to_string())
            .spawn(move || {
                for res in rx {
                    match res {
                        Ok(event) => {
                            let kind = match event.kind {
                                EventKind::Create(_) => "create",
                                EventKind::Modify(_) => "modify",
                                EventKind::Remove(_) => "remove",
                                _ => continue,
                            };

                            let mut filtered_paths = Vec::new();
                            for path in event.paths {
                                if should_ignore_known_file(&watcher_known_files, &path) {
                                    continue;
                                }
                                filtered_paths.push(path.to_string_lossy().to_string());
                            }

                            if filtered_paths.is_empty() {
                                continue;
                            }

                            emit_local_change(
                                &watcher_app_handle,
                                &watcher_db_path,
                                &watcher_root_id,
                                &watcher_root,
                                kind,
                                filtered_paths,
                                "watcher",
                            );
                        }
                        Err(_) => eprintln!("[LiveSync] Watcher error occurred"),
                    }
                }
            })
            .map_err(|e| {
                eprintln!("[LiveSync] worker thread spawn failed: {e}");
                ERR_SYNC_SETUP_FAILED.to_string()
            })?;

        let (poll_stop_tx, poll_stop_rx) = mpsc::channel();
        let poller_known_files = Arc::clone(&self.known_files);
        let poller_app_handle = app;
        let poller_root = folder.clone();
        let poller_db_path = sync_db_path;
        let poller_root_id = root_id;
        let mut snapshot = scan_sync_root(&poller_root).map_err(|e| {
            eprintln!(
                "[LiveSync] poller baseline scan failed for {:?}: {e}",
                poller_root
            );
            ERR_SYNC_SETUP_FAILED.to_string()
        })?;

        let poller = std::thread::Builder::new()
            .name("live-sync-poller".to_string())
            .spawn(move || loop {
                if poll_stop_rx.recv_timeout(poll_interval).is_ok() {
                    break;
                }

                match scan_sync_root(&poller_root) {
                    Ok(next_snapshot) => {
                        for (kind, paths) in diff_snapshots(&snapshot, &next_snapshot) {
                            let filtered_paths: Vec<String> = paths
                                .into_iter()
                                .filter(|path| !should_ignore_known_file(&poller_known_files, path))
                                .map(|path| path.to_string_lossy().to_string())
                                .collect();

                            if !filtered_paths.is_empty() {
                                emit_local_change(
                                    &poller_app_handle,
                                    &poller_db_path,
                                    &poller_root_id,
                                    &poller_root,
                                    kind,
                                    filtered_paths,
                                    "poller",
                                );
                            }
                        }
                        snapshot = next_snapshot;
                    }
                    Err(e) => eprintln!("[LiveSync] poller scan failed: {e}"),
                }
            })
            .map_err(|e| {
                eprintln!("[LiveSync] poller thread spawn failed: {e}");
                ERR_SYNC_SETUP_FAILED.to_string()
            })?;

        println!(
            "[LiveSync] poller active root={} interval_seconds={}",
            folder.to_string_lossy(),
            poll_interval.as_secs()
        );

        *self.watcher.lock().map_err(|e| {
            eprintln!("[LiveSync] watcher state lock failed: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })? = Some(watcher);
        *self.folder.lock().map_err(|e| {
            eprintln!("[LiveSync] folder state lock failed: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })? = Some(folder);
        *self.root_canonical.lock().map_err(|e| {
            eprintln!("[LiveSync] root canonical state lock failed: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })? = Some(canonical_root);
        *self.worker.lock().map_err(|e| {
            eprintln!("[LiveSync] worker state lock failed: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })? = Some(worker);
        *self.poll_stop.lock().map_err(|e| {
            eprintln!("[LiveSync] poll stop state lock failed: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })? = Some(poll_stop_tx);
        *self.poller.lock().map_err(|e| {
            eprintln!("[LiveSync] poller state lock failed: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })? = Some(poller);

        Ok(())
    }

    /// Return the current sync status (enabled/disabled and watched folder path).
    pub fn status(&self) -> Result<LiveSyncStatus, String> {
        let folder = self.folder.lock().map_err(|e| {
            eprintln!("[LiveSync] status lock failed: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })?;
        Ok(LiveSyncStatus {
            enabled: folder.is_some(),
            folder_path: folder.as_ref().map(|p| p.to_string_lossy().to_string()),
            poll_interval_seconds: DEFAULT_SYNC_POLL_INTERVAL.as_secs(),
        })
    }

    /// Apply a remote file change (create, update, or delete) to the local sync directory.
    ///
    /// Validates the path against the sync root to prevent path traversal,
    /// decodes base64 content for writes, and marks the target as a known
    /// file to suppress self-triggered watcher events.
    pub fn apply_remote_change(&self, change: RemoteSyncChange) -> Result<String, String> {
        let root = self
            .folder
            .lock()
            .map_err(|e| {
                eprintln!("[LiveSync] folder lock failed during remote apply: {e}");
                ERR_SYNC_STATE_UNAVAILABLE.to_string()
            })?
            .clone()
            .ok_or(ERR_SYNC_NOT_ACTIVE)?;

        let canonical_root = self
            .root_canonical
            .lock()
            .map_err(|e| {
                eprintln!("[LiveSync] root canonical lock failed during remote apply: {e}");
                ERR_SYNC_STATE_UNAVAILABLE.to_string()
            })?
            .clone()
            .ok_or(ERR_SYNC_NOT_ACTIVE)?;

        let relative = Path::new(&change.relative_path);
        if relative.as_os_str().is_empty() {
            return Err(ERR_SYNC_INVALID_TARGET.into());
        }
        if relative.components().any(|c| {
            matches!(
                c,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        }) {
            return Err(ERR_SYNC_INVALID_TARGET.into());
        }

        let target = root.join(relative);

        match change.action.as_str() {
            "create" | "update" => {
                let encoded = change
                    .content_base64
                    .ok_or("Invalid remote update payload")?;
                let data = base64::engine::general_purpose::STANDARD
                    .decode(encoded)
                    .map_err(|e| {
                        eprintln!("[LiveSync] remote content decode failed: {e}");
                        ERR_SYNC_INVALID_REMOTE_CONTENT.to_string()
                    })?;

                validate_path_within_root(&canonical_root, &target).map_err(|e| {
                    eprintln!(
                        "[LiveSync][AUDIT] rejected remote write action={} path={} reason={}",
                        change.action, change.relative_path, e
                    );
                    ERR_SYNC_INVALID_TARGET.to_string()
                })?;

                if let Some(parent) = target.parent() {
                    fs::create_dir_all(parent).map_err(|e| {
                        eprintln!("[LiveSync] create parent dirs failed for {:?}: {e}", parent);
                        ERR_SYNC_WRITE_FAILED.to_string()
                    })?;
                }

                self.mark_known_file(&target)?;
                fs::write(&target, data).map_err(|e| {
                    eprintln!("[LiveSync] write failed for {:?}: {e}", target);
                    ERR_SYNC_WRITE_FAILED.to_string()
                })?;

                println!(
                    "[LiveSync][AUDIT] remote action={} result=success path={}",
                    change.action, change.relative_path
                );
            }
            "delete" => {
                validate_path_within_root(&canonical_root, &target).map_err(|e| {
                    eprintln!(
                        "[LiveSync][AUDIT] rejected remote delete path={} reason={}",
                        change.relative_path, e
                    );
                    ERR_SYNC_INVALID_TARGET.to_string()
                })?;

                if target.exists() {
                    self.mark_known_file(&target)?;
                    fs::remove_file(&target).map_err(|e| {
                        eprintln!("[LiveSync] delete failed for {:?}: {e}", target);
                        ERR_SYNC_DELETE_FAILED.to_string()
                    })?;
                }

                println!(
                    "[LiveSync][AUDIT] remote action=delete result=success path={}",
                    change.relative_path
                );
            }
            _ => return Err("Unknown action".into()),
        }

        Ok(target.to_string_lossy().to_string())
    }

    /// Stop the file watcher and clear all sync state.
    ///
    /// Drops the `notify` watcher, joins the background worker thread, and clears
    /// the suppression cache. Safe to call when sync is already stopped.
    pub fn stop(&self) -> Result<(), String> {
        let poll_stop = self
            .poll_stop
            .lock()
            .map_err(|e| {
                eprintln!("[LiveSync] poll stop state lock failed on stop: {e}");
                ERR_SYNC_STATE_UNAVAILABLE.to_string()
            })?
            .take();
        if let Some(poll_stop) = poll_stop {
            let _ = poll_stop.send(());
        }

        *self.watcher.lock().map_err(|e| {
            eprintln!("[LiveSync] watcher state lock failed on stop: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })? = None;
        *self.folder.lock().map_err(|e| {
            eprintln!("[LiveSync] folder state lock failed on stop: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })? = None;
        *self.root_canonical.lock().map_err(|e| {
            eprintln!("[LiveSync] root canonical state lock failed on stop: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })? = None;

        let worker = self
            .worker
            .lock()
            .map_err(|e| {
                eprintln!("[LiveSync] worker state lock failed on stop: {e}");
                ERR_SYNC_STATE_UNAVAILABLE.to_string()
            })?
            .take();
        if let Some(worker) = worker {
            let _ = worker.join();
        }

        let poller = self
            .poller
            .lock()
            .map_err(|e| {
                eprintln!("[LiveSync] poller state lock failed on stop: {e}");
                ERR_SYNC_STATE_UNAVAILABLE.to_string()
            })?
            .take();
        if let Some(poller) = poller {
            let _ = poller.join();
        }

        self.known_files
            .lock()
            .map_err(|e| {
                eprintln!("[LiveSync] known_files lock failed on stop: {e}");
                ERR_SYNC_STATE_UNAVAILABLE.to_string()
            })?
            .clear();

        Ok(())
    }

    fn mark_known_file(&self, path: &Path) -> Result<(), String> {
        let mut cache = self.known_files.lock().map_err(|e| {
            eprintln!("[LiveSync] known_files lock failed on mark: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })?;
        let now = Instant::now();
        prune_known_files(&mut cache, now);
        cache.insert(path.to_path_buf(), now);
        Ok(())
    }
}

fn should_ignore_known_file(
    known_files: &Arc<Mutex<HashMap<PathBuf, Instant>>>,
    path: &Path,
) -> bool {
    if let Ok(mut cache) = known_files.lock() {
        let now = Instant::now();
        prune_known_files(&mut cache, now);
        if let Some(marked_at) = cache.remove(path) {
            return now.saturating_duration_since(marked_at) <= SUPPRESSION_TTL;
        }
        false
    } else {
        false
    }
}

fn emit_local_change(
    app_handle: &AppHandle,
    db_path: &Path,
    root_id: &str,
    root: &Path,
    kind: &str,
    paths: Vec<String>,
    source: &str,
) {
    println!(
        "[LiveSync] local-change kind={} paths={} source={}",
        kind,
        paths.len(),
        source
    );
    for path in &paths {
        println!("[LiveSync] local-change path={}", path);
    }

    let relative_paths = paths
        .iter()
        .map(|path| relative_sync_path(root, Path::new(path)))
        .collect();
    if let Err(e) = record_local_change_metadata(db_path, root_id, root, kind, &paths) {
        eprintln!(
            "[LiveSync][AUDIT] local metadata record failed reason={}",
            e
        );
    }

    // Regression guard: the frontend sync engine depends on this exact event
    // name. Payloads are intentionally mapping-ready: absolute paths are kept
    // for compatibility, while rootPath/relativePaths/source let future UI and
    // path-mapping code consume the native sync stream without route coupling.
    if let Err(e) = app_handle.emit(
        "live-sync://local-change",
        LiveSyncEvent {
            kind: kind.to_string(),
            paths,
            root_path: root.to_string_lossy().to_string(),
            relative_paths,
            source: source.to_string(),
        },
    ) {
        eprintln!("[LiveSync] failed to emit local-change event: {e}");
    }
}

fn record_local_change_metadata(
    db_path: &Path,
    root_id: &str,
    root: &Path,
    kind: &str,
    paths: &[String],
) -> Result<(), String> {
    let db = SyncDb::open(db_path)?;
    for path in paths {
        let path = Path::new(path);
        let relative = Path::new(&relative_sync_path(root, path)).to_path_buf();
        if kind == "remove" {
            db.mark_tombstone(root_id, &relative)?;
            continue;
        }

        let metadata = fs::symlink_metadata(path).ok();
        let local_kind = metadata
            .as_ref()
            .map(|meta| if meta.is_dir() { "dir" } else { "file" })
            .unwrap_or("unknown");
        let local_size = metadata
            .as_ref()
            .filter(|meta| meta.is_file())
            .map(|meta| meta.len().min(i64::MAX as u64) as i64);
        let local_mtime_ns = metadata
            .as_ref()
            .and_then(|meta| meta.modified().ok())
            .and_then(system_time_nanos)
            .map(|ns| ns.min(i64::MAX as u128) as i64);

        db.upsert_local_item(
            root_id,
            &relative,
            local_kind,
            local_size,
            local_mtime_ns,
            None,
            SyncItemState::LocalPending,
        )?;
    }
    Ok(())
}

fn relative_sync_path(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .to_string()
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct FileFingerprint {
    len: u64,
    modified: Option<u128>,
}

type SyncSnapshot = HashMap<PathBuf, FileFingerprint>;

fn scan_sync_root(root: &Path) -> std::io::Result<SyncSnapshot> {
    let mut snapshot = HashMap::new();
    scan_sync_dir(root, &mut snapshot)?;
    Ok(snapshot)
}

fn scan_sync_dir(dir: &Path, snapshot: &mut SyncSnapshot) -> std::io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let meta = fs::symlink_metadata(&path)?;

        if meta.file_type().is_symlink() {
            continue;
        }

        if meta.is_dir() {
            scan_sync_dir(&path, snapshot)?;
        } else if meta.is_file() {
            snapshot.insert(
                path,
                FileFingerprint {
                    len: meta.len(),
                    modified: meta.modified().ok().and_then(system_time_nanos),
                },
            );
        }
    }
    Ok(())
}

fn system_time_nanos(time: SystemTime) -> Option<u128> {
    time.duration_since(UNIX_EPOCH)
        .ok()
        .map(|duration| duration.as_nanos())
}

fn diff_snapshots(
    previous: &SyncSnapshot,
    next: &SyncSnapshot,
) -> Vec<(&'static str, Vec<PathBuf>)> {
    let previous_paths: HashSet<&PathBuf> = previous.keys().collect();
    let next_paths: HashSet<&PathBuf> = next.keys().collect();

    let mut creates = Vec::new();
    let mut modifies = Vec::new();
    let mut removes = Vec::new();

    for path in next_paths.difference(&previous_paths) {
        creates.push((*path).clone());
    }

    for path in previous_paths.intersection(&next_paths) {
        if previous.get(*path) != next.get(*path) {
            modifies.push((*path).clone());
        }
    }

    for path in previous_paths.difference(&next_paths) {
        removes.push((*path).clone());
    }

    let mut changes = Vec::new();
    if !creates.is_empty() {
        changes.push(("create", creates));
    }
    if !modifies.is_empty() {
        changes.push(("modify", modifies));
    }
    if !removes.is_empty() {
        changes.push(("remove", removes));
    }
    changes
}

fn prune_known_files(cache: &mut HashMap<PathBuf, Instant>, now: Instant) {
    cache.retain(|_, marked_at| now.saturating_duration_since(*marked_at) <= SUPPRESSION_TTL);
    if cache.len() <= SUPPRESSION_CACHE_MAX {
        return;
    }

    // If burst volume still exceeds cap, drop oldest markers first.
    let mut by_age: Vec<(PathBuf, Instant)> = cache.iter().map(|(p, t)| (p.clone(), *t)).collect();
    by_age.sort_by_key(|(_, t)| *t);
    let overflow = by_age.len() - SUPPRESSION_CACHE_MAX;
    for (path, _) in by_age.into_iter().take(overflow) {
        cache.remove(&path);
    }
}

pub(crate) fn validate_path_within_root(root_canonical: &Path, target: &Path) -> Result<(), String> {
    let mut cur = PathBuf::new();
    for component in target.components() {
        cur.push(component.as_os_str());
        if let Ok(meta) = fs::symlink_metadata(&cur) {
            if meta.file_type().is_symlink() {
                return Err("symlink traversal is not allowed".to_string());
            }
        }
    }

    let canonical_target = if target.exists() {
        target
            .canonicalize()
            .map_err(|_| "unable to resolve target path".to_string())?
    } else {
        let existing_ancestor = find_existing_ancestor(target)
            .ok_or_else(|| "target has no existing ancestor".to_string())?;
        let canonical_ancestor = existing_ancestor
            .canonicalize()
            .map_err(|_| "unable to resolve ancestor path".to_string())?;

        if !canonical_ancestor.starts_with(root_canonical) {
            return Err("target escapes sync root".to_string());
        }

        return Ok(());
    };

    if !canonical_target.starts_with(root_canonical) {
        return Err("target escapes sync root".to_string());
    }

    Ok(())
}

fn find_existing_ancestor(path: &Path) -> Option<PathBuf> {
    let mut current = path.to_path_buf();
    while !current.exists() {
        if !current.pop() {
            return None;
        }
    }
    Some(current)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_sync_root(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("proton-drive-live-sync-{name}-{nonce}"));
        fs::create_dir_all(&root).unwrap();
        root
    }

    #[test]
    fn remote_change_serde_uses_frontend_camel_case_contract() {
        let change: RemoteSyncChange = serde_json::from_str(
            r#"{"relativePath":"Pictures/test.jpg","action":"update","contentBase64":"aGVsbG8="}"#,
        )
        .unwrap();

        assert_eq!(change.relative_path, "Pictures/test.jpg");
        assert_eq!(change.action, "update");
        assert_eq!(change.content_base64.as_deref(), Some("aGVsbG8="));
    }

    #[test]
    fn sync_target_accepts_new_file_under_root() {
        let root = temp_sync_root("new-file");
        let target = root.join("Pictures").join("camera").join("image.jpg");
        let canonical_root = root.canonicalize().unwrap();

        assert!(validate_path_within_root(&canonical_root, &target).is_ok());

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn sync_target_rejects_existing_file_outside_root() {
        let root = temp_sync_root("escape-root");
        let outside = temp_sync_root("outside-root").join("image.jpg");
        fs::write(&outside, b"outside").unwrap();
        let canonical_root = root.canonicalize().unwrap();

        assert!(validate_path_within_root(&canonical_root, &outside).is_err());

        fs::remove_dir_all(root).unwrap();
        fs::remove_dir_all(outside.parent().unwrap()).unwrap();
    }

    #[test]
    #[cfg(unix)]
    fn sync_target_rejects_symlink_traversal() {
        use std::os::unix::fs as unix_fs;

        let root = temp_sync_root("symlink-root");
        let outside = temp_sync_root("symlink-outside");
        let link = root.join("Pictures").join("linked");
        fs::create_dir_all(link.parent().unwrap()).unwrap();
        unix_fs::symlink(&outside, &link).unwrap();
        let target = link.join("image.jpg");
        let canonical_root = root.canonicalize().unwrap();

        assert!(validate_path_within_root(&canonical_root, &target).is_err());

        fs::remove_dir_all(root).unwrap();
        fs::remove_dir_all(outside).unwrap();
    }

    #[test]
    fn suppression_cache_drops_remote_write_marker_once() {
        let known_files = Arc::new(Mutex::new(HashMap::new()));
        let path = PathBuf::from("/tmp/proton-drive-live-sync-marker");

        known_files
            .lock()
            .unwrap()
            .insert(path.clone(), Instant::now());

        assert!(should_ignore_known_file(&known_files, &path));
        assert!(!should_ignore_known_file(&known_files, &path));
    }

    #[test]
    fn suppression_cache_is_bounded() {
        let mut cache = HashMap::new();
        let now = Instant::now();

        for idx in 0..(SUPPRESSION_CACHE_MAX + 10) {
            cache.insert(PathBuf::from(format!("/tmp/file-{idx}")), now);
        }

        prune_known_files(&mut cache, now);
        assert!(cache.len() <= SUPPRESSION_CACHE_MAX);
    }

    #[test]
    fn relative_sync_path_is_root_relative_for_mapping() {
        let root = PathBuf::from("/home/test/Pictures/protondrive-sync-smoke");
        let file = root.join("nested").join("image.jpg");

        assert_eq!(relative_sync_path(&root, &file), "nested/image.jpg");
    }

    #[test]
    fn poll_snapshot_diff_detects_create_modify_and_remove() {
        let created = PathBuf::from("/tmp/created.txt");
        let modified = PathBuf::from("/tmp/modified.txt");
        let removed = PathBuf::from("/tmp/removed.txt");

        let mut previous = HashMap::new();
        previous.insert(
            modified.clone(),
            FileFingerprint {
                len: 1,
                modified: Some(1),
            },
        );
        previous.insert(
            removed.clone(),
            FileFingerprint {
                len: 1,
                modified: Some(1),
            },
        );

        let mut next = HashMap::new();
        next.insert(
            created.clone(),
            FileFingerprint {
                len: 1,
                modified: Some(1),
            },
        );
        next.insert(
            modified.clone(),
            FileFingerprint {
                len: 2,
                modified: Some(2),
            },
        );

        let changes = diff_snapshots(&previous, &next);

        assert!(changes
            .iter()
            .any(|(kind, paths)| kind == &"create" && paths == &vec![created.clone()]));
        assert!(changes
            .iter()
            .any(|(kind, paths)| kind == &"modify" && paths == &vec![modified.clone()]));
        assert!(changes
            .iter()
            .any(|(kind, paths)| kind == &"remove" && paths == &vec![removed.clone()]));
    }

    #[test]
    fn local_change_metadata_records_pending_items_and_safe_tombstones() {
        let root = temp_sync_root("metadata");
        let db_path = root.join(".sync-state.sqlite3");
        let db = SyncDb::open(&db_path).unwrap();
        let root_id = db.upsert_root(&root).unwrap();
        drop(db);

        let file = root.join("folder").join("local.txt");
        fs::create_dir_all(file.parent().unwrap()).unwrap();
        fs::write(&file, b"local").unwrap();

        record_local_change_metadata(
            &db_path,
            &root_id,
            &root,
            "create",
            &[file.to_string_lossy().to_string()],
        )
        .unwrap();

        let db = SyncDb::open(&db_path).unwrap();
        let item = db
            .get_item(&root_id, Path::new("folder/local.txt"))
            .unwrap()
            .unwrap();
        assert_eq!(item.state, SyncItemState::LocalPending);
        assert_eq!(item.local_kind, "file");
        drop(db);

        fs::remove_file(&file).unwrap();
        record_local_change_metadata(
            &db_path,
            &root_id,
            &root,
            "remove",
            &[file.to_string_lossy().to_string()],
        )
        .unwrap();

        let db = SyncDb::open(&db_path).unwrap();
        let item = db
            .get_item(&root_id, Path::new("folder/local.txt"))
            .unwrap()
            .unwrap();
        assert_eq!(item.state, SyncItemState::Tombstone);

        fs::remove_dir_all(root).unwrap();
    }
}
