import os, sys, subprocess

cands = ['/root/.local/bin/agy', '/usr/local/bin/agy', '/usr/bin/agy']
bin_path = None
for p in cands:
    if os.path.isfile(p):
        bin_path = p
        break

if not bin_path:
    sys.exit(0)

# Лок обновлений Antigravity: читаем флаг, выставляемый менеджером.
try:
    with open("/workspace/.update_lock") as _f:
        lock = (_f.read().strip() != "false")
except Exception:
    lock = True  # ON по умолчанию

cache_file = os.path.expanduser("~/.local/share/agy/.patch_cache")
try:
    st = os.stat(bin_path)
    cur_key = f"{st.st_size}_{st.st_mtime_ns}_{lock}_v1.3.8"
    if os.path.exists(cache_file):
        with open(cache_file, "r") as _cf:
            if _cf.read().strip() == cur_key:
                sys.exit(0)
except Exception:
    pass

patcher_dir = "/workspace/open-antigravity-patcher"
bundle = "/workspace/open-antigravity-patcher-v1.3.8.tar"
if not os.path.exists(os.path.join(patcher_dir, "source/main.py")):
    if os.path.exists(bundle):
        # Offline: ships inside the app as a bundled asset (like the Debian rootfs).
        print("[*] Unpacking bundled open-antigravity-patcher v1.3.8 (offline)...")
        os.makedirs(patcher_dir, exist_ok=True)
        subprocess.run(["tar", "xf", bundle, "-C", patcher_dir])
    else:
        # Dev fallback: no bundle present (run outside the app). GIT_TERMINAL_PROMPT=0 —
        # не висеть на запросе логина, если репо приватен/удалён, а падать сразу.
        print("[*] Bundle not found - cloning open-antigravity-patcher V1.3.8 from GitHub...")
        _genv = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
        if subprocess.run(["git", "clone", "--depth", "1", "--branch", "V1.3.8",
                           "https://github.com/AvenCores/open-antigravity-patcher.git", patcher_dir], env=_genv).returncode != 0:
            subprocess.run(["git", "clone", "https://github.com/AvenCores/open-antigravity-patcher.git", patcher_dir], env=_genv)
            subprocess.run(["git", "-C", patcher_dir, "checkout", "fe12d5b06d44bd503cc6b96082aefa859b7241a3"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# Ensure binary is writable before patching (снять иммутабельность, если была)
try:
    os.system(f"chattr -i {bin_path} 2>/dev/null")
    os.chmod(bin_path, 0o755)
except Exception:
    pass

sys.path.insert(0, os.path.join(patcher_dir, "source"))
try:
    from patcher.agy.patcher import is_already_patched, do_patch_agy
    if not is_already_patched(bin_path):
        print("[!] Antigravity CLI is NOT patched! Launching patcher V1.3.8...")
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
        print("[OK] Antigravity CLI is already patched (V1.3.8 region bypass active).")
except Exception as e:
    print(f"[!] Patcher check failed: {e}")
    import traceback; traceback.print_exc()

# Auto-updater URL: при включённом локе глушим (equal-length, ELF-структура цела),
# при выключенном — возвращаем настоящий URL, чтобы agy мог самообновляться.
try:
    with open(bin_path, "rb") as f:
        bindata = f.read()

    updater_url = b"https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
    disabled_url = b"http://127.0.0.1:9999/disabled-auto-updater-server-url-disabled-block"

    if lock:
        if updater_url in bindata:
            print("[*] Neutralizing embedded auto-updater URL (lock ON)...")
            tmp_bin = bin_path + ".tmp2"
            with open(tmp_bin, "wb") as f:
                f.write(bindata.replace(updater_url, disabled_url))
            os.chmod(tmp_bin, 0o755)
            os.replace(tmp_bin, bin_path)
            print("[OK] Auto-updater URL neutralized.")
        else:
            print("[OK] Auto-updater URL already neutralized.")
    else:
        if disabled_url in bindata:
            print("[*] Restoring auto-updater URL (lock OFF)...")
            tmp_bin = bin_path + ".tmp2"
            with open(tmp_bin, "wb") as f:
                f.write(bindata.replace(disabled_url, updater_url))
            os.chmod(tmp_bin, 0o755)
            os.replace(tmp_bin, bin_path)
            print("[OK] Auto-updater URL restored — self-update allowed.")
        else:
            print("[OK] Auto-updater URL intact (lock OFF).")
except Exception as e:
    print(f"[!] Auto-updater note: {e}")

# Привести права бинаря к состоянию лока: ON → иммутабельный/только-чтение,
# OFF → записываемый (чтобы agy мог сам себя обновить).
try:
    if lock:
        os.chmod(bin_path, 0o555)
        os.system(f"chattr +i {bin_path} 2>/dev/null")
    else:
        os.system(f"chattr -i {bin_path} 2>/dev/null")
        os.chmod(bin_path, 0o755)
except Exception:
    pass

try:
    new_st = os.stat(bin_path)
    new_key = f"{new_st.st_size}_{new_st.st_mtime_ns}_{lock}_v1.3.8"
    os.makedirs(os.path.dirname(cache_file), exist_ok=True)
    with open(cache_file, "w") as _cf:
        _cf.write(new_key)
except Exception:
    pass

