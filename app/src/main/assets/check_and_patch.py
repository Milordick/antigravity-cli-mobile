import os, sys, subprocess, re

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

# Force update to latest disabled per user request
# subprocess.run(["git", "-C", patcher_dir, "fetch", "origin", "main"], stderr=subprocess.DEVNULL)
# subprocess.run(["git", "-C", patcher_dir, "reset", "--hard", "origin/main"], stderr=subprocess.DEVNULL)

# Hotfix the patcher for linux_arm64 signature (tbz w3 vs tbnz w3)
patcher_file = os.path.join(patcher_dir, "source/patcher/agy/patcher.py")
if os.path.exists(patcher_file):
    with open(patcher_file, "r", encoding="utf-8") as f:
        code = f.read()
    
    correct_gate = r"""
LINUX_ARM64_CLI_GATE = Gate(
    rb"[\x01\x21\x41\x61\x81\xa1\xc1\xe1].\x00\xb5[\x00\x20\x40\x60\x80\xa0\xc0\xe0].\x00\xb4\x03\x20\x40\x39[\x03\x23\x43\x63\x83\xa3\xc3\xe3].\x00\x36",
    rb"[\x01\x21\x41\x61\x81\xa1\xc1\xe1].\x00\xb5[\x00\x20\x40\x60\x80\xa0\xc0\xe0].\x00\xb4\x23\x00\x80\x52[\x03\x23\x43\x63\x83\xa3\xc3\xe3].\x00\x36",
    b"\x23\x00\x80\x52",
    offset=8,
    desc="eligibility screen off (linux arm64)"
)
"""
    # Remove any existing LINUX_ARM64_CLI_GATE
    code = re.sub(r'LINUX_ARM64_CLI_GATE\s*=\s*Gate\([\s\S]*?desc="eligibility screen off \(linux arm64\)"\n\)', '', code)
    
    # Re-insert the correct gate after ARM64_CLI_GATE
    insert_pos = code.find('desc="eligibility screen off (arm64)",\n)') + len('desc="eligibility screen off (arm64)",\n)')
    if insert_pos > 100:
        code = code[:insert_pos] + "\n\n" + correct_gate.strip() + "\n" + code[insert_pos:]
        
        # Make sure _detect_arch is hooked up
        if 'arch == "linux_arm64":' not in code:
            old_ret = 'return ARM64_CLI_GATE if arch == "arm64" else CLI_GATE'
            new_ret = 'if arch == "linux_arm64":\n        return LINUX_ARM64_CLI_GATE\n    return ARM64_CLI_GATE if arch == "arm64" else CLI_GATE'
            code = code.replace(old_ret, new_ret)
            old_ret2 = 'return ARM64_CLI_GATE if _detect_arch(path) == "arm64" else CLI_GATE'
            new_ret2 = 'arch = _detect_arch(path)\n    if arch == "linux_arm64":\n        return LINUX_ARM64_CLI_GATE\n    return ARM64_CLI_GATE if arch == "arm64" else CLI_GATE'
            code = code.replace(old_ret2, new_ret2)
        # Fix _detect_arch to return "linux_arm64" for ELF AARCH64
        code = re.sub(r'elif machine == 183:[ \t]*# EM_AARCH64 \(ARM64\)\n[ \t]*return "arm64"', 
                      r'elif machine == 183:\n                    return "linux_arm64"', code)
            
        with open(patcher_file, "w", encoding="utf-8", newline="\n") as f:
            f.write(code)

sys.path.insert(0, os.path.join(patcher_dir, "source"))
try:
    from patcher.agy.patcher import is_already_patched, do_patch_agy
    if is_already_patched(bin_path):
        print("[OK] Antigravity CLI is already patched (region bypass active).")
        sys.exit(0)

    print("[!] Antigravity CLI is NOT patched! Launching patcher...")
    do_patch_agy(bin_path)
    try:
        subprocess.run(["pkill", "-9", "-x", "agy"], stderr=subprocess.DEVNULL)
    except Exception:
        pass
except Exception as e:
    print(f"[!] Patcher check failed: {e}")
