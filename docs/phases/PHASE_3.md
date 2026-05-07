# Phase 3: GUI Development

**Duration**: 5-7 days  
**Status**: ❌ Blocked by Phase 2  
**Dependencies**: Phase 2 (Core API & Sync) complete  
**Unlocks**: Phase 4

---

## OVERVIEW

Implement Fyne-based graphical user interface.

**Entry Criteria**: 
- Phase 2 complete
- CLI fully functional
- Authentication, file ops, and sync working

**Exit Criteria**:
- Full GUI functional
- All screens implemented
- Usable by end users
- All tests passing

---

## INTERNAL DEPENDENCIES

```
2.1 Client ───────┬──► 3.1 App Framework ──┬──► 3.2 Login Screen
2.3 Sync Engine ──┘           │            ├──► 3.3 Main View
1.1 Config ───────────────────┤            ├──► 3.4 Settings
                              │            ├──► 3.5 System Tray
                              └────────────┴──► 3.6 Notifications
```

---

## 3.1 APPLICATION FRAMEWORK

**Dependencies**: 2.1 (Client), 2.3 (Sync Engine)  
**Output**: `internal/gui/app.go`, `internal/gui/theme.go`  
**Estimated Time**: 0.5 days

### Tasks

- [ ] 🏗️ **Create `internal/gui/app.go`**
  - [ ] `App` struct:
    ```go
    type App struct {
        fyneApp    fyne.App
        mainWindow fyne.Window
        
        client     *client.Client
        syncEngine *sync.SyncEngine
        config     *config.Config
        store      storage.Store
        
        // Current view state
        currentView View
        viewMu      sync.RWMutex
    }
    ```
  - [ ] `NewApp(client, syncEngine, config, store) (*App, error)`
  - [ ] `Run() error`
    - Create Fyne app
    - Check if logged in → show main or login
    - Run main loop
  - [ ] `Quit()`
    - Save state
    - Stop sync engine
    - Close gracefully
  - [ ] `ShowView(view View)`
    - Switch between views
  - [ ] `ShowError(title, message string)`
  - [ ] `ShowNotification(title, message string)`

- [ ] 🏗️ **Create `internal/gui/theme.go`**
  - [ ] Custom Fyne theme:
    ```go
    type ProtonTheme struct {
        variant fyne.ThemeVariant
    }
    ```
  - [ ] Implement `fyne.Theme` interface
  - [ ] Colors matching Proton brand
  - [ ] `NewProtonTheme(variant string) *ProtonTheme`
    - "dark", "light", "system"
  - [ ] `DetectSystemTheme() string`

- [ ] 🏗️ **Create `internal/gui/views.go`**
  - [ ] `View` interface:
    ```go
    type View interface {
        Content() fyne.CanvasObject
        OnShow()
        OnHide()
        Refresh()
    }
    ```

- [ ] 🧪 **Create `internal/gui/app_test.go`**
  - [ ] `TestNewApp` - creates app
  - [ ] `TestAppQuit` - quits cleanly

- [ ] 🧪 **Create `internal/gui/theme_test.go`**
  - [ ] `TestProtonTheme_Dark`
  - [ ] `TestProtonTheme_Light`

### Acceptance Criteria
- [ ] App initializes correctly
- [ ] Theme applies to all components
- [ ] View switching works
- [ ] Clean shutdown

---

## 3.2 LOGIN SCREEN

**Dependencies**: 3.1 (Framework), 2.1 (Auth)  
**Output**: `internal/gui/login.go`  
**Estimated Time**: 1 day

### Tasks

- [ ] 🏗️ **Create `internal/gui/login.go`**
  - [ ] `LoginView` struct implementing `View`:
    ```go
    type LoginView struct {
        app *App
        
        usernameEntry *widget.Entry
        passwordEntry *widget.Entry
        rememberCheck *widget.Check
        loginButton   *widget.Button
        errorLabel    *widget.Label
        spinner       *widget.ProgressBarInfinite
    }
    ```
  - [ ] `NewLoginView(app *App) *LoginView`
  - [ ] `Content() fyne.CanvasObject`
    - Logo/branding
    - Username field
    - Password field (password mode)
    - "Remember me" checkbox
    - Login button
    - Error message area
    - Loading spinner (hidden initially)
  - [ ] `OnShow()` - focus username field
  - [ ] `OnHide()` - clear password field
  - [ ] `Refresh()` - update state
  - [ ] `onLoginClick()`
    - Validate inputs
    - Show spinner
    - Attempt login in goroutine
    - On success: switch to main view
    - On error: show error message
  - [ ] Input validation:
    - Username not empty
    - Password not empty
    - Show validation errors inline

- [ ] 🔒 **Security requirements**:
  - [ ] Password field uses `widget.PasswordEntry`
  - [ ] Password cleared from memory after use
  - [ ] Password never logged
  - [ ] "Remember me" stores session, not password

- [ ] 🏗️ **Create `internal/gui/login_2fa.go`** (if needed)
  - [ ] 2FA code entry dialog
  - [ ] `Show2FADialog() string` - returns entered code

- [ ] 🧪 **Create `internal/gui/login_test.go`**
  - [ ] `TestLoginView_Content` - all elements present
  - [ ] `TestLoginView_Validation` - validates input
  - [ ] `TestLoginView_PasswordCleared` - password wiped after use
  - [ ] `TestLoginView_ErrorDisplay` - shows errors

### Acceptance Criteria
- [ ] Login screen matches Proton branding
- [ ] Input validation works
- [ ] Loading state shown during login
- [ ] Errors displayed clearly
- [ ] Password never persisted
- [ ] "Remember me" works correctly

---

## 3.3 MAIN VIEW (FILE BROWSER)

**Dependencies**: 3.1 (Framework), 2.3 (Sync Engine)  
**Output**: `internal/gui/mainview.go`, `internal/gui/filelist.go`, `internal/gui/toolbar.go`  
**Estimated Time**: 2 days

### Tasks

- [ ] 🏗️ **Create `internal/gui/mainview.go`**
  - [ ] `MainView` struct:
    ```go
    type MainView struct {
        app *App
        
        toolbar  *Toolbar
        fileList *FileList
        statusBar *StatusBar
        
        currentPath string
    }
    ```
  - [ ] `NewMainView(app *App) *MainView`
  - [ ] `Content() fyne.CanvasObject`
    - Toolbar at top
    - File list in center (scrollable)
    - Status bar at bottom
  - [ ] `OnShow()` - refresh file list
  - [ ] `OnHide()`
  - [ ] `Refresh()` - update from sync state
  - [ ] `NavigateTo(path string)` - change current folder

- [ ] 🏗️ **Create `internal/gui/filelist.go`**
  - [ ] `FileList` struct:
    ```go
    type FileList struct {
        widget.BaseWidget
        
        files    []*FileItem
        selected *FileItem
        sortBy   string // name, size, date, status
        sortAsc  bool
        
        onSelect    func(*FileItem)
        onOpen      func(*FileItem)
        onContext   func(*FileItem, fyne.Position)
    }
    ```
  - [ ] `FileItem` struct:
    ```go
    type FileItem struct {
        Info       *client.FileInfo
        SyncStatus string
        Icon       fyne.Resource
    }
    ```
  - [ ] `NewFileList() *FileList`
  - [ ] `SetFiles(files []*FileItem)`
  - [ ] `Sort(by string, ascending bool)`
  - [ ] `GetSelected() *FileItem`
  - [ ] Column headers: Name, Size, Modified, Status
  - [ ] Icons for file types
  - [ ] Sync status indicators (synced, syncing, pending, error)
  - [ ] Double-click to open folder
  - [ ] Right-click context menu

- [ ] 🏗️ **Create `internal/gui/toolbar.go`**
  - [ ] `Toolbar` struct with buttons:
    - Back (navigate up)
    - Forward (if applicable)
    - Upload
    - Download
    - New Folder
    - Delete
    - Refresh
    - Settings
  - [ ] `NewToolbar(callbacks ToolbarCallbacks) *Toolbar`
  - [ ] Disable buttons based on selection state

- [ ] 🏗️ **Create `internal/gui/statusbar.go`**
  - [ ] `StatusBar` struct:
    ```go
    type StatusBar struct {
        widget.BaseWidget
        
        statusLabel   *widget.Label
        progressBar   *widget.ProgressBar
        storageLabel  *widget.Label
    }
    ```
  - [ ] Show: sync status, progress, storage used
  - [ ] `SetStatus(status SyncStatus)`
  - [ ] `SetProgress(percent float64)`
  - [ ] `SetStorage(used, total int64)`

- [ ] 🏗️ **Create `internal/gui/contextmenu.go`**
  - [ ] Context menu items:
    - Open
    - Download
    - Rename
    - Move
    - Delete
    - Properties
  - [ ] `ShowContextMenu(item *FileItem, pos fyne.Position)`

- [ ] 🏗️ **Create `internal/gui/dialogs.go`**
  - [ ] `ShowUploadDialog()` - file picker
  - [ ] `ShowDownloadDialog()` - folder picker
  - [ ] `ShowNewFolderDialog() string` - name input
  - [ ] `ShowDeleteConfirmDialog(items []*FileItem) bool`
  - [ ] `ShowRenameDialog(item *FileItem) string`
  - [ ] `ShowPropertiesDialog(item *FileItem)`

- [ ] 🔒 **Security requirements**:
  - [ ] Filenames decrypted in memory for display only
  - [ ] No filename logging from GUI events
  - [ ] Clear file list from memory on logout

- [ ] 🧪 **Create `internal/gui/mainview_test.go`**
  - [ ] `TestMainView_Content` - all elements present
  - [ ] `TestMainView_Navigation` - folder navigation

- [ ] 🧪 **Create `internal/gui/filelist_test.go`**
  - [ ] `TestFileList_SetFiles` - displays files
  - [ ] `TestFileList_Sort` - sorting works
  - [ ] `TestFileList_Selection` - selection works

### Acceptance Criteria
- [ ] File list displays correctly
- [ ] Sorting works on all columns
- [ ] Navigation works
- [ ] Toolbar actions work
- [ ] Context menu works
- [ ] Status bar shows correct info
- [ ] Sync status visible per file

---

## 3.4 SETTINGS PANEL

**Dependencies**: 3.1 (Framework), 1.1 (Config)  
**Output**: `internal/gui/settings.go`  
**Estimated Time**: 1 day

### Tasks

- [ ] 🏗️ **Create `internal/gui/settings.go`**
  - [ ] `SettingsView` struct:
    ```go
    type SettingsView struct {
        app *App
        
        // General
        syncDirEntry    *widget.Entry
        syncDirBrowse   *widget.Button
        
        // Performance
        profileSelect   *widget.Select
        
        // Appearance
        themeSelect     *widget.Select
        
        // Security
        clearSessionBtn *widget.Button
        clearDataBtn    *widget.Button
        
        // About
        versionLabel    *widget.Label
    }
    ```
  - [ ] `NewSettingsView(app *App) *SettingsView`
  - [ ] `Content() fyne.CanvasObject`
    - Tabs or accordion for sections:
      - General (sync directory)
      - Performance (profile selection)
      - Appearance (theme)
      - Security (clear data options)
      - About (version, licenses)
  - [ ] Sections:
    - **General**:
      - Sync directory chooser
      - Auto-start on login (checkbox)
    - **Performance**:
      - Profile: Auto, Low, Standard, High
      - Show current detection results
    - **Appearance**:
      - Theme: Dark, Light, System
      - Language (future)
    - **Sync**:
      - Conflict strategy selector
      - Selective sync (future)
      - Bandwidth limit (future)
    - **Security**:
      - "Clear Session" button
      - "Delete All Local Data" button (with confirmation)
      - Show encryption status
      - Show keyring status
    - **About**:
      - Version number
      - Build info
      - License info
      - Links (website, support)
  - [ ] `SaveSettings() error`
  - [ ] `LoadSettings()`

- [ ] 🔒 **Security options**:
  - [ ] `onClearSession()` - logout and clear session token
  - [ ] `onClearAllData()` - delete database, cache, credentials
    - Confirm dialog with strong warning
    - Require typing "DELETE" to confirm

- [ ] 🧪 **Create `internal/gui/settings_test.go`**
  - [ ] `TestSettingsView_Content` - all sections present
  - [ ] `TestSettingsView_Save` - saves changes
  - [ ] `TestSettingsView_Load` - loads current config

### Acceptance Criteria
- [ ] All settings accessible
- [ ] Changes save correctly
- [ ] Security actions work
- [ ] About shows correct info

---

## 3.5 SYSTEM TRAY

**Dependencies**: 3.1 (Framework)  
**Output**: `internal/gui/tray.go`  
**Estimated Time**: 0.5 days

### Tasks

- [ ] 🏗️ **Create `internal/gui/tray.go`**
  - [ ] `TrayIcon` struct:
    ```go
    type TrayIcon struct {
        app *App
        
        menu *fyne.Menu
        
        // Menu items to update
        statusItem    *fyne.MenuItem
        pauseItem     *fyne.MenuItem
    }
    ```
  - [ ] `NewTrayIcon(app *App) *TrayIcon`
  - [ ] `Setup() error`
    - Create system tray icon
    - Set up menu
  - [ ] Menu items:
    - Status (disabled, shows current status)
    - Separator
    - Open ProtonDrive
    - Pause/Resume Sync
    - Sync Now
    - Separator
    - Settings
    - Separator
    - Quit
  - [ ] `UpdateStatus(status SyncStatus)`
    - Change icon based on status (synced, syncing, error)
    - Update status menu item
  - [ ] `SetPaused(paused bool)`
    - Update Pause/Resume menu item text
  - [ ] Tray icon click:
    - Single click: show/hide main window
    - Right click: show menu
  - [ ] Icons:
    - Normal (synced)
    - Syncing (animated or different icon)
    - Error (warning icon)
    - Paused

- [ ] 🧪 **Create `internal/gui/tray_test.go`**
  - [ ] `TestTrayIcon_Menu` - menu items present
  - [ ] `TestTrayIcon_UpdateStatus` - status updates

### Acceptance Criteria
- [ ] Tray icon appears
- [ ] Menu works correctly
- [ ] Status icon changes
- [ ] Click behavior works

---

## 3.6 NOTIFICATIONS

**Dependencies**: 3.1 (Framework)  
**Output**: `internal/gui/notifications.go`  
**Estimated Time**: 0.5 days

### Tasks

- [ ] 🏗️ **Create `internal/gui/notifications.go`**
  - [ ] `NotificationManager` struct:
    ```go
    type NotificationManager struct {
        app     *App
        enabled bool
    }
    ```
  - [ ] `NewNotificationManager(app *App) *NotificationManager`
  - [ ] `SetEnabled(enabled bool)`
  - [ ] Notification types:
    - `NotifySyncComplete()`
      - Title: "Sync Complete"
      - Body: "All files are up to date"
    - `NotifyConflict(count int)`
      - Title: "Sync Conflict"
      - Body: "X files need attention"
      - **No filenames in notification**
    - `NotifyError(errCode string)`
      - Title: "Sync Error"
      - Body: user-friendly error message
      - **No sensitive data**
    - `NotifyDownloadComplete(count int)`
      - Title: "Download Complete"
      - Body: "X files downloaded"
  - [ ] Use Fyne's notification system
  - [ ] Respect system notification settings
  - [ ] Rate limit notifications (don't spam)

- [ ] 🔒 **Security requirements**:
  - [ ] NEVER include filenames in notifications
  - [ ] Only use counts and generic messages
  - [ ] No sensitive data in any notification

- [ ] 🧪 **Create `internal/gui/notifications_test.go`**
  - [ ] `TestNotificationContent_NoFilenames`
    - Create notification for file
    - Assert no filename in title or body

### Acceptance Criteria
- [ ] Notifications appear
- [ ] Different types work
- [ ] Can be disabled
- [ ] No filenames in any notification
- [ ] Rate limiting works

---

## PHASE 3 EXIT CHECKLIST

Before moving to Phase 4, verify:

- [ ] **All screens implemented**
  - [ ] Login screen
  - [ ] Main file browser
  - [ ] Settings panel
  - [ ] All dialogs

- [ ] **System integration**
  - [ ] System tray works
  - [ ] Notifications work

- [ ] **Security verified**
  - [ ] No plaintext filenames in GUI logs
  - [ ] No filenames in notifications
  - [ ] Password handling secure

- [ ] **Usability**
  - [ ] Navigation intuitive
  - [ ] Errors displayed clearly
  - [ ] Loading states visible

- [ ] **All tests passing**
  - [ ] GUI tests pass
  - [ ] Security tests pass
  - [ ] CI/CD green

- [ ] **Documentation updated**
  - [ ] CHANGELOG.md updated
  - [ ] This file updated with completion status

---

**Phase 3 Estimated Completion**: 5-7 days  
**Next Phase**: [PHASE_4.md](./PHASE_4.md) - Testing & Hardening