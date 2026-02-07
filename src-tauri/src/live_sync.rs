use base64::Engine as _;
use notify::{Config, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::{mpsc, Arc, Mutex};
use std::thread::JoinHandle;
use tauri::{AppHandle, Emitter};

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
    pub action: String, // create, update, delete
    pub content_base64: Option<String>,
}

pub struct LiveSyncManager {
    watcher: Mutex<Option<RecommendedWatcher>>,
    folder: Mutex<Option<PathBuf>>,
    worker: Mutex<Option<JoinHandle<()>>>,
    known_files: Arc<Mutex<HashSet<PathBuf>>>,
}

impl Default for LiveSyncManager {
    fn default() -> Self {
        Self {
            watcher: Mutex::new(None),
            folder: Mutex::new(None),
            worker: Mutex::new(None),
            known_files: Arc::new(Mutex::new(HashSet::new())),
        }
    }
}

impl LiveSyncManager {
    pub fn start(&self, app: AppHandle, folder: PathBuf) -> Result<(), String> {
        if !folder.exists() || !folder.is_dir() {
            return Err("Sync path must be a directory".into());
        }

        self.stop()?;

        let (tx, rx) = mpsc::channel();
        let mut watcher =
            RecommendedWatcher::new(tx, Config::default()).map_err(|e| e.to_string())?;

        watcher
            .watch(&folder, RecursiveMode::Recursive)
            .map_err(|e| e.to_string())?;

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

                            let _ = app_handle.emit(
                                "live-sync://local-change",
                                LiveSyncEvent {
                                    kind: kind.to_string(),
                                    paths: filtered_paths,
                                },
                            );
                        }
                        Err(e) => eprintln!("[LiveSync] Watcher error: {e:?}"),
                    }
                }
            })
            .map_err(|e| format!("Failed to start watcher thread: {e}"))?;

        *self.watcher.lock().map_err(|_| "Watcher lock poisoned")? = Some(watcher);
        *self.folder.lock().map_err(|_| "Folder lock poisoned")? = Some(folder);
        *self.worker.lock().map_err(|_| "Worker lock poisoned")? = Some(worker);

        Ok(())
    }

    pub fn status(&self) -> Result<LiveSyncStatus, String> {
        let folder = self.folder.lock().map_err(|_| "Folder lock poisoned")?;
        Ok(LiveSyncStatus {
            enabled: folder.is_some(),
            folder_path: folder.as_ref().map(|p| p.to_string_lossy().to_string()),
        })
    }

    pub fn apply_remote_change(&self, change: RemoteSyncChange) -> Result<String, String> {
        let root = self
            .folder
            .lock()
            .map_err(|_| "Folder lock poisoned")?
            .clone()
            .ok_or("Live sync is not active")?;

        let relative = Path::new(&change.relative_path);
        if relative.as_os_str().is_empty() {
            return Err("Invalid relative path".into());
        }
        if relative.components().any(|c| {
            matches!(
                c,
                Component::ParentDir | Component::RootDir | Component::Prefix(_)
            )
        }) {
            return Err("Invalid relative path".into());
        }

        let target = root.join(relative);

        match change.action.as_str() {
            "create" | "update" => {
                let encoded = change
                    .content_base64
                    .ok_or("contentBase64 is required for create/update")?;
                let data = base64::engine::general_purpose::STANDARD
                    .decode(encoded)
                    .map_err(|e| e.to_string())?;

                if let Some(parent) = target.parent() {
                    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
                }

                self.mark_known_file(&target)?;
                fs::write(&target, data).map_err(|e| e.to_string())?;
            }
            "delete" => {
                if target.exists() {
                    self.mark_known_file(&target)?;
                    fs::remove_file(&target).map_err(|e| e.to_string())?;
                }
            }
            _ => return Err("Unknown action".into()),
        }

        Ok(target.to_string_lossy().to_string())
    }

    pub fn stop(&self) -> Result<(), String> {
        *self.watcher.lock().map_err(|_| "Watcher lock poisoned")? = None;
        *self.folder.lock().map_err(|_| "Folder lock poisoned")? = None;

        let worker = self
            .worker
            .lock()
            .map_err(|_| "Worker lock poisoned")?
            .take();
        if let Some(worker) = worker {
            let _ = worker.join();
        }

        self.known_files
            .lock()
            .map_err(|_| "Known files lock poisoned")?
            .clear();

        Ok(())
    }

    fn mark_known_file(&self, path: &Path) -> Result<(), String> {
        self.known_files
            .lock()
            .map_err(|_| "Known files lock poisoned")?
            .insert(path.to_path_buf());
        Ok(())
    }
}

fn should_ignore_known_file(known_files: &Arc<Mutex<HashSet<PathBuf>>>, path: &Path) -> bool {
    if let Ok(mut cache) = known_files.lock() {
        cache.remove(path)
    } else {
        false
    }
}
