#!/usr/bin/env python3
"""Manual configuration helper for ProtonDrive with 2FA"""

import subprocess
import getpass
import sys

def configure_protondrive():
    print("ProtonDrive Manual Configuration Helper")
    print("=" * 40)
    
    # Get credentials
    email = input("Enter your ProtonMail email: ").strip()
    password = getpass.getpass("Enter your password: ").strip()
    
    # Check if 2FA is needed
    has_2fa = input("Do you have 2FA enabled? (y/n): ").strip().lower() == 'y'
    twofa_code = ""
    if has_2fa:
        twofa_code = input("Enter your 2FA code: ").strip()
    
    print("\nConfiguring ProtonDrive...")
    
    try:
        # Delete existing config
        subprocess.run(["rclone", "config", "delete", "protondrive"], 
                      capture_output=True, text=True)
        
        # Obscure password
        obscure_result = subprocess.run(
            ["rclone", "obscure", password],
            capture_output=True, text=True
        )
        
        if obscure_result.returncode != 0:
            print(f"Error obscuring password: {obscure_result.stderr}")
            return False
            
        obscured_pass = obscure_result.stdout.strip()
        
        # Create config with interactive mode to handle 2FA properly
        config_cmd = [
            "rclone", "config", "create", "protondrive", "protondrive",
            f"username={email}",
            f"password={obscured_pass}"
        ]
        
        if twofa_code:
            config_cmd.append(f"2fa={twofa_code}")
        
        result = subprocess.run(config_cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print("✓ Configuration created successfully!")
            
            # Test connection
            print("\nTesting connection...")
            test_result = subprocess.run(
                ["rclone", "lsd", "protondrive:"],
                capture_output=True, text=True
            )
            
            if test_result.returncode == 0:
                print("✓ Connection successful!")
                print("\nYour ProtonDrive folders:")
                print(test_result.stdout)
                return True
            else:
                print("✗ Connection failed:")
                print(test_result.stderr)
                
                if "2FA" in test_result.stderr or "two-factor" in test_result.stderr:
                    print("\nPlease run this script again with a fresh 2FA code.")
                
                return False
        else:
            print(f"Configuration failed: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    if configure_protondrive():
        print("\nProtonDrive is now configured! You can use the GUI application.")
    else:
        print("\nConfiguration failed. Please check your credentials and try again.")
        sys.exit(1)
