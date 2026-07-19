import os, sys, subprocess

cands = ['/root/.local/bin/agy', '/usr/local/bin/agy', '/usr/bin/agy']
bin_path = None
for p in cands:
    if os.path.isfile(p):
        bin_path = p
        break

if not bin_path:
    sys.exit(0)

patcher_dir = "/workspace/open-antigravity-patcher"
if not os.path.exists(os.path.join(patcher_dir, "source/main.py")):
    print("[*] Cloning open-antigravity-patcher from GitHub...")
    subprocess.run(["git", "clone", "https://github.com/AvenCores/open-antigravity-patcher.git", patcher_dir])

sys.path.insert(0, os.path.join(patcher_dir, "source"))
try:
    from patcher.agy.patcher import is_already_patched, do_patch_agy
    if is_already_patched(bin_path):
        print("[OK] Antigravity CLI is already patched (region bypass active).")
        sys.exit(0)

    print("[!] Antigravity CLI is NOT patched! Launching patcher 1.2.5...")
    do_patch_agy(bin_path)
    try:
        subprocess.run(["pkill", "-9", "-x", "agy"], stderr=subprocess.DEVNULL)
    except Exception:
        pass
except Exception as e:
    print(f"[!] Patcher check failed: {e}")
