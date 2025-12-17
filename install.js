#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const https = require("https");
const os = require("os");
const { execSync } = require("child_process");

const REPO = "donniedice/protondrive-tauri";
const API_URL = `https://api.github.com/repos/${REPO}/releases/latest`;

const platform = os.platform();
const arch = os.arch();

const extensionMap = {
  linux: { x64: ".AppImage", arm64: ".AppImage" },
  darwin: { x64: ".dmg", arm64: ".dmg" },
  win32: { x64: ".exe", arm64: ".msi" },
};

const spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

function getDownloadUrl() {
  return new Promise((resolve, reject) => {
    https.get(API_URL, {
      headers: { "User-Agent": "protondrive-tauri-installer" },
    }, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        try {
          const release = JSON.parse(data);

          if (release.message === "Not Found") {
            reject(new Error("No releases found"));
            return;
          }

          if (!release.assets || release.assets.length === 0) {
            reject(new Error("No binaries available yet"));
            return;
          }

          const ext = extensionMap[platform]?.[arch] || ".AppImage";
          const asset = release.assets.find((a) => a.name.includes(ext));

          if (!asset) {
            const available = release.assets.map(a => a.name).join(", ");
            reject(new Error(`No ${ext} found. Available: ${available}`));
            return;
          }

          resolve(asset.browser_download_url);
        } catch (e) {
          reject(e);
        }
      });
    }).on("error", reject);
  });
}

function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, (res) => {
      if (res.statusCode !== 200) {
        reject(new Error(`Download failed: ${res.statusCode}`));
        return;
      }
      res.pipe(file);
      file.on("finish", () => {
        file.close();
        resolve();
      });
    }).on("error", (err) => {
      fs.unlink(dest, () => {});
      reject(err);
    });
  });
}

async function animateSpinner(promise, message) {
  let frame = 0;
  const interval = setInterval(() => {
    process.stdout.write(`\r${spinnerFrames[frame % spinnerFrames.length]} ${message}`);
    frame++;
  }, 80);

  try {
    const result = await promise;
    clearInterval(interval);
    process.stdout.write("\r\x1B[K");
    return result;
  } catch (e) {
    clearInterval(interval);
    process.stdout.write("\r\x1B[K");
    throw e;
  }
}

async function installLinux(downloadUrl, filename) {
  const tempFile = path.join("/tmp", filename);
  await animateSpinner(
    downloadFile(downloadUrl, tempFile),
    "Downloading binary..."
  );

  const installDir = path.join(process.env.HOME, ".local/bin");
  const installPath = path.join(installDir, "proton-drive");

  if (!fs.existsSync(installDir)) {
    fs.mkdirSync(installDir, { recursive: true });
  }

  fs.copyFileSync(tempFile, installPath);
  fs.chmodSync(installPath, 0o755);
  fs.unlinkSync(tempFile);

  const desktopFile = path.join(process.env.HOME, ".local/share/applications/protondrive.desktop");
  const desktopDir = path.dirname(desktopFile);
  if (!fs.existsSync(desktopDir)) {
    fs.mkdirSync(desktopDir, { recursive: true });
  }

  const desktopContent = `[Desktop Entry]
Version=1.0
Type=Application
Name=Proton Drive
Comment=Encrypted cloud storage
Exec=${installPath}
Icon=folder
Categories=Utility;
Terminal=false`;

  fs.writeFileSync(desktopFile, desktopContent);

  try {
    execSync("update-desktop-database ~/.local/share/applications 2>/dev/null", { stdio: "ignore" });
  } catch {}

  console.log(`✅ Installed to ~/.local/bin/proton-drive`);
  console.log(`   Launch: proton-drive`);
  console.log(`   Or find in Applications menu`);
}

async function installMacOS(downloadUrl, filename) {
  const tempFile = path.join("/tmp", filename);
  await animateSpinner(
    downloadFile(downloadUrl, tempFile),
    "Downloading binary..."
  );

  const appsDir = path.join(process.env.HOME, "Applications");
  if (!fs.existsSync(appsDir)) {
    fs.mkdirSync(appsDir, { recursive: true });
  }

  try {
    execSync(`hdiutil attach "${tempFile}" -quiet`, { stdio: "pipe" });
    const volumes = fs.readdirSync("/Volumes");
    const volume = volumes.find((v) => v.includes("Proton") || v.includes("Drive"));

    if (volume) {
      const srcApp = path.join(`/Volumes/${volume}`, "Proton Drive.app");
      const dstApp = path.join(appsDir, "Proton Drive.app");

      if (fs.existsSync(dstApp)) {
        execSync(`rm -rf "${dstApp}"`);
      }

      execSync(`cp -r "${srcApp}" "${dstApp}"`);
      execSync(`hdiutil detach "/Volumes/${volume}" -quiet`);

      console.log(`✅ Installed to ~/Applications/Proton Drive.app`);
      console.log(`   Available in Launchpad`);
    }
  } catch (e) {
    throw new Error("Failed to install DMG. Try manual install: open /tmp/" + filename);
  }

  fs.unlinkSync(tempFile);
}

async function installWindows(downloadUrl, filename) {
  const tempFile = path.join(process.env.TEMP, filename);
  await animateSpinner(
    downloadFile(downloadUrl, tempFile),
    "Downloading installer..."
  );

  console.log(`✅ Downloaded installer`);
  console.log(`   Running setup...`);

  try {
    execSync(`"${tempFile}"`, { stdio: "inherit" });
  } catch {
    console.log(`   If installer didn't start, run: "${tempFile}"`);
  }
}

async function buildLocally() {
  console.log("📦 No releases found. Building locally...");
  console.log("");

  try {
    // Clone the repository to a temp directory
    const tempDir = path.join(os.tmpdir(), `protondrive-tauri-${Date.now()}`);
    console.log("📥 Cloning repository...");
    execSync(`git clone --depth=1 https://github.com/${REPO}.git "${tempDir}"`, { stdio: "pipe" });

    // Clone WebClients submodule
    console.log("📥 Fetching WebClients...");
    execSync(`cd "${tempDir}" && git clone --depth=1 https://github.com/ProtonMail/WebClients.git WebClients`, { stdio: "pipe" });

    // Install dependencies
    console.log("📦 Installing dependencies...");
    execSync(`cd "${tempDir}" && npm install`, { stdio: "pipe" });

    // Build WebClients
    console.log("🔨 Building web app...");
    execSync(`cd "${tempDir}/WebClients" && npm install --legacy-peer-deps`, { stdio: "pipe" });
    execSync(`cd "${tempDir}/WebClients" && npm run build --workspace proton-drive`, { stdio: "pipe" });

    // Build Tauri app
    console.log("🔨 Building desktop app...");
    execSync(`cd "${tempDir}" && npm run tauri build`, { stdio: "pipe" });

    // Find the built binary
    const bundleDir = path.join(tempDir, "src-tauri/target/release/bundle");
    let binaryPath = "";
    
    if (platform === "linux") {
      const appImagePath = fs.readdirSync(bundleDir).find(f => f.endsWith(".AppImage"));
      if (appImagePath) {
        binaryPath = path.join(bundleDir, appImagePath);
        const installDir = path.join(process.env.HOME, ".local/bin");
        const installPath = path.join(installDir, "proton-drive");
        
        if (!fs.existsSync(installDir)) {
          fs.mkdirSync(installDir, { recursive: true });
        }
        
        fs.copyFileSync(binaryPath, installPath);
        fs.chmodSync(installPath, 0o755);
        
        // Create desktop entry
        const desktopFile = path.join(process.env.HOME, ".local/share/applications/protondrive.desktop");
        const desktopDir = path.dirname(desktopFile);
        if (!fs.existsSync(desktopDir)) {
          fs.mkdirSync(desktopDir, { recursive: true });
        }
        
        const desktopContent = `[Desktop Entry]
Version=1.0
Type=Application
Name=Proton Drive
Comment=Encrypted cloud storage
Exec=${installPath}
Icon=folder
Categories=Utility;
Terminal=false`;
        
        fs.writeFileSync(desktopFile, desktopContent);
        
        try {
          execSync("update-desktop-database ~/.local/share/applications 2>/dev/null", { stdio: "ignore" });
        } catch {}
        
        console.log("");
        console.log(`✅ Successfully built and installed!`);
        console.log(`   Launch: proton-drive`);
        console.log(`   Or find in Applications menu`);
      }
    } else if (platform === "darwin") {
      const dmgPath = fs.readdirSync(bundleDir).find(f => f.endsWith(".dmg"));
      if (dmgPath) {
        binaryPath = path.join(bundleDir, dmgPath);
        await installMacOS(`file://${binaryPath}`, dmgPath);
      }
    } else if (platform === "win32") {
      const exePath = fs.readdirSync(bundleDir).find(f => f.endsWith(".exe") || f.endsWith(".msi"));
      if (exePath) {
        binaryPath = path.join(bundleDir, exePath);
        await installWindows(`file://${binaryPath}`, exePath);
      }
    }

    // Clean up temp directory
    try {
      execSync(`rm -rf "${tempDir}"`, { stdio: "ignore" });
    } catch {}

  } catch (error) {
    console.log("");
    console.log(`❌ Build failed: ${error.message}`);
    console.log("");
    console.log("📋 Please ensure you have:");
    console.log("   • Git installed");
    console.log("   • Node.js 18+ installed");
    console.log("   • Rust toolchain installed");
    console.log("   • Tauri dependencies for your platform");
    console.log("");
    console.log("🔗 See: https://tauri.app/v1/guides/getting-started/prerequisites");
    process.exit(1);
  }
}

async function install() {
  try {
    const downloadUrl = await animateSpinner(
      getDownloadUrl(),
      "Fetching latest release..."
    );

    const filename = downloadUrl.split("/").pop();

    if (platform === "linux") {
      await installLinux(downloadUrl, filename);
    } else if (platform === "darwin") {
      await installMacOS(downloadUrl, filename);
    } else if (platform === "win32") {
      await installWindows(downloadUrl, filename);
    } else {
      throw new Error(`Unsupported platform: ${platform}`);
    }

  } catch (error) {
    if (error.message.includes("No releases found") || error.message.includes("No binaries available")) {
      // Try building locally
      await buildLocally();
    } else {
      process.stdout.write("\r\x1B[K");
      console.log(`❌ ${error.message}`);
      console.log("");
      console.log("📋 Attempting local build...");
      await buildLocally();
    }
  }
}

install();
