#!/usr/bin/env python3
"""
ProtonDrive Linux GUI Client - Fixed with Verbose Debug Logging
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox, simpledialog
import subprocess
import threading
import os
import sys
from pathlib import Path
import time
import datetime

class ProtonDriveGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("ProtonDrive")
        self.root.geometry("900x700")
        self.root.minsize(800, 600)
        
        # Set window icon if available
        icon_path = Path(__file__).parent.parent / "icons" / "protondrive.png"
        if icon_path.exists():
            try:
                self.root.iconphoto(True, tk.PhotoImage(file=str(icon_path)))
                self.debug_log("Icon loaded successfully")
            except Exception as e:
                self.debug_log(f"Failed to load icon: {e}")
        
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
        self.debug_log("Window configured with Proton color scheme")
        
        # Style configuration
        self.setup_styles()
        self.debug_log("Styles configured")
        
        # Create UI
        self.setup_ui()
        self.debug_log("UI setup complete")
        
        # Check rclone
        self.check_rclone()
        
        # Load existing config
        self.load_config()
        
        # Start status checker
        self.check_connection_status()
        
        self.log("=== ProtonDrive GUI Started ===", "info")
        self.log(f"Timestamp: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", "info")
    
    def debug_log(self, message):
        """Internal debug logging - appears in terminal"""
        timestamp = datetime.datetime.now().strftime('%H:%M:%S')
        print(f"[DEBUG {timestamp}] {message}")
    
    def setup_styles(self):
        style = ttk.Style()
        style.theme_use('clam')
        self.debug_log("Using 'clam' theme")
        
        # Frame styles
        style.configure('Proton.TFrame', background=self.colors['background'], borderwidth=0)
        style.configure('Surface.TFrame', background=self.colors['surface'], relief='flat', borderwidth=1)
        
        # Label styles
        style.configure('Proton.TLabel', background=self.colors['surface'], 
                       foreground=self.colors['text'], font=('Segoe UI', 10))
        style.configure('Title.TLabel', background=self.colors['background'], 
                       foreground=self.colors['text'], font=('Segoe UI', 24, 'bold'))
        style.configure('Status.TLabel', background=self.colors['surface'], 
                       foreground=self.colors['text_secondary'], font=('Segoe UI', 9))
        
        # Entry styles
        style.configure('Proton.TEntry', fieldbackground=self.colors['surface_light'],
                       background=self.colors['surface_light'], foreground=self.colors['text'],
                       bordercolor=self.colors['border'], insertcolor=self.colors['text'],
                       font=('Segoe UI', 11))
        style.map('Proton.TEntry',
            fieldbackground=[('focus', self.colors['surface_light'])],
            bordercolor=[('focus', self.colors['primary'])])
        
        # Button styles
        style.configure('Primary.TButton', background=self.colors['primary'],
                       foreground=self.colors['text'], borderwidth=0, focuscolor='none',
                       font=('Segoe UI', 11, 'bold'))
        style.map('Primary.TButton',
            background=[('active', self.colors['primary_dark'])],
            foreground=[('active', self.colors['text'])])
        
        style.configure('Secondary.TButton', background=self.colors['surface_light'],
                       foreground=self.colors['text'], borderwidth=1,
                       bordercolor=self.colors['border'], focuscolor='none',
                       font=('Segoe UI', 11))
        style.map('Secondary.TButton',
            background=[('active', self.colors['surface'])],
            bordercolor=[('active', self.colors['primary'])])
    
    def create_gradient_header(self, parent):
        self.debug_log("Creating gradient header")
        header_frame = tk.Frame(parent, height=120, bg=self.colors['background'])
        header_frame.grid(row=0, column=0, sticky="ew", padx=0, pady=0)
        header_frame.grid_columnconfigure(0, weight=1)
        
        gradient_frame = tk.Frame(header_frame, bg=self.colors['primary'], height=120)
        gradient_frame.place(x=0, y=0, relwidth=1, relheight=1)
        
        title_frame = tk.Frame(gradient_frame, bg=self.colors['primary'])
        title_frame.place(relx=0.5, rely=0.5, anchor="center")
        
        title_label = tk.Label(title_frame, text="ProtonDrive",
                             font=('Segoe UI', 32, 'bold'),
                             fg=self.colors['text'], bg=self.colors['primary'])
        title_label.pack()
        
        subtitle_label = tk.Label(title_frame, text="Secure cloud storage",
                                font=('Segoe UI', 12),
                                fg=self.colors['text'], bg=self.colors['primary'])
        subtitle_label.pack()
        
        return header_frame
    
    def setup_ui(self):
        self.debug_log("Setting up UI components")
        main_container = ttk.Frame(self.root, style='Proton.TFrame')
        main_container.grid(row=0, column=0, sticky="nsew")
        self.root.grid_rowconfigure(0, weight=1)
        self.root.grid_columnconfigure(0, weight=1)
        
        self.create_gradient_header(main_container)
        
        content_frame = ttk.Frame(main_container, style='Proton.TFrame')
        content_frame.grid(row=1, column=0, sticky="nsew", padx=40, pady=20)
        main_container.grid_rowconfigure(1, weight=1)
        main_container.grid_columnconfigure(0, weight=1)
        
        # Status bar
        self.debug_log("Creating status bar")
        self.status_frame = tk.Frame(content_frame, bg=self.colors['surface'], height=40)
        self.status_frame.grid(row=0, column=0, sticky="ew", pady=(0, 20))
        self.status_frame.grid_columnconfigure(1, weight=1)
        
        self.status_indicator = tk.Canvas(self.status_frame, width=12, height=12, 
                                        bg=self.colors['surface'], highlightthickness=0)
        self.status_indicator.grid(row=0, column=0, padx=(15, 5), pady=14)
        self.status_dot = self.status_indicator.create_oval(2, 2, 10, 10, 
                                                           fill=self.colors['error'], outline="")
        
        self.status_label = ttk.Label(self.status_frame, text="Not connected", 
                                    style='Status.TLabel')
        self.status_label.grid(row=0, column=1, sticky="w", pady=14)
        
        # Login card
        self.debug_log("Creating login card")
        login_card = tk.Frame(content_frame, bg=self.colors['surface'])
        login_card.grid(row=1, column=0, sticky="ew", pady=(0, 20))
        
        login_inner = tk.Frame(login_card, bg=self.colors['surface'])
        login_inner.pack(padx=30, pady=30)
        
        login_title = tk.Label(login_inner, text="Sign in to ProtonDrive",
                             font=('Segoe UI', 16, 'bold'),
                             fg=self.colors['text'], bg=self.colors['surface'])
        login_title.grid(row=0, column=0, columnspan=2, pady=(0, 25))
        
        # Email field
        email_label = tk.Label(login_inner, text="Email address",
                             font=('Segoe UI', 10),
                             fg=self.colors['text_secondary'],
                             bg=self.colors['surface'])
        email_label.grid(row=1, column=0, sticky="w", pady=(0, 5))
        
        self.email_var = tk.StringVar()
        self.email_var.trace('w', lambda *args: self.debug_log(f"Email changed: {len(self.email_var.get())} chars"))
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
        self.password_var.trace('w', lambda *args: self.debug_log(f"Password changed: {len(self.password_var.get())} chars"))
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
        self.twofa_var.trace('w', lambda *args: self.debug_log(f"2FA changed: {len(self.twofa_var.get())} chars"))
        self.twofa_entry = ttk.Entry(login_inner, textvariable=self.twofa_var,
                                   style='Proton.TEntry', width=35)
        self.twofa_entry.grid(row=6, column=0, columnspan=2, pady=(0, 25), ipady=8)
        
        # Sign in button
        self.signin_btn = ttk.Button(login_inner, text="Sign in",
                                   command=self.configure_remote,
                                   style='Primary.TButton', width=30)
        self.signin_btn.grid(row=7, column=0, columnspan=2, ipady=10)
        
        # Actions card (hidden initially)
        self.debug_log("Creating actions card")
        self.actions_card = tk.Frame(content_frame, bg=self.colors['surface'])
        self.actions_card.grid(row=2, column=0, sticky="ew", pady=(0, 20))
        self.actions_card.grid_remove()
        
        actions_inner = tk.Frame(self.actions_card, bg=self.colors['surface'])
        actions_inner.pack(padx=30, pady=20)
        
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
        self.debug_log("Creating output console")
        console_frame = tk.Frame(content_frame, bg=self.colors['surface'])
        console_frame.grid(row=3, column=0, sticky="nsew")
        content_frame.grid_rowconfigure(3, weight=1)
        
        console_header = tk.Frame(console_frame, bg=self.colors['surface_light'], height=40)
        console_header.pack(fill="x")
        
        console_title = tk.Label(console_header, text="Activity Log (Verbose Mode)",
                               font=('Segoe UI', 11, 'bold'),
                               fg=self.colors['text'], bg=self.colors['surface_light'])
        console_title.pack(side="left", padx=15, pady=10)
        
        clear_btn = tk.Button(console_header, text="Clear",
                            font=('Segoe UI', 9), fg=self.colors['text_secondary'],
                            bg=self.colors['surface_light'], bd=0, highlightthickness=0,
                            command=self.clear_output)
        clear_btn.pack(side="right", padx=15, pady=10)
        
        output_container = tk.Frame(console_frame, bg=self.colors['secondary'])
        output_container.pack(fill="both", expand=True, padx=1, pady=1)
        
        self.output_text = tk.Text(output_container, bg=self.colors['secondary'],
                                 fg=self.colors['text'], font=('Consolas', 9),
                                 wrap="word", bd=0, highlightthickness=0,
                                 insertbackground=self.colors['text'])
        self.output_text.pack(side="left", fill="both", expand=True, padx=10, pady=10)
        
        scrollbar = ttk.Scrollbar(output_container, orient="vertical", 
                                command=self.output_text.yview)
        scrollbar.pack(side="right", fill="y")
        self.output_text.configure(yscrollcommand=scrollbar.set)
        
        # Configure text tags
        self.output_text.tag_configure("success", foreground=self.colors['success'])
        self.output_text.tag_configure("error", foreground=self.colors['error'])
        self.output_text.tag_configure("warning", foreground=self.colors['warning'])
        self.output_text.tag_configure("info", foreground=self.colors['primary_light'])
        self.output_text.tag_configure("debug", foreground=self.colors['text_secondary'])
        
        self.debug_log("UI setup complete")
    
    def check_rclone(self):
        """Check if rclone is installed"""
        self.debug_log("Checking for rclone installation")
        self.log("[CHECK] Verifying rclone installation...", "debug")
        
        try:
            result = subprocess.run(["rclone", "version"], 
                                  capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                version_line = result.stdout.split('\n')[0]
                self.log(f"✓ rclone found: {version_line}", "success")
                self.debug_log(f"rclone version: {version_line}")
                return True
            else:
                self.log(f"✗ rclone check failed with code {result.returncode}", "error")
                self.debug_log(f"rclone stderr: {result.stderr}")
                return False
        except FileNotFoundError:
            self.log("✗ rclone not found in PATH", "error")
            self.log("Install with: curl https://rclone.org/install.sh | sudo bash", "info")
            self.debug_log("FileNotFoundError: rclone binary not in PATH")
            return False
        except subprocess.TimeoutExpired:
            self.log("✗ rclone check timed out", "error")
            self.debug_log("Timeout checking rclone")
            return False
        except Exception as e:
            self.log(f"✗ Unexpected error checking rclone: {e}", "error")
            self.debug_log(f"Exception in check_rclone: {e}")
            return False
    
    def check_connection_status(self):
        """Check if ProtonDrive is configured"""
        self.debug_log("Starting connection status check")
        self.log("[CHECK] Checking ProtonDrive connection status...", "debug")
        
        def check():
            try:
                self.debug_log("Running: rclone listremotes")
                result = subprocess.run(["rclone", "listremotes"], 
                                      capture_output=True, text=True, timeout=5)
                
                if result.returncode == 0:
                    self.debug_log(f"listremotes output: {result.stdout}")
                    
                    if "protondrive:" in result.stdout:
                        self.log("[CHECK] ProtonDrive remote found, testing connection...", "debug")
                        self.debug_log("Running: rclone lsd protondrive:")
                        
                        # Verify it actually works
                        test = subprocess.run(["rclone", "lsd", "protondrive:"],
                                            capture_output=True, text=True, timeout=10)
                        
                        if test.returncode == 0:
                            self.log("✓ Connection verified successfully", "success")
                            self.debug_log("Connection test passed")
                            self.update_status("Connected", self.colors['success'])
                            self.root.after(0, self.show_actions)
                        else:
                            self.log("⚠ Configuration exists but connection failed", "warning")
                            self.log(f"[DEBUG] Error: {test.stderr[:200]}", "debug")
                            self.debug_log(f"Connection test failed: {test.stderr}")
                            self.update_status("Configuration error", self.colors['warning'])
                    else:
                        self.log("[CHECK] No ProtonDrive remote configured", "debug")
                        self.debug_log("protondrive: not found in remotes")
                        self.update_status("Not connected", self.colors['error'])
                else:
                    self.log(f"✗ listremotes failed with code {result.returncode}", "error")
                    self.debug_log(f"listremotes error: {result.stderr}")
                    self.update_status("Not connected", self.colors['error'])
                    
            except subprocess.TimeoutExpired:
                self.log("✗ Connection check timed out", "error")
                self.debug_log("Timeout in connection check")
                self.update_status("Check timeout", self.colors['error'])
            except Exception as e:
                self.log(f"✗ Connection check error: {e}", "error")
                self.debug_log(f"Exception in check_connection_status: {e}")
                self.update_status("Check error", self.colors['error'])
        
        threading.Thread(target=check, daemon=True).start()
        # Check again in 30 seconds
        self.root.after(30000, self.check_connection_status)
    
    def update_status(self, text, color):
        self.status_label.config(text=text)
        self.status_indicator.itemconfig(self.status_dot, fill=color)
        self.debug_log(f"Status updated: {text}")
    
    def show_actions(self):
        self.actions_card.grid()
        self.debug_log("Actions card shown")
    
    def hide_actions(self):
        self.actions_card.grid_remove()
        self.debug_log("Actions card hidden")
    
    def clear_output(self):
        self.output_text.delete(1.0, tk.END)
        self.debug_log("Output cleared")
        self.log("=== Log Cleared ===", "info")
    
    def log(self, message, tag=None):
        timestamp = datetime.datetime.now().strftime('%H:%M:%S')
        formatted_msg = f"[{timestamp}] {message}\n"
        self.output_text.insert(tk.END, formatted_msg, tag)
        self.output_text.see(tk.END)
        self.root.update_idletasks()
    
    def load_config(self):
        """Load existing configuration"""
        self.debug_log("Attempting to load existing config")
        self.log("[CONFIG] Loading existing configuration...", "debug")
        
        try:
            result = subprocess.run(["rclone", "config", "show", "protondrive"], 
                                  capture_output=True, text=True, timeout=5)
            
            if result.returncode == 0:
                self.debug_log(f"Config show output: {result.stdout[:200]}")
                self.log("[CONFIG] Found existing ProtonDrive configuration", "debug")
                
                for line in result.stdout.split('\n'):
                    if 'username' in line.lower() or 'user' in line.lower():
                        parts = line.split('=')
                        if len(parts) > 1:
                            email = parts[1].strip()
                            self.email_var.set(email)
                            self.log(f"✓ Loaded saved email: {email}", "success")
                            self.debug_log(f"Email loaded: {email}")
                            break
            else:
                self.log("[CONFIG] No existing configuration found", "debug")
                self.debug_log("No protondrive config exists")
                
        except subprocess.TimeoutExpired:
            self.log("⚠ Config load timed out", "warning")
            self.debug_log("Timeout loading config")
        except Exception as e:
            self.log(f"⚠ Could not load config: {e}", "warning")
            self.debug_log(f"Exception in load_config: {e}")
    
    def configure_remote(self):
        """Configure ProtonDrive with proper password handling and verbose logging"""
        email = self.email_var.get().strip()
        password = self.password_var.get().strip()
        twofa = self.twofa_var.get().strip()
        
        self.debug_log(f"Configure called - Email: {email}, Password length: {len(password)}, 2FA: {bool(twofa)}")
        self.log("=== Starting ProtonDrive Configuration ===", "info")
        self.log(f"[AUTH] Email: {email}", "debug")
        self.log(f"[AUTH] Password: {'*' * len(password)} ({len(password)} chars)", "debug")
        self.log(f"[AUTH] 2FA: {'Yes (' + str(len(twofa)) + ' digits)' if twofa else 'No'}", "debug")
        
        if not email or not password:
            self.log("✗ Email and password are required", "error")
            self.debug_log("Validation failed: missing credentials")
            messagebox.showerror("Error", "Please enter both email and password")
            return
        
        if '@' not in email:
            self.log("✗ Invalid email format", "error")
            self.debug_log("Validation failed: invalid email")
            messagebox.showerror("Error", "Please enter a valid email address")
            return
        
        self.signin_btn.config(state="disabled", text="Signing in...")
        self.debug_log("Sign in button disabled")
        
        def config_thread():
            try:
                # Step 1: Delete existing config
                self.log("[STEP 1/5] Removing old configuration...", "info")
                self.debug_log("Running: rclone config delete protondrive")
                
                delete_result = subprocess.run(
                    ["rclone", "config", "delete", "protondrive"],
                    capture_output=True, text=True, timeout=10
                )
                self.debug_log(f"Delete result: returncode={delete_result.returncode}")
                self.log("[STEP 1/5] ✓ Old config removed", "debug")
                
                # Step 2: Obscure password
                self.log("[STEP 2/5] Encrypting password securely...", "info")
                self.debug_log("Running: rclone obscure [password]")
                
                obscure_result = subprocess.run(
                    ["rclone", "obscure", password],
                    capture_output=True, text=True, timeout=10
                )
                
                if obscure_result.returncode != 0:
                    self.log(f"✗ Password encryption failed: {obscure_result.stderr}", "error")
                    self.debug_log(f"Obscure failed: {obscure_result.stderr}")
                    return
                
                obscured_pass = obscure_result.stdout.strip()
                self.log(f"[STEP 2/5] ✓ Password encrypted ({len(obscured_pass)} chars)", "debug")
                self.debug_log(f"Obscured password length: {len(obscured_pass)}")
                
                # Step 3: Build configuration command
                self.log("[STEP 3/5] Building configuration...", "info")
                config_cmd = [
                    "rclone", "config", "create", "protondrive", "protondrive",
                    f"username={email}",
                    f"password={obscured_pass}",
                    "--obscure"
                ]
                
                if twofa:
                    config_cmd.append(f"2fa={twofa}")
                    self.log("[STEP 3/5] ✓ Added 2FA code to configuration", "debug")
                    self.debug_log("2FA included in config")
                
                # Log the command (safely)
                safe_cmd = config_cmd.copy()
                for i, arg in enumerate(safe_cmd):
                    if 'password=' in arg:
                        safe_cmd[i] = 'password=***HIDDEN***'
                    if '2fa=' in arg:
                        safe_cmd[i] = '2fa=***HIDDEN***'
                
                self.log(f"[DEBUG] Command: {' '.join(safe_cmd)}", "debug")
                self.debug_log(f"Running: {' '.join(safe_cmd)}")
                
                # Step 4: Create configuration
                self.log("[STEP 4/5] Creating ProtonDrive configuration...", "info")
                result = subprocess.run(config_cmd, capture_output=True, 
                                      text=True, timeout=30)
                
                self.debug_log(f"Config create result: returncode={result.returncode}")
                self.debug_log(f"Config stdout: {result.stdout[:200]}")
                self.debug_log(f"Config stderr: {result.stderr[:200]}")
                
                if result.returncode == 0:
                    self.log("[STEP 4/5] ✓ Configuration created successfully", "success")
                    
                    # Step 5: Test connection
                    self.log("[STEP 5/5] Testing connection to ProtonDrive...", "info")
                    time.sleep(2)  # Brief pause
                    
                    self.debug_log("Running: rclone lsd protondrive:")
                    test_result = subprocess.run(
                        ["rclone", "lsd", "protondrive:"],
                        capture_output=True, text=True, timeout=30
                    )
                    
                    self.debug_log(f"Test result: returncode={test_result.returncode}")
                    self.debug_log(f"Test stdout: {test_result.stdout[:200]}")
                    self.debug_log(f"Test stderr: {test_result.stderr[:200]}")
                    
                    if test_result.returncode == 0:
                        self.log("✓ Connection test successful!", "success")
                        self.log("=== Configuration Complete ===", "success")
                        self.log("✓ ProtonDrive is ready to use!", "success")
                        
                        self.update_status("Connected", self.colors['success'])
                        self.show_actions()
                        
                        # Clear sensitive fields
                        self.password_var.set("")
                        self.twofa_var.set("")
                        self.debug_log("Credentials cleared from UI")
                        
                    else:
                        self.log("[STEP 5/5] ✗ Connection test failed", "error")
                        self.log(f"[ERROR] {test_result.stderr}", "error")
                        self.debug_log(f"Connection test failed: {test_result.stderr}")
                        
                        if "2FA" in test_result.stderr or "two-factor" in test_result.stderr.lower():
                            self.log("⚠ 2FA code may be invalid or expired", "warning")
                            self.log("Please enter a fresh 6-digit code and try again", "warning")
                        elif "username" in test_result.stderr.lower() or "password" in test_result.stderr.lower():
                            self.log("✗ Invalid credentials", "error")
                            self.log("Please check your email and password", "error")
                        elif "timeout" in test_result.stderr.lower():
                            self.log("⚠ Connection timeout - please check your internet", "warning")
                        
                else:
                    self.log(f"[STEP 4/5] ✗ Configuration failed", "error")
                    self.log(f"[ERROR] {result.stderr}", "error")
                    self.debug_log(f"Config creation failed: {result.stderr}")
                    
            except subprocess.TimeoutExpired:
                self.log("✗ Operation timed out after 30 seconds", "error")
                self.log("Please check your internet connection and try again", "error")
                self.debug_log("TimeoutExpired in configure_remote")
            except Exception as e:
                self.log(f"✗ Unexpected error: {str(e)}", "error")
                self.debug_log(f"Exception in configure_remote: {type(e).__name__}: {e}")
                import traceback
                self.debug_log(f"Traceback: {traceback.format_exc()}")
            finally:
                self.root.after(0, lambda: self.signin_btn.config(
                    state="normal", text="Sign in"))
                self.debug_log("Sign in button re-enabled")
        
        threading.Thread(target=config_thread, daemon=True, name="ConfigThread").start()
        self.debug_log("Configuration thread started")
    
    def sync_folder(self):
        self.debug_log("Sync folder button clicked")
        self.log("=== Starting Folder Sync ===", "info")
        
        local_folder = filedialog.askdirectory(title="Select folder to sync")
        if not local_folder:
            self.log("⚠ Sync cancelled - no folder selected", "warning")
            self.debug_log("User cancelled folder selection")
            return
        
        self.log(f"[SYNC] Local folder: {local_folder}", "debug")
        self.debug_log(f"Selected local folder: {local_folder}")
        
        remote_folder = simpledialog.askstring("Remote Folder", 
                                             "Enter ProtonDrive folder name (leave empty for root):")
        if remote_folder is None:
            self.log("⚠ Sync cancelled", "warning")
            self.debug_log("User cancelled remote folder input")
            return
        
        remote_path = f"protondrive:{remote_folder}" if remote_folder else "protondrive:"
        self.log(f"[SYNC] Remote path: {remote_path}", "debug")
        self.debug_log(f"Remote path: {remote_path}")
        
        def sync_thread():
            try:
                cmd = ["rclone", "sync", local_folder, remote_path, "-v", "--progress"]
                self.log(f"[SYNC] Starting: {local_folder} → {remote_path}", "info")
                self.log(f"[DEBUG] Command: {' '.join(cmd)}", "debug")
                self.debug_log(f"Running: {' '.join(cmd)}")
                
                process = subprocess.Popen(cmd, stdout=subprocess.PIPE, 
                                         stderr=subprocess.STDOUT, text=True)
                
                line_count = 0
                for line in process.stdout:
                    line = line.strip()
                    if line:
                        line_count += 1
                        if "ERROR" in line:
                            self.log(f"[ERROR] {line}", "error")
                        elif "Transferred:" in line or "Transferred:" in line:
                            self.log(f"[PROGRESS] {line}", "success")
                        elif line_count % 10 == 0:  # Log every 10th line to avoid spam
                            self.log(f"[SYNC] {line}", "debug")
                        
                        self.debug_log(f"Sync output: {line}")
                
                process.wait()
                
                self.debug_log(f"Sync completed with return code: {process.returncode}")
                
                if process.returncode == 0:
                    self.log("=== Sync Complete ===", "success")
                    self.log("✓ All files synchronized successfully!", "success")
                else:
                    self.log("=== Sync Failed ===", "error")
                    self.log(f"✗ Process exited with code {process.returncode}", "error")
                    
            except Exception as e:
                self.log(f"✗ Sync error: {str(e)}", "error")
                self.debug_log(f"Exception in sync_folder: {type(e).__name__}: {e}")
        
        threading.Thread(target=sync_thread, daemon=True, name="SyncThread").start()
        self.debug_log("Sync thread started")
    
    def browse_remote(self):
        self.debug_log("Browse files button clicked")
        self.log("=== Browsing ProtonDrive ===", "info")
        
        def browse_thread():
            try:
                self.log("[BROWSE] Fetching directory list...", "debug")
                self.debug_log("Running: rclone lsd protondrive:")
                
                result = subprocess.run(["rclone", "lsd", "protondrive:"],
                                      capture_output=True, text=True, timeout=30)
                
                self.debug_log(f"Browse result: returncode={result.returncode}")
                self.debug_log(f"Browse output length: {len(result.stdout)} chars")
                
                if result.returncode == 0:
                    self.log("✓ Directory listing retrieved", "success")
                    self.log("", None)
                    self.log("📁 ProtonDrive Contents:", "info")
                    self.log("-" * 60, "debug")
                    
                    lines = result.stdout.strip().split('\n')
                    if not lines or (len(lines) == 1 and not lines[0]):
                        self.log("  (Empty - no folders found)", "debug")
                        self.debug_log("ProtonDrive is empty")
                    else:
                        for line in lines:
                            if line:
                                self.log(f"  📁 {line}", None)
                                self.debug_log(f"Found: {line}")
                    
                    self.log("-" * 60, "debug")
                    self.log(f"Total: {len([l for l in lines if l])} folders", "info")
                else:
                    self.log(f"✗ Browse failed: {result.stderr}", "error")
                    self.debug_log(f"Browse error: {result.stderr}")
                    
            except subprocess.TimeoutExpired:
                self.log("✗ Browse timed out after 30 seconds", "error")
                self.debug_log("Browse operation timed out")
            except Exception as e:
                self.log(f"✗ Browse error: {str(e)}", "error")
                self.debug_log(f"Exception in browse_remote: {type(e).__name__}: {e}")
        
        threading.Thread(target=browse_thread, daemon=True, name="BrowseThread").start()
        self.debug_log("Browse thread started")
    
    def mount_drive(self):
        self.debug_log("Mount drive button clicked")
        self.log("=== Mounting ProtonDrive ===", "info")
        
        mount_point = filedialog.askdirectory(title="Select mount point")
        if not mount_point:
            self.log("⚠ Mount cancelled - no mount point selected", "warning")
            self.debug_log("User cancelled mount point selection")
            return
        
        self.log(f"[MOUNT] Mount point: {mount_point}", "debug")
        self.debug_log(f"Mount point: {mount_point}")
        
        # Check if mount point is empty
        if os.listdir(mount_point):
            self.log("⚠ Warning: Mount point is not empty", "warning")
            confirm = messagebox.askyesno("Mount Point Not Empty",
                                         f"The directory {mount_point} is not empty.\n\nContinue anyway?")
            if not confirm:
                self.log("⚠ Mount cancelled by user", "warning")
                return
        
        def mount_thread():
            try:
                cmd = ["rclone", "mount", "protondrive:", mount_point, 
                      "--vfs-cache-mode", "full", "--daemon"]
                
                self.log(f"[MOUNT] Mounting to {mount_point}...", "info")
                self.log(f"[DEBUG] Command: {' '.join(cmd)}", "debug")
                self.debug_log(f"Running: {' '.join(cmd)}")
                
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                
                self.debug_log(f"Mount result: returncode={result.returncode}")
                self.debug_log(f"Mount stdout: {result.stdout}")
                self.debug_log(f"Mount stderr: {result.stderr}")
                
                if result.returncode == 0:
                    self.log("=== Mount Successful ===", "success")
                    self.log(f"✓ ProtonDrive mounted at: {mount_point}", "success")
                    self.log("", None)
                    self.log("ℹ️  To unmount, run:", "info")
                    self.log(f"   fusermount -u {mount_point}", "debug")
                    self.log("   or", "debug")
                    self.log(f"   umount {mount_point}", "debug")
                else:
                    self.log("✗ Mount failed", "error")
                    self.log(f"[ERROR] {result.stderr}", "error")
                    
                    if "already mounted" in result.stderr.lower():
                        self.log("⚠ Mount point may already be in use", "warning")
                    elif "permission denied" in result.stderr.lower():
                        self.log("⚠ Permission denied - try running with sudo", "warning")
                    elif "fuse" in result.stderr.lower():
                        self.log("⚠ FUSE not available - install with:", "warning")
                        self.log("   sudo apt install fuse3  # Debian/Ubuntu", "debug")
                        self.log("   sudo pacman -S fuse3    # Arch", "debug")
                        
            except subprocess.TimeoutExpired:
                self.log("✗ Mount timed out after 30 seconds", "error")
                self.debug_log("Mount operation timed out")
            except Exception as e:
                self.log(f"✗ Mount error: {str(e)}", "error")
                self.debug_log(f"Exception in mount_drive: {type(e).__name__}: {e}")
        
        threading.Thread(target=mount_thread, daemon=True, name="MountThread").start()
        self.debug_log("Mount thread started")


def main():
    """Entry point for the application"""
    print("=" * 60)
    print("ProtonDrive Linux GUI - Starting")
    print("Debug output will appear here")
    print("=" * 60)
    
    root = tk.Tk()
    app = ProtonDriveGUI(root)
    
    try:
        root.mainloop()
    except KeyboardInterrupt:
        print("\n[DEBUG] Keyboard interrupt received")
    except Exception as e:
        print(f"[DEBUG] Fatal error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        print("[DEBUG] Application closed")


if __name__ == "__main__":
    main()