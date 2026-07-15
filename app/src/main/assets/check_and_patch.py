import os, sys, re, struct, subprocess

cands = ['/root/.local/bin/agy', '/usr/local/bin/agy', '/usr/bin/agy']
bin_path = None
for p in cands:
    if os.path.isfile(p):
        bin_path = p
        break

if not bin_path:
    sys.exit(0)

with open(bin_path, "rb") as f:
    d = f.read()

u1 = re.search(b'[\x00-\xff]{2}\x40\xf9[\x00-\xff]{2}[\x00-\xff]\xf9[\x00-\xff]{3}\x97[\x00-\xff]{3}\xb5[\x00-\xff]{3}\xb4\x03\x20\x40\x39[\x00-\xff]{3}\x37', d)
p1 = re.search(b'[\x00-\xff]{2}\x40\xf9[\x00-\xff]{2}[\x00-\xff]\xf9[\x00-\xff]{3}\x97\x1f\x20\x03\xd5[\x00-\xff]{3}\xb4\x23\x00\x80\x52[\x00-\xff]{3}\x37', d)
u2 = re.search(rb'\x48\x85\xc0\x0f\x84.{4}\x80\x78\x08\x00\x0f\x85.{4}', d, re.S)
p2 = re.search(rb'\x48\x85\xc0\x0f\x84.{4}\x48\x85\xc0\x90\x0f\x85.{4}', d, re.S)

is_patched = False
is_unpatched = False

if d[:4] == b"\x7fELF" and len(d) >= 20:
    endian = d[5]
    fmt = "<H" if endian == 1 else ">H"
    machine = struct.unpack_from(fmt, d, 18)[0]
    if machine == 183:
        if p1: is_patched = True
        elif u1: is_unpatched = True
    elif machine == 62:
        if p2: is_patched = True
        elif u2: is_unpatched = True

if is_patched:
    print("[OK] Antigravity CLI is already patched (region bypass active).")
    sys.exit(0)

if not is_unpatched:
    sys.exit(0)

print("[!] Antigravity CLI is NOT patched! Launching patcher...")

patcher_dir = "/workspace/open-antigravity-patcher"
if not os.path.exists(os.path.join(patcher_dir, "source/main.py")):
    print("[*] Cloning open-antigravity-patcher from GitHub...")
    subprocess.run(["git", "clone", "https://github.com/AvenCores/open-antigravity-patcher.git", patcher_dir])

if os.path.exists(os.path.join(patcher_dir, "source/main.py")):
    # Discard any previous modifications to start fresh
    subprocess.run(["git", "-C", patcher_dir, "checkout", "source/patcher/agy/patcher.py"], stderr=subprocess.DEVNULL)
    
    apply_script = os.path.join(patcher_dir, "__apply_patcher_auto.py")
    with open(apply_script, "w", encoding="utf-8") as f:
        f.write('''import os
path = '/workspace/open-antigravity-patcher/source/patcher/agy/patcher.py'
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        code = f.read()
        
    new_gate = """LINUX_ARM64_CLI_GATE = Gate(
    rb"[\\\\x00-\\\\xff]{2}\\\\x40\\\\xf9[\\\\x00-\\\\xff]{2}[\\\\x00-\\\\xff]\\\\xf9[\\\\x00-\\\\xff]{3}\\\\x97[\\\\x00-\\\\xff]{3}\\\\xb5[\\\\x00-\\\\xff]{3}\\\\xb4\\\\x03\\\\x20\\\\x40\\\\x39[\\\\x00-\\\\xff]{3}\\\\x37",
    rb"[\\\\x00-\\\\xff]{2}\\\\x40\\\\xf9[\\\\x00-\\\\xff]{2}[\\\\x00-\\\\xff]\\\\xf9[\\\\x00-\\\\xff]{3}\\\\x97\\\\x1f\\\\x20\\\\x03\\\\xd5[\\\\x00-\\\\xff]{3}\\\\xb4\\\\x23\\\\x00\\\\x80\\\\x52[\\\\x00-\\\\xff]{3}\\\\x37",
    b"\\\\x1f\\\\x20\\\\x03\\\\xd5\\\\x80\\\\x15\\\\x00\\\\xb4\\\\x23\\\\x00\\\\x80\\\\x52",
    offset=12,
    desc="eligibility screen off (linux arm64)"
)"""
    new_detect = """def _detect_arch(path):
    try:
        with open(path, "rb") as f:
            hdr = f.read(20)
        if len(hdr) < 8:
            return "unknown"
        magic = hdr[:4]
        if magic == b"\\\\xcf\\\\xfa\\\\xed\\\\xfe":          
            cputype = struct.unpack_from("<I", hdr, 4)[0]
            if cputype == 0x0100000c or cputype == 0x0100000C:
                return "arm64"
            if cputype == 0x01000007:
                return "x86_64"
        elif magic == b"\\\\x7fELF":                 
            if len(hdr) >= 20:
                endian = "<" if hdr[5] == 1 else ">"
                e_machine = struct.unpack_from(endian + "H", hdr, 18)[0]
                if e_machine == 183:              
                    return "linux_arm64"
                elif e_machine == 62:             
                    return "x86_64"
        elif hdr[:2] == b"MZ":                    
            return "x86_64"
    except Exception:
        pass
    return "unknown"

"""
    if "LINUX_ARM64_CLI_GATE" not in code:
        idx_desc = code.find('desc="eligibility screen off (arm64)",')
        if idx_desc == -1:
            idx_desc = code.find("desc='eligibility screen off (arm64)',")
        if idx_desc != -1:
            idx_line_end = code.find("\\n", idx_desc)
            if idx_line_end != -1:
                idx_gate_end = code.find(")", idx_line_end)
                if idx_gate_end != -1:
                    code = code[:idx_gate_end+1] + "\\n\\n" + new_gate + code[idx_gate_end+1:]
        
    idx = code.find("def _detect_arch(path):")
    idx2 = code.find("def _gate_for(path):")
    if idx != -1 and idx2 != -1:
        code = code[:idx] + new_detect + code[idx2:]
        
    old_ret = 'return ARM64_CLI_GATE if _detect_arch(path) == "arm64" else CLI_GATE'
    new_ret = 'arch = _detect_arch(path)\\n    if arch == "linux_arm64":\\n        return LINUX_ARM64_CLI_GATE\\n    return ARM64_CLI_GATE if arch == "arm64" else CLI_GATE'
    code = code.replace(old_ret, new_ret)
    
    with open(path, 'w', encoding='utf-8') as f:
        f.write(code)
    print("[OK] Successfully patched patcher.py!")
''')
    subprocess.run([sys.executable, apply_script])
    auto_apply = os.path.join(patcher_dir, "__auto_apply_patch.py")
    with open(auto_apply, "w", encoding="utf-8") as f:
        f.write(f'''import sys
sys.path.insert(0, '/workspace/open-antigravity-patcher/source')
from patcher.agy.patcher import do_patch_agy
do_patch_agy("{bin_path}")
''')
    subprocess.run([sys.executable, auto_apply])
    try:
        subprocess.run(["pkill", "-9", "-x", "agy"], stderr=subprocess.DEVNULL)
    except:
        pass
else:
    print("[!] Failed to get open-antigravity-patcher.")
