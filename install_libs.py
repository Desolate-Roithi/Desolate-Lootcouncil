import os
import shutil
import subprocess
import sys
import stat

# Configuration
LIBS_DIR = "Libs"
ACE3_URL = "https://github.com/WoWUIDev/Ace3.git"
OTHER_REPOS = {
    "LibStub": "https://github.com/lua-wow/LibStub.git",
}

def on_rm_error(func, path, exc_info):
    os.chmod(path, stat.S_IWRITE)
    func(path)

def run_command(command, cwd=None):
    try:
        subprocess.check_call(command, cwd=cwd, shell=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {command}")
        sys.exit(1)

def install_ace3():
    print("--- Installing Ace3 ---")
    ace3_dir = os.path.join(LIBS_DIR, "Ace3")
    
    # 1. Clean existing Ace3 if any
    if os.path.exists(ace3_dir):
        shutil.rmtree(ace3_dir, onerror=on_rm_error)
        
    # 2. Clone Ace3
    print(f"Cloning Ace3 from {ACE3_URL}...")
    run_command(f"git clone {ACE3_URL} {ace3_dir}")
    
    # 3. Remove .git
    git_dir = os.path.join(ace3_dir, ".git")
    if os.path.exists(git_dir):
        shutil.rmtree(git_dir, onerror=on_rm_error)
        
    # 4. Extract CallbackHandler-1.0 to root Libs/CallbackHandler-1.0
    # Because the user requested specific siblings: Libs/Ace3, Libs/LibStub, Libs/CallbackHandler-1.0
    cb_src = os.path.join(ace3_dir, "CallbackHandler-1.0")
    cb_dst = os.path.join(LIBS_DIR, "CallbackHandler-1.0")
    
    if os.path.exists(cb_src):
        if os.path.exists(cb_dst):
             shutil.rmtree(cb_dst, onerror=on_rm_error)
        shutil.copytree(cb_src, cb_dst)
        print("Copied CallbackHandler-1.0 to Libs root")
    
    print("Ace3 installed (nested folder).")

def install_others():
    print("--- Installing Other Libraries ---")
    for name, url in OTHER_REPOS.items():
        target_dir = os.path.join(LIBS_DIR, name)
        
        # Remove existing
        if os.path.exists(target_dir):
            shutil.rmtree(target_dir, onerror=on_rm_error)
            
        print(f"Cloning {name}...")
        run_command(f"git clone {url} {target_dir}")

        # Remove .git directory
        git_dir = os.path.join(target_dir, ".git")
        if os.path.exists(git_dir):
            shutil.rmtree(git_dir, onerror=on_rm_error)
            print(f"Removed .git from {name}")

def install_libs():
    if not os.path.exists(LIBS_DIR):
        os.makedirs(LIBS_DIR)
        print(f"Created {LIBS_DIR}")
        
    # We need to clean up the root Libs folder first because previous run flattened everything into it.
    # We want to remove the flattened folders (AceAddon, AceConsole, etc.) but keep Libs dir.
    # A simple way is to delete Libs entirely and recreate, but we need to be careful with permissions.
    # Or just let the script overwrite/delete specific targets.
    # The previous script flattened Ace3 to root. So we have Libs/AceAddon-3.0 etc.
    # We should clean those up to match the "Goal: folder should look like this".
    
    # Let's clean Libs entirely to be safe and ensure clean state matching the Goal.
    # NOTE: This deletes everything in Libs!
    if os.path.exists(LIBS_DIR):
        print("Cleaning Libs directory for fresh install...")
        shutil.rmtree(LIBS_DIR, onerror=on_rm_error)
        os.makedirs(LIBS_DIR)
        
    install_ace3()
    install_others()

if __name__ == "__main__":
    install_libs()
