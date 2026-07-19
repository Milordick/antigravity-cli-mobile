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
class CompositeGate:
    def __init__(self, gates):
        self.gates = gates
        self.desc = " / ".join(g.desc for g in gates)

    def find(self, data):
        statuses = []
        for g in self.gates:
            try:
                statuses.append(g.find(data)[0])
            except LookupError:
                statuses.append("unknown")
        if all(s == "patched" for s in statuses):
            return ("patched", 0)
        return ("unpatched", 0)

    def write_patches(self, f, data):
        for g in self.gates:
            try:
                kind, off = g.find(data)
                if kind == "unpatched" or kind == "patched":
                    f.seek(off)
                    f.write(g.fix)
            except LookupError:
                pass

LINUX_ARM64_CLI_GATE = CompositeGate([
    Gate(
        rb"\xfd\x7b\xbe\xa9\xf4\x4f\x01\xa9\xfd\x03\x00\x91\x80.\x00\xb4........\x28\xfd\xdf\x08\x88.\x00\x36\x08\x20\x40\x39\xa8.\x00\x37",
        rb"\xfd\x7b\xbe\xa9\xf4\x4f\x01\xa9\xfd\x03\x00\x91\x80.\x00\xb4........\x28\xfd\xdf\x08\x88.\x00\x36\x28\x00\x80\x52\xa8.\x00\x37",
        b"\x28\x00\x80\x52",
        offset=32,
        desc="eligibility gate 1 (linux arm64)"
    ),
    Gate(
        rb"\x01..\xb5...\xb4\x08\x20\x40\x39...\x37\x08\xa4\x44\xa9",
        rb"\x01..\xb5...\xb4\x28\x00\x80\x52...\x37\x08\xa4\x44\xa9",
        b"\x28\x00\x80\x52",
        offset=8,
        desc="eligibility gate 2 (linux arm64)"
    )
])
"""
    # Remove any existing CompositeGate class and LINUX_ARM64_CLI_GATE
    code = re.sub(r'class CompositeGate[\s\S]*?LINUX_ARM64_CLI_GATE\s*=\s*CompositeGate\([\s\S]*?\]\)\n', '', code)
    code = re.sub(r'LINUX_ARM64_CLI_GATE\s*=\s*Gate\([\s\S]*?desc="eligibility screen off \(linux arm64\)"\n\)', '', code)
    
    # Re-insert the correct gate after ARM64_CLI_GATE
    insert_pos = code.find('desc="eligibility screen off (arm64)",\n)') + len('desc="eligibility screen off (arm64)",\n)')
    if insert_pos > 100:
        code = code[:insert_pos] + "\n\n" + correct_gate.strip() + "\n" + code[insert_pos:]
        
        # Modify do_patch_agy write logic to handle CompositeGate
        old_write = '            with open(path, "r+b") as f:\n                f.seek(off)\n                f.write(gate.fix)'
        new_write = '            with open(path, "r+b") as f:\n                if hasattr(gate, "write_patches"):\n                    gate.write_patches(f, d)\n                else:\n                    f.seek(off)\n                    f.write(gate.fix)'
        code = code.replace(old_write, new_write)

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

