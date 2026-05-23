use base64::Engine as _;
use notify::{Config, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::{mpsc, Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter};

const ERR_SYNC_SETUP_FAILED: &str = "Failed to start live sync";
const ERR_SYNC_STATE_UNAVAILABLE: &str = "Live sync is temporarily unavailable";
const ERR_SYNC_NOT_ACTIVE: &str = "Live sync is not active";
const ERR_SYNC_INVALID_REMOTE_CONTENT: &str = "Invalid remote file content";
const ERR_SYNC_WRITE_FAILED: &str = "Failed to apply remote file update";
const ERR_SYNC_DELETE_FAILED: &str = "Failed to apply remote file deletion";
const ERR_SYNC_INVALID_TARGET: &str = "Invalid sync target path";
const SUPPRESSION_TTL: Duration = Duration::from_secs(30);
const SUPPRESSION_CACHE_MAX: usize = 4096;

#[derive(Debug, Clone, Serialize)]
pub struct LiveSyncEvent {
    pub kind: String,
    pub paths: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct LiveSyncStatus {
    pub enabled: bool,
    pub folder_path: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RemoteSyncChange {
    pub relative_path: String,
    pub action: String,
    pub content_base64: Option<String>,
}

pub struct LiveSyncManager {
    watcher: Mutex<Option<RecommendedWatcher>>,
    folder: Mutex<Option<PathBuf>>,
    root_canonical: Mutex<Option<PathBuf>>,
    worker: Mutex<Option<JoinHandle<()>>>,
    known_files: Arc<Mutex<HashMap<PathBuf, Instant>>>,
}

impl Default for LiveSyncManager {
    fn default() -> Self {
        Self {
            watcher: Mutex::new(None),
            folder: Mutex::new(None),
            root_canonical: Mutex::new(None),
            worker: Mutex::new(None),
            known_files: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

impl LiveSyncManager {
    pub fn start(&self, app: AppHandle, folder: PathBuf) -> Result<(), String> {
        if !folder.exists() || !folder.is_dir() {
            return Err("Sync path must be a directory".into());
        }

        let canonical_root = folder.canonicalize().map_err(|e| {
            eprintln!("[LiveSync] canonicalize root failed for {:?}: {e}", folder);
            ERR_SYNC_SETUP_FAILED.to_string()
        })?;

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

        let known_files = Arc::clone(&self.known_files);
        let app_handle = app.clone();

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
                                if should_ignore_known_file(&known_files, &path) {
                                    continue;
                                }
                                filtered_paths.push(path.to_string_lossy().to_string());
                            }

                            if filtered_paths.is_empty() {
                                continue;
                            }

                            // Regression guard: the frontend sync engine depends on this
                            // exact event name and absolute local paths to upload local
                            // changes. Do not rename or reshape without updating docs,
                            // tests, and the WebClients integration together.
                            if let Err(e) = app_handle.emit(
                                "live-sync://local-change",
                                LiveSyncEvent {
                                    kind: kind.to_string(),
                                    paths: filtered_paths,
                                },
                            ) {
                                eprintln!("[LiveSync] failed to emit local-change event: {e}");
                            }
                        }
                        Err(_) => eprintln!("[LiveSync] Watcher error occurred"),
                    }
                }
            })
            .map_err(|e| {
                eprintln!("[LiveSync] worker thread spawn failed: {e}");
                ERR_SYNC_SETUP_FAILED.to_string()
            })?;

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

        Ok(())
    }

    pub fn status(&self) -> Result<LiveSyncStatus, String> {
        let folder = self.folder.lock().map_err(|e| {
            eprintln!("[LiveSync] status lock failed: {e}");
            ERR_SYNC_STATE_UNAVAILABLE.to_string()
        })?;
        Ok(LiveSyncStatus {
            enabled: folder.is_some(),
            folder_path: folder.as_ref().map(|p| p.to_string_lossy().to_string()),
        })
    }

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

    pub fn stop(&self) -> Result<(), String> {
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

fn validate_path_within_root(root_canonical: &Path, target: &Path) -> Result<(), String> {
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
}
