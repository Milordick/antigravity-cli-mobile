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
    print("[*] Cloning open-antigravity-patcher V1.3.4 from GitHub...")
    subprocess.run(["git", "clone", "--branch", "V1.3.4", "https://github.com/AvenCores/open-antigravity-patcher.git", patcher_dir])
    if not os.path.exists(os.path.join(patcher_dir, "source/main.py")):
        subprocess.run(["git", "clone", "https://github.com/AvenCores/open-antigravity-patcher.git", patcher_dir])
        subprocess.run(["git", "-C", patcher_dir, "checkout", "V1.3.4"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["git", "-C", patcher_dir, "checkout", "a4c660871554b3c25279e1214246a7918eedb63f"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
else:
    # Ensure V1.3.4
    try:
        subprocess.run(["git", "-C", patcher_dir, "fetch", "--tags"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        subprocess.run(["git", "-C", patcher_dir, "checkout", "V1.3.4"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    except Exception:
        pass

# Ensure binary is writable before patching
try:
    os.chmod(bin_path, 0o755)
except Exception:
    pass

sys.path.insert(0, os.path.join(patcher_dir, "source"))
try:
    from patcher.agy.patcher import is_already_patched, do_patch_agy
    if not is_already_patched(bin_path):
        print("[!] Antigravity CLI is NOT patched! Launching patcher V1.3.4...")
        import shutil
        tmp_bin = bin_path + ".tmp"
        shutil.copy2(bin_path, tmp_bin)
        do_patch_agy(tmp_bin)
        os.replace(tmp_bin, bin_path)
        try:
            subprocess.run(["pkill", "-9", "-x", "agy"], stderr=subprocess.DEVNULL)
        except Exception:
            pass
    else:
        print("[OK] Antigravity CLI is already patched (V1.3.4 region bypass active).")
except Exception as e:
    print(f"[!] Patcher check failed: {e}")
    import traceback; traceback.print_exc()

# Neutralize embedded auto-updater URL in binary using exact 69-byte string to preserve ELF structure
try:
    with open(bin_path, "rb") as f:
        bindata = f.read()

    updater_url = b"https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
    disabled_url = b"http://127.0.0.1:9999/disabled-auto-updater-server-url-disabled-block"

    if updater_url in bindata:
        print("[*] Neutralizing embedded auto-updater URL in agy binary...")
        tmp_bin = bin_path + ".tmp2"
        with open(tmp_bin, "wb") as f:
            f.write(bindata.replace(updater_url, disabled_url))
        os.chmod(tmp_bin, 0o755)
        os.replace(tmp_bin, bin_path)
        print("[OK] Embedded auto-updater URL successfully neutralized.")
    else:
        print("[OK] Embedded auto-updater URL is already neutralized.")
except Exception as e:
    print(f"[!] Auto-updater neutralization note: {e}")

# Re-apply executable permissions
try:
    os.chmod(bin_path, 0o755)
except Exception:
    pass
