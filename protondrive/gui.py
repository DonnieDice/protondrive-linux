#!/usr/bin/env python3

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, simpledialog
import subprocess
import threading
import os
import sys
from pathlib import Path

class ProtonDriveGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("ProtonDrive")
        self.root.geometry("900x700")
        self.root.minsize(800, 600)
        
        # Set window icon if available
        icon_path = Path(__file__).parent.parent / "icons" / "protondrive.png"
        if icon_path.exists():
            self.root.iconphoto(True, tk.PhotoImage(file=str(icon_path)))
        
        # Proton color scheme
        self.colors = {
            'primary': '#6D4AFF',
            'primary_dark': '#5940CC',
            'primary_light': '#8A6FFF',
            'secondary': '#1C1340',
            'background': '#1C1340',
            'surface': '#292352',
            'surface_light': '#3D3572',
            'text': '#FFFFFF',
            'text_secondary': '#B8B1D4',
            'success': '#1EA885',
            'error': '#DC3545',
            'warning': '#F59E0B',
            'border': '#453D72'
        }
        
        # Configure root window
        self.root.configure(bg=self.colors['background'])
        
        # Style configuration
        self.setup_styles()
        
        # Create UI
        self.setup_ui()
        
        # Configure rclone path
        self.setup_rclone()
        
        # Load existing config
        self.load_config()
        
        # Start status checker
        self.check_connection_status()
    
    def setup_styles(self):
        style = ttk.Style()
        
        # Configure theme
        style.theme_use('clam')
        
        # Frame styles
        style.configure(
            'Proton.TFrame',
            background=self.colors['background'],
            borderwidth=0
        )
        
        style.configure(
            'Surface.TFrame',
            background=self.colors['surface'],
            relief='flat',
            borderwidth=1
        )
        
        # Label styles
        style.configure(
            'Proton.TLabel',
            background=self.colors['surface'],
            foreground=self.colors['text'],
            font=('Segoe UI', 10)
        )
        
        style.configure(
            'Title.TLabel',
            background=self.colors['background'],
            foreground=self.colors['text'],
            font=('Segoe UI', 24, 'bold')
        )
        
        style.configure(
            'Subtitle.TLabel',
            background=self.colors['background'],
            foreground=self.colors['text_secondary'],
            font=('Segoe UI', 11)
        )
        
        style.configure(
            'Status.TLabel',
            background=self.colors['surface'],
            foreground=self.colors['text_secondary'],
            font=('Segoe UI', 9)
        )
        
        # Entry styles
        style.configure(
            'Proton.TEntry',
            fieldbackground=self.colors['surface_light'],
            background=self.colors['surface_light'],
            foreground=self.colors['text'],
            bordercolor=self.colors['border'],
            insertcolor=self.colors['text'],
            font=('Segoe UI', 11)
        )
        
        style.map('Proton.TEntry',
            fieldbackground=[('focus', self.colors['surface_light'])],
            bordercolor=[('focus', self.colors['primary'])]
        )
        
        # Button styles
        style.configure(
            'Primary.TButton',
            background=self.colors['primary'],
            foreground=self.colors['text'],
            borderwidth=0,
            focuscolor='none',
            font=('Segoe UI', 11, 'bold')
        )
        
        style.map('Primary.TButton',
            background=[('active', self.colors['primary_dark'])],
            foreground=[('active', self.colors['text'])]
        )
        
        style.configure(
            'Secondary.TButton',
            background=self.colors['surface_light'],
            foreground=self.colors['text'],
            borderwidth=1,
            bordercolor=self.colors['border'],
            focuscolor='none',
            font=('Segoe UI', 11)
        )
        
        style.map('Secondary.TButton',
            background=[('active', self.colors['surface'])],
            bordercolor=[('active', self.colors['primary'])]
        )
        
        # Progressbar style
        style.configure(
            'Proton.Horizontal.TProgressbar',
            background=self.colors['primary'],
            troughcolor=self.colors['surface_light'],
            borderwidth=0,
            lightcolor=self.colors['primary_light'],
            darkcolor=self.colors['primary']
        )
    
    def create_gradient_header(self, parent):
        """Create a gradient header like Proton's design"""
        header_frame = tk.Frame(parent, height=120, bg=self.colors['background'])
        header_frame.grid(row=0, column=0, sticky="ew", padx=0, pady=0)
        header_frame.grid_columnconfigure(0, weight=1)
        
        # Create gradient effect with overlapping frames
        gradient_frame = tk.Frame(header_frame, bg=self.colors['primary'], height=120)
        gradient_frame.place(x=0, y=0, relwidth=1, relheight=1)
        
        # Logo and title
        title_frame = tk.Frame(gradient_frame, bg=self.colors['primary'])
        title_frame.place(relx=0.5, rely=0.5, anchor="center")
        
        # ProtonDrive title
        title_label = tk.Label(
            title_frame,
            text="ProtonDrive",
            font=('Segoe UI', 32, 'bold'),
            fg=self.colors['text'],
            bg=self.colors['primary']
        )
        title_label.pack()
        
        subtitle_label = tk.Label(
            title_frame,
            text="Secure cloud storage",
            font=('Segoe UI', 12),
            fg=self.colors['text'],
            bg=self.colors['primary']
        )
        subtitle_label.pack()
        
        return header_frame
    
    def setup_ui(self):
        # Main container
        main_container = ttk.Frame(self.root, style='Proton.TFrame')
        main_container.grid(row=0, column=0, sticky="nsew")
        self.root.grid_rowconfigure(0, weight=1)
        self.root.grid_columnconfigure(0, weight=1)
        
        # Header with gradient
        self.create_gradient_header(main_container)
        
        # Content frame
        content_frame = ttk.Frame(main_container, style='Proton.TFrame')
        content_frame.grid(row=1, column=0, sticky="nsew", padx=40, pady=20)
        main_container.grid_rowconfigure(1, weight=1)
        main_container.grid_columnconfigure(0, weight=1)
        
        # Status bar
        self.status_frame = tk.Frame(content_frame, bg=self.colors['surface'], height=40)
        self.status_frame.grid(row=0, column=0, sticky="ew", pady=(0, 20))
        self.status_frame.grid_columnconfigure(1, weight=1)
        
        # Status indicator
        self.status_indicator = tk.Canvas(self.status_frame, width=12, height=12, 
                                        bg=self.colors['surface'], highlightthickness=0)
        self.status_indicator.grid(row=0, column=0, padx=(15, 5), pady=14)
        self.status_dot = self.status_indicator.create_oval(2, 2, 10, 10, 
                                                           fill=self.colors['error'], 
                                                           outline="")
        
        self.status_label = ttk.Label(self.status_frame, text="Not connected", 
                                    style='Status.TLabel')
        self.status_label.grid(row=0, column=1, sticky="w", pady=14)
        
        # Login card
        login_card = tk.Frame(content_frame, bg=self.colors['surface'])
        login_card.grid(row=1, column=0, sticky="ew", pady=(0, 20))
        
        login_inner = tk.Frame(login_card, bg=self.colors['surface'])
        login_inner.pack(padx=30, pady=30)
        
        # Login title
        login_title = tk.Label(login_inner, text="Sign in to ProtonDrive",
                             font=('Segoe UI', 16, 'bold'),
                             fg=self.colors['text'],
                             bg=self.colors['surface'])
        login_title.grid(row=0, column=0, columnspan=2, pady=(0, 25))
        
        # Email field
        email_label = tk.Label(login_inner, text="Email address",
                             font=('Segoe UI', 10),
                             fg=self.colors['text_secondary'],
                             bg=self.colors['surface'])
        email_label.grid(row=1, column=0, sticky="w", pady=(0, 5))
        
        self.email_var = tk.StringVar()
        self.email_entry = ttk.Entry(login_inner, textvariable=self.email_var,
                                   style='Proton.TEntry', width=35)
        self.email_entry.grid(row=2, column=0, columnspan=2, pady=(0, 15), ipady=8)
        
        # Password field
        password_label = tk.Label(login_inner, text="Password",
                                font=('Segoe UI', 10),
                                fg=self.colors['text_secondary'],
                                bg=self.colors['surface'])
        password_label.grid(row=3, column=0, sticky="w", pady=(0, 5))
        
        self.password_var = tk.StringVar()
        self.password_entry = ttk.Entry(login_inner, textvariable=self.password_var,
                                      show="•", style='Proton.TEntry', width=35)
        self.password_entry.grid(row=4, column=0, columnspan=2, pady=(0, 15), ipady=8)
        
        # 2FA field
        twofa_label = tk.Label(login_inner, text="Two-factor code (if enabled)",
                             font=('Segoe UI', 10),
                             fg=self.colors['text_secondary'],
                             bg=self.colors['surface'])
        twofa_label.grid(row=5, column=0, sticky="w", pady=(0, 5))
        
        self.twofa_var = tk.StringVar()
        self.twofa_entry = ttk.Entry(login_inner, textvariable=self.twofa_var,
                                   style='Proton.TEntry', width=35)
        self.twofa_entry.grid(row=6, column=0, columnspan=2, pady=(0, 25), ipady=8)
        
        # Sign in button
        self.signin_btn = ttk.Button(login_inner, text="Sign in",
                                   command=self.configure_remote,
                                   style='Primary.TButton', width=30)
        self.signin_btn.grid(row=7, column=0, columnspan=2, ipady=10)
        
        # Actions card
        self.actions_card = tk.Frame(content_frame, bg=self.colors['surface'])
        self.actions_card.grid(row=2, column=0, sticky="ew", pady=(0, 20))
        self.actions_card.grid_remove()  # Hide initially
        
        actions_inner = tk.Frame(self.actions_card, bg=self.colors['surface'])
        actions_inner.pack(padx=30, pady=20)
        
        # Action buttons with icons
        button_frame = tk.Frame(actions_inner, bg=self.colors['surface'])
        button_frame.pack()
        
        self.sync_btn = ttk.Button(button_frame, text="📁 Sync Folder",
                                 command=self.sync_folder,
                                 style='Secondary.TButton', width=20)
        self.sync_btn.grid(row=0, column=0, padx=10, pady=10, ipady=15)
        
        self.browse_btn = ttk.Button(button_frame, text="🔍 Browse Files",
                                   command=self.browse_remote,
                                   style='Secondary.TButton', width=20)
        self.browse_btn.grid(row=0, column=1, padx=10, pady=10, ipady=15)
        
        self.mount_btn = ttk.Button(button_frame, text="💾 Mount Drive",
                                  command=self.mount_drive,
                                  style='Secondary.TButton', width=20)
        self.mount_btn.grid(row=0, column=2, padx=10, pady=10, ipady=15)
        
        # Output console
        console_frame = tk.Frame(content_frame, bg=self.colors['surface'])
        console_frame.grid(row=3, column=0, sticky="nsew")
        content_frame.grid_rowconfigure(3, weight=1)
        
        console_header = tk.Frame(console_frame, bg=self.colors['surface_light'], height=40)
        console_header.pack(fill="x")
        
        console_title = tk.Label(console_header, text="Activity Log",
                               font=('Segoe UI', 11, 'bold'),
                               fg=self.colors['text'],
                               bg=self.colors['surface_light'])
        console_title.pack(side="left", padx=15, pady=10)
        
        # Clear button
        clear_btn = tk.Button(console_header, text="Clear",
                            font=('Segoe UI', 9),
                            fg=self.colors['text_secondary'],
                            bg=self.colors['surface_light'],
                            bd=0, highlightthickness=0,
                            command=self.clear_output)
        clear_btn.pack(side="right", padx=15, pady=10)
        
        # Output text with dark theme
        output_container = tk.Frame(console_frame, bg=self.colors['secondary'])
        output_container.pack(fill="both", expand=True, padx=1, pady=1)
        
        self.output_text = tk.Text(output_container, 
                                 bg=self.colors['secondary'],
                                 fg=self.colors['text'],
                                 font=('Consolas', 10),
                                 wrap="word",
                                 bd=0,
                                 highlightthickness=0,
                                 insertbackground=self.colors['text'])
        self.output_text.pack(side="left", fill="both", expand=True, padx=10, pady=10)
        
        # Scrollbar
        scrollbar = ttk.Scrollbar(output_container, orient="vertical", 
                                command=self.output_text.yview)
        scrollbar.pack(side="right", fill="y")
        self.output_text.configure(yscrollcommand=scrollbar.set)
        
        # Configure text tags for colored output
        self.output_text.tag_configure("success", foreground=self.colors['success'])
        self.output_text.tag_configure("error", foreground=self.colors['error'])
        self.output_text.tag_configure("warning", foreground=self.colors['warning'])
        self.output_text.tag_configure("info", foreground=self.colors['primary_light'])
    
    def check_connection_status(self):
        """Check if ProtonDrive is configured and update status"""
        def check():
            try:
                result = subprocess.run(["rclone", "listremotes"], 
                                      capture_output=True, text=True)
                if "protondrive:" in result.stdout:
                    self.update_status("Connected", self.colors['success'])
                    self.root.after(0, self.show_actions)
                else:
                    self.update_status("Not connected", self.colors['error'])
            except:
                self.update_status("Not connected", self.colors['error'])
        
        threading.Thread(target=check, daemon=True).start()
        # Check again in 30 seconds
        self.root.after(30000, self.check_connection_status)
    
    def update_status(self, text, color):
        """Update status indicator and label"""
        self.status_label.config(text=text)
        self.status_indicator.itemconfig(self.status_dot, fill=color)
    
    def show_actions(self):
        """Show action buttons after successful login"""
        self.actions_card.grid()
    
    def hide_actions(self):
        """Hide action buttons"""
        self.actions_card.grid_remove()
    
    def clear_output(self):
        """Clear the output console"""
        self.output_text.delete(1.0, tk.END)
    
    def log(self, message, tag=None):
        """Add message to output with optional formatting"""
        self.output_text.insert(tk.END, f"{message}\n", tag)
        self.output_text.see(tk.END)
    
    def setup_rclone(self):
        # Check if rclone is installed
        try:
            subprocess.run(["rclone", "version"], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.log("Installing rclone...", "warning")
            try:
                subprocess.run(["curl", "https://rclone.org/install.sh", "|", "sudo", "bash"], 
                             shell=True, check=True)
                self.log("✓ rclone installed successfully", "success")
            except subprocess.CalledProcessError:
                self.log("Failed to install rclone. Please install manually.", "error")
    
    def load_config(self):
        try:
            result = subprocess.run(["rclone", "config", "show", "protondrive"], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if line.startswith('user ='):
                        self.email_var.set(line.split('=')[1].strip())
                        break
        except Exception as e:
            self.log(f"Could not load existing config: {e}", "error")
    
    def configure_remote(self):
        email = self.email_var.get().strip()
        password = self.password_var.get().strip()
        twofa = self.twofa_var.get().strip()
        
        if not email or not password:
            messagebox.showerror("Error", "Please enter both email and password")
            return
        
        # Disable sign in button
        self.signin_btn.config(state="disabled", text="Signing in...")
        
        def config_thread():
            try:
                self.log("Configuring ProtonDrive...", "info")
                
                # First, obscure the password
                obscure_result = subprocess.run(
                    ["rclone", "obscure", password],
                    capture_output=True, text=True
                )
                
                if obscure_result.returncode != 0:
                    self.log(f"Failed to process password: {obscure_result.stderr}", "error")
                    return
                    
                obscured_pass = obscure_result.stdout.strip()
                
                # Delete existing config if it exists
                subprocess.run(["rclone", "config", "delete", "protondrive"], 
                             capture_output=True, text=True)
                
                # Create rclone config with obscured password
                config_cmd = [
                    "rclone", "config", "create", "protondrive", "protondrive",
                    f"user={email}", f"pass={obscured_pass}"
                ]
                
                # Add 2FA if provided
                if twofa:
                    config_cmd.append(f"2fa={twofa}")
                
                # Log the command for debugging, with sensitive info redacted
                log_cmd = list(config_cmd)
                for i, item in enumerate(log_cmd):
                    if "pass=" in item:
                        log_cmd[i] = "pass=********"
                    if "2fa=" in item:
                        log_cmd[i] = "2fa=******"
                self.log(f"Executing: {' '.join(log_cmd)}", "info")
                
                result = subprocess.run(config_cmd, capture_output=True, text=True)
                
                if result.returncode == 0:
                    self.log("✓ ProtonDrive configured successfully!", "success")
                    
                    # Test the connection
                    self.log("Testing connection...", "info")
                    test_result = subprocess.run(
                        ["rclone", "lsd", "protondrive:"],
                        capture_output=True, text=True
                    )
                    if test_result.returncode == 0:
                        self.log("✓ Connection successful!", "success")
                        self.update_status("Connected", self.colors['success'])
                        self.show_actions()
                        # Clear password fields for security
                        self.password_var.set("")
                        self.twofa_var.set("")
                    else:
                        self.log(f"Connection failed: {test_result.stderr}", "error")
                        if "2FA" in test_result.stderr or "two-factor" in test_result.stderr:
                            self.log("Please ensure your 2FA code is current and try again.", "warning")
                else:
                    self.log(f"Configuration failed: {result.stderr}", "error")
                    
            except Exception as e:
                self.log(f"Error: {e}", "error")
            finally:
                # Re-enable sign in button
                self.root.after(0, lambda: self.signin_btn.config(state="normal", text="Sign in"))
        
        threading.Thread(target=config_thread, daemon=True).start()
    
    def sync_folder(self):
        local_folder = filedialog.askdirectory(title="Select folder to sync")
        if not local_folder:
            return
        
        remote_folder = simpledialog.askstring("Remote Folder", 
                                             "Enter ProtonDrive folder name (leave empty for root):")
        if remote_folder is None:
            return
        
        def sync_thread():
            try:
                remote_path = f"protondrive:{remote_folder}" if remote_folder else "protondrive:"
                cmd = ["rclone", "sync", local_folder, remote_path, "-v", "--progress"]
                self.log(f"Syncing {local_folder} to {remote_path}", "info")
                
                process = subprocess.Popen(cmd, stdout=subprocess.PIPE, 
                                         stderr=subprocess.STDOUT, text=True)
                
                for line in process.stdout:
                    line = line.strip()
                    if "ERROR" in line:
                        self.log(line, "error")
                    elif "Transferred:" in line:
                        self.log(line, "success")
                    else:
                        self.log(line)
                
                process.wait()
                
                if process.returncode == 0:
                    self.log("✓ Sync completed successfully!", "success")
                else:
                    self.log("✗ Sync failed", "error")
                    
            except Exception as e:
                self.log(f"Sync error: {e}", "error")
        
        threading.Thread(target=sync_thread, daemon=True).start()
    
    def browse_remote(self):
        def browse_thread():
            try:
                self.log("Browsing ProtonDrive...", "info")
                result = subprocess.run(["rclone", "lsd", "protondrive:"], 
                                      capture_output=True, text=True)
                
                if result.returncode == 0:
                    self.log("ProtonDrive contents:", "info")
                    for line in result.stdout.strip().split('\n'):
                        if line:
                            self.log(f"  📁 {line}")
                else:
                    self.log(f"Browse failed: {result.stderr}", "error")
                    
            except Exception as e:
                self.log(f"Browse error: {e}", "error")
        
        threading.Thread(target=browse_thread, daemon=True).start()
    
    def mount_drive(self):
        mount_point = filedialog.askdirectory(title="Select mount point")
        if not mount_point:
            return
        
        def mount_thread():
            try:
                cmd = ["rclone", "mount", "protondrive:", mount_point, "--vfs-cache-mode", "full"]
                self.log(f"Mounting ProtonDrive to {mount_point}", "info")
                self.log("Press Ctrl+C in terminal to unmount", "warning")
                
                process = subprocess.Popen(cmd, stdout=subprocess.PIPE, 
                                         stderr=subprocess.STDOUT, text=True)
                
                self.log("✓ ProtonDrive mounted successfully!", "success")
                self.log(f"Access your files at: {mount_point}", "info")
                
                for line in process.stdout:
                    if line.strip():
                        self.log(line.strip())
                        
            except Exception as e:
                self.log(f"Mount error: {e}", "error")
        
        threading.Thread(target=mount_thread, daemon=True).start()

def main():
    root = tk.Tk()
    app = ProtonDriveGUI(root)
    root.mainloop()

if __name__ == "__main__":
    main()