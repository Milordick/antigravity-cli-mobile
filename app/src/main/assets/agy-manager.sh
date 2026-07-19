#!/bin/bash
# ==============================================================================
# Antigravity CLI (agy) -- Debian Sandbox Launcher
# ==============================================================================

[ -z "$PREFIX" ] && PREFIX="/data/data/com.agycli/files/usr"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

WORKSPACE_DIR="/sdcard/AntigravityWorkspace"
PROXY_CONFIG="$WORKSPACE_DIR/proxy_config.sh"
XRAY_CONFIG="$WORKSPACE_DIR/xray_config.json"
XRAY_TEMPLATE="$WORKSPACE_DIR/xray_config.json.template"
VLESS_SETTINGS="$WORKSPACE_DIR/vless_settings.sh"
LAST_DIR_FILE="$WORKSPACE_DIR/.last_dir"
PROOT_BIN="$PREFIX/bin/proot"

# -----------------------------------------------------------------------------
show_banner() {
    clear
    local W
    W=$(tput cols 2>/dev/null || echo 60)
    # Clamp: min 30, max 80
    [ "$W" -lt 30 ] && W=30
    [ "$W" -gt 80 ] && W=80

    local inner=$((W - 4))  # space inside || borders
    local line
    printf -v line '%*s' "$((W - 2))" ''; line="${line// /=}"

    local title="ANTIGRAVITY CLI  //  DEBIAN SANDBOX"
    local sub="Powered by proot-distro  *  Debian Bookworm"

    # Center text inside inner width
    _center() {
        local txt="$1" len="${#1}" pad
        pad=$(( (inner - len) / 2 ))
        [ "$pad" -lt 0 ] && pad=0
        local right_pad=$(( inner - len - pad ))
        [ "$right_pad" -lt 0 ] && right_pad=0
        printf "  ||%*s%s%*s||" "$pad" '' "$txt" "$right_pad" ''
    }

    echo ""
    echo -e "${MAGENTA}${BOLD}  =${line}=${NC}"
    echo -e "${MAGENTA}${BOLD}  ||$(printf '%*s' "$inner" '')||${NC}"
    echo -e "${MAGENTA}${BOLD}$(_center "$title")${NC}"
    echo -e "${MAGENTA}${BOLD}  ||$(printf '%*s' "$inner" '')||${NC}"
    echo -e "${MAGENTA}${BOLD}  =${line}=${NC}"
    echo ""
    echo -e "${CYAN}${DIM}$(_center "$sub")${NC}"
    echo ""
}


# -----------------------------------------------------------------------------
log_info()  { echo -e "${BLUE}  [*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}  [OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}  [!]${NC} $1"; }
log_error() { echo -e "${RED}  [!!]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}${BOLD}  ==== $1 ====${NC}"; }

# -----------------------------------------------------------------------------
generate_xray_config() {
    [ -f "$PROXY_CONFIG" ] && source "$PROXY_CONFIG"
    XRAY_PORT="${XRAY_PORT:-10808}"
    
    # Copy generate_proxy_config.py to workspace so it is available inside Debian
    local update_gen="false"
    if [ -f "$PREFIX/bin/generate_proxy_config.py" ]; then
        if [ -f "$WORKSPACE_DIR/generate_proxy_config.py" ]; then
            HASH_SRC=$(sha256sum "$PREFIX/bin/generate_proxy_config.py" | cut -d" " -f1)
            HASH_DST=$(sha256sum "$WORKSPACE_DIR/generate_proxy_config.py" | cut -d" " -f1)
            if [ "$HASH_SRC" != "$HASH_DST" ]; then
                update_gen="true"
            fi
        else
            update_gen="true"
        fi
        if [ "$update_gen" = "true" ]; then
            log_info "Updating config generator (generate_proxy_config.py)..."
            cp "$PREFIX/bin/generate_proxy_config.py" "$WORKSPACE_DIR/generate_proxy_config.py"
        fi
    elif [ -f "/sdcard/AntigravityWorkspace/generate_proxy_config.py" ]; then
        cp "/sdcard/AntigravityWorkspace/generate_proxy_config.py" "$WORKSPACE_DIR/generate_proxy_config.py"
    fi
    
    if [ -f "$WORKSPACE_DIR/vless_link.txt" ]; then
        # Run config generator inside Debian using python3
        proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" --bind "/sdcard:/sdcard" -- /usr/bin/python3 /workspace/generate_proxy_config.py /workspace/vless_link.txt "$XRAY_PORT" /workspace >/dev/null 2>&1
        return $?
    fi
    return 1
}

parse_vless_link() {
    local link="$1"
    if [[ "$link" =~ ^vless://([^@]+)@([^:]+):([0-9]+)\?(.*)$ ]]; then
        VLESS_UUID="${BASH_REMATCH[1]}"
        VLESS_ADDR="${BASH_REMATCH[2]}"
        VLESS_PORT="${BASH_REMATCH[3]}"
        local q="${BASH_REMATCH[4]%%#*}"
        VLESS_FLOW=""; VLESS_SNI=""; VLESS_PUBKEY=""; VLESS_SHORTID=""
        IFS='&' read -ra params <<< "$q"
        for p in "${params[@]}"; do
            local k="${p%%=*}" v="${p#*=}"
            v=$(echo -e "${v//%/\\x}")
            case "$k" in
                sni)  VLESS_SNI="$v"     ;;
                pbk)  VLESS_PUBKEY="$v"  ;;
                flow) VLESS_FLOW="$v"    ;;
                sid)  VLESS_SHORTID="$v" ;;
            esac
        done
        return 0
    fi
    return 1
}

is_initialized() {
    [ ! -d "$WORKSPACE_DIR" ]         && return 1
    [ ! -f "$PROXY_CONFIG" ]          && return 1
    [ ! -f "$PROOT_BIN" ]             && return 1
    ! command -v proot-distro &>/dev/null && return 1
    # Check installed rootfs directory directly — more reliable than parsing list output
    [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/debian" ] && return 1
    return 0
}

request_storage() {
    if [ ! -w "/sdcard" ]; then
        show_banner
        log_warn "Storage access required. Tap ALLOW in the dialog, then press ENTER."
        termux-setup-storage
        read -r
        local i=0
        while [ ! -w "/sdcard" ] && [ $i -lt 10 ]; do sleep 1; ((i++)); done
        if [ ! -w "/sdcard" ]; then
            log_error "Storage permission not granted. Cannot continue."
            exit 1
        fi
        log_ok "Storage access granted!"
        sleep 1
    fi
}

# -----------------------------------------------------------------------------
do_init() {
    request_storage
    show_banner
    log_step "First-Run Setup"
    echo ""

    mkdir -p "$WORKSPACE_DIR" "$PREFIX/tmp"

    # -- Default configs -------------------------------------------------------
    if [ ! -f "$PROXY_CONFIG" ]; then
        cat << 'EOF' > "$PROXY_CONFIG"
USE_PROXY="false"
PROXY_TYPE="xray"
PROXY_ADDR="127.0.0.1"
PROXY_PORT="10808"
XRAY_PORT="10808"
EOF
        chmod +x "$PROXY_CONFIG"
    fi

    if [ ! -f "$VLESS_SETTINGS" ]; then
        cat << 'EOF' > "$VLESS_SETTINGS"
VLESS_ADDR="YOUR_SERVER"
VLESS_PORT="443"
VLESS_UUID="YOUR_UUID"
VLESS_FLOW="xtls-rprx-vision"
VLESS_SNI="YOUR_SNI"
VLESS_PUBKEY="YOUR_KEY"
VLESS_SHORTID=""
EOF
    fi

    # Backward compatibility: Convert VLESS_SETTINGS to vless_link.txt if it doesn't exist
    if [ -f "$VLESS_SETTINGS" ] && [ ! -f "$WORKSPACE_DIR/vless_link.txt" ]; then
        source "$VLESS_SETTINGS"
        if [ -n "$VLESS_PUBKEY" ]; then
            VLESS_URL="vless://${VLESS_UUID}@${VLESS_ADDR}:${VLESS_PORT}?security=reality&flow=${VLESS_FLOW}&sni=${VLESS_SNI}&pbk=${VLESS_PUBKEY}&sid=${VLESS_SHORTID}"
        else
            VLESS_URL="vless://${VLESS_UUID}@${VLESS_ADDR}:${VLESS_PORT}?security=tls&flow=${VLESS_FLOW}&sni=${VLESS_SNI}"
        fi
        echo "$VLESS_URL" > "$WORKSPACE_DIR/vless_link.txt"
    fi

    # Copy generate_xray_config.py to workspace
    if [ -f "$PREFIX/bin/generate_xray_config.py" ]; then
        cp "$PREFIX/bin/generate_xray_config.py" "$WORKSPACE_DIR/generate_xray_config.py"
    elif [ -f "/sdcard/AntigravityWorkspace/generate_xray_config.py" ]; then
        cp "/sdcard/AntigravityWorkspace/generate_xray_config.py" "$WORKSPACE_DIR/generate_xray_config.py"
    fi

    # Always ensure XRAY_TEMPLATE is up to date (HTTP proxy inbound is required for apt/curl)
    cat << 'EOF' > "$XRAY_TEMPLATE"
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": XRAY_PORT_PLACEHOLDER,
    "protocol": "socks",
    "settings": { "auth": "noauth", "udp": true, "ip": "127.0.0.1" },
    "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
  },
  {
    "port": XRAY_HTTP_PORT_PLACEHOLDER,
    "protocol": "http",
    "settings": { "allowTransparent": false },
    "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "VLESS_ADDRESS_PLACEHOLDER",
        "port": VLESS_PORT_PLACEHOLDER,
        "users": [{ "id": "VLESS_UUID_PLACEHOLDER", "encryption": "none", "flow": "VLESS_FLOW_PLACEHOLDER" }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "fingerprint": "chrome",
        "serverName": "VLESS_SNI_PLACEHOLDER",
        "publicKey": "VLESS_PUBKEY_PLACEHOLDER",
        "shortId": "VLESS_SHORTID_PLACEHOLDER"
      }
    }
  }, { "protocol": "freedom", "tag": "direct" }]
}
EOF
    generate_xray_config

    # -- Extra keys ------------------------------------------------------------
    mkdir -p "$HOME/.termux"
    if ! grep -q "extra-keys" "$HOME/.termux/termux.properties" 2>/dev/null; then
        log_info "Configuring terminal extra keys..."
        cat << 'EOF' >> "$HOME/.termux/termux.properties"

extra-keys = [ \
  ['ESC','/','-','HOME','UP','END','PGUP'], \
  ['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN'] \
]
EOF
        termux-reload-settings 2>/dev/null || true
    fi

    # -- Validate proot --------------------------------------------------------
    log_step "Checking proot"
    if [ ! -f "$PROOT_BIN" ]; then
        log_warn "proot not in bootstrap -- installing via pkg..."
        pkg update -y -q 2>&1 | tail -3
        pkg install proot -y -q 2>&1 | tail -5
        if [ ! -f "$PROOT_BIN" ]; then
            log_error "Failed to install proot. Cannot continue."
            exit 1
        fi
    fi
    chmod +x "$PROOT_BIN"
    log_ok "proot ready: $(proot --version 2>&1 | head -1)"

    # -- Validate proot-distro -------------------------------------------------
    log_step "Checking proot-distro"
    if ! command -v proot-distro &>/dev/null; then
        log_error "proot-distro not found in bootstrap!"
        exit 1
    fi
    log_ok "proot-distro ready."

    # -- Install Debian --------------------------------------------------------
    log_step "Installing Debian container"
    if proot-distro list 2>/dev/null | grep -q 'debian'; then
        log_ok "Debian already installed."
    else
        log_info "Downloading Debian Bookworm (showing progress)..."
        # Run directly without redirection so curl progress bar is shown live to the user
        if ! proot-distro install debian; then
            log_error "Debian installation failed."
            exit 1
        fi
        log_ok "Debian installed."
    fi

    # -- Configure Debian guest ------------------------------------------------
    log_step "Configuring Debian"
    proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" --bind "/sdcard:/sdcard" -- /bin/bash << 'DEBIAN_SETUP'
set -e
export DEBIAN_FRONTEND=noninteractive

if [ -f "/workspace/proxy_config.sh" ]; then
    source "/workspace/proxy_config.sh"
fi

echo "[*] Updating package list (apt-get update)..."
apt-get update

echo "[*] Installing base packages (python, git, curl, unzip, etc.)..."
apt-get install -y --no-install-recommends \
    curl ca-certificates unzip procps git xz-utils python3 python3-packaging

# xray/hysteria cores are now dynamically downloaded on-demand when starting the proxy

# agy CLI
echo "[*] Installing Antigravity CLI..."
curl -fsSL https://antigravity.google/cli/install.sh | bash 2>&1 || true

# bash.bashrc additions (idempotent)
grep -q 'AGY_TRACK' /etc/bash.bashrc 2>/dev/null || cat >> /etc/bash.bashrc << 'BASHRC'

# AGY_TRACK -- Antigravity workspace tracker
_agy_track_dir() {
    [[ "$PWD" == /workspace* ]] && echo "$PWD" > /workspace/.last_dir 2>/dev/null
}
PROMPT_COMMAND="_agy_track_dir${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
export PATH="$HOME/.local/bin:$PATH"
BASHRC

# Launch wrapper
cat > /usr/local/bin/start-agy.sh << 'WRAPPER'
#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
[ -f /workspace/proxy_config.sh ] && source /workspace/proxy_config.sh

if [ "$USE_PROXY" = "true" ] && [ "$PROXY_TYPE" = "xray" ]; then
    if ! pgrep -x xray > /dev/null 2>&1; then
        [ -f /workspace/xray_config.json ] && \
            nohup /usr/local/bin/xray run -c /workspace/xray_config.json \
            > /tmp/xray.log 2>&1 &
        sleep 1
    fi
    # Use HTTP proxy inbound because many CLI tools (apt, curl) fail with pure SOCKS5
    export HTTP_PROXY="http://127.0.0.1:$(( ${XRAY_PORT:-10808} + 1 ))"
    export HTTPS_PROXY="$HTTP_PROXY"
    export ALL_PROXY="$HTTP_PROXY"
elif [ "$USE_PROXY" = "true" ]; then
    export HTTP_PROXY="${PROXY_TYPE}://${PROXY_ADDR}:${PROXY_PORT}"
    export HTTPS_PROXY="$HTTP_PROXY"
    export ALL_PROXY="$HTTP_PROXY"
fi

TARGET="/workspace"
[ -f /workspace/.last_dir ] \
    && SAVED=$(cat /workspace/.last_dir) \
    && [ -d "$SAVED" ] \
    && TARGET="$SAVED"
cd "$TARGET"

echo -e "\e[1;36m[Antigravity]\e[0m  Workspace: $TARGET"
if command -v agy > /dev/null 2>&1; then
    exec agy "$@"
elif [ -f "$HOME/.local/bin/agy" ]; then
    exec "$HOME/.local/bin/agy" "$@"
else
    echo -e "\e[33m[!] agy not found -- dropping into bash.\e[0m"
    exec bash
fi
WRAPPER
chmod +x /usr/local/bin/start-agy.sh
echo "[OK] Debian guest configured."
DEBIAN_SETUP

    echo ""
    log_ok "Setup complete! Launching sandbox..."
    sleep 1
    do_start_inner
}

# -----------------------------------------------------------------------------
do_start_inner() {
    [ -f "$PROXY_CONFIG" ] && source "$PROXY_CONFIG"

    # Auto-heal Debian guest container (upgrades check for packages)
    if ! proot-distro login debian -- command -v python3 >/dev/null 2>&1 ||        ! proot-distro login debian -- command -v git >/dev/null 2>&1 ||        ! proot-distro login debian -- python3 -c "import packaging" >/dev/null 2>&1; then
        log_warn "Debian container is missing required packages (python3/git/packaging)."
        log_info "Attempting to auto-upgrade container packages..."
        if proot-distro login debian -- apt-get update &&            proot-distro login debian -- apt-get install -y --no-install-recommends python3 git curl ca-certificates unzip procps xz-utils python3-packaging; then
            log_ok "Container packages upgraded successfully."
        else
            log_error "Failed to upgrade container. Some features (xray config, patcher) may not work without internet."
            sleep 2
        fi
    fi

    # xray/hysteria cores are now dynamically downloaded on-demand inside the guest when the proxy is started

    local EXTRA_BINDS=""
    [ -d "$WORKSPACE_DIR" ] && EXTRA_BINDS="$EXTRA_BINDS --bind $WORKSPACE_DIR:/workspace"
    [ -d "/sdcard" ]        && EXTRA_BINDS="$EXTRA_BINDS --bind /sdcard:/sdcard"

    # Copy check_and_patch.py directly from Termux bin to workspace
    if [ -f "$PREFIX/bin/check_and_patch.py" ]; then
        cp "$PREFIX/bin/check_and_patch.py" "$WORKSPACE_DIR/check_and_patch.py"
    fi

    # Always write an up-to-date start-agy.sh to workspace so Debian picks it up.
    # The workspace is mounted as /workspace inside Debian.
    cat > "$WORKSPACE_DIR/start-agy.sh" << 'START_AGY'
#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
[ -f /workspace/proxy_config.sh ] && source /workspace/proxy_config.sh

if [ "$USE_PROXY" = "true" ] && { [ "$PROXY_TYPE" = "xray" ] || [ "$PROXY_TYPE" = "hysteria2" ]; }; then
    ENGINE="xray"
    [ -f /workspace/proxy_engine.txt ] && ENGINE=$(cat /workspace/proxy_engine.txt)
    pkill -x xray >/dev/null 2>&1 || true
    pkill -x hysteria >/dev/null 2>&1 || true
    if [ "$ENGINE" = "xray" ]; then
        if [ ! -f /usr/local/bin/xray ]; then
            echo -e "\e[33m[*] Xray core is missing inside Debian. Downloading...\e[0m"
            ARCH=$(uname -m)
            case "$ARCH" in
                aarch64) XRAY_ARCH="arm64-v8a" ;;
                x86_64)  XRAY_ARCH="64" ;;
                armv7l)  XRAY_ARCH="arm32-v7a" ;;
                *)       XRAY_ARCH="64" ;;
            esac
            curl -# -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" \
                && unzip -q -o /tmp/xray.zip -d /usr/local/bin/ xray \
                && chmod +x /usr/local/bin/xray \
                && rm -f /tmp/xray.zip \
                && echo -e "\e[32m[OK] Xray installed.\e[0m" \
                || { echo -e "\e[31m[!] Failed to download Xray core.\e[0m"; exit 1; }
        fi
        if [ -f /workspace/xray_config.json ]; then
            nohup /usr/local/bin/xray run -c /workspace/xray_config.json >/tmp/xray.log 2>&1 &
            sleep 1
        fi
    elif [ "$ENGINE" = "hysteria" ]; then
        if [ ! -f /usr/local/bin/hysteria ]; then
            echo -e "\e[33m[*] Hysteria core is missing inside Debian. Downloading...\e[0m"
            ARCH=$(uname -m)
            case "$ARCH" in
                aarch64) HY_ARCH="arm64" ;;
                x86_64)  HY_ARCH="amd64" ;;
                armv7l)  HY_ARCH="arm" ;;
                *)       HY_ARCH="amd64" ;;
            esac
            curl -# -L -o /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${HY_ARCH}" \
                && chmod +x /usr/local/bin/hysteria \
                && echo -e "\e[32m[OK] Hysteria installed.\e[0m" \
                || { echo -e "\e[31m[!] Failed to download Hysteria core.\e[0m"; exit 1; }
        fi
        if [ -f /workspace/hysteria_config.json ]; then
            nohup /usr/local/bin/hysteria -c /workspace/hysteria_config.json client >/tmp/hysteria.log 2>&1 &
            sleep 1
        fi
    fi
    export HTTP_PROXY="http://127.0.0.1:$(( ${XRAY_PORT:-10808} + 1 ))"
    export HTTPS_PROXY="$HTTP_PROXY"
    export ALL_PROXY="$HTTP_PROXY"
else
    pkill -x xray >/dev/null 2>&1 || true
    pkill -x hysteria >/dev/null 2>&1 || true
fi
if [ "$USE_PROXY" = "true" ] && [ "$PROXY_TYPE" != "xray" ] && [ "$PROXY_TYPE" != "hysteria2" ]; then
    export HTTP_PROXY="${PROXY_TYPE}://${PROXY_ADDR}:${PROXY_PORT}"
    export HTTPS_PROXY="$HTTP_PROXY"
    export ALL_PROXY="$HTTP_PROXY"
fi

TARGET="/workspace"
[ -f /workspace/.last_dir ] && SAVED=$(cat /workspace/.last_dir) && [ -d "$SAVED" ] && TARGET="$SAVED"
cd "$TARGET"

echo -e "\e[1;36m[Antigravity]\e[0m  Workspace: $TARGET"

# Check if agy is installed. If not, install it synchronously.
if ! command -v agy > /dev/null 2>&1 && [ ! -f "$HOME/.local/bin/agy" ]; then
    echo -e "\e[1;36m[*] Installing Antigravity CLI (first run)...\e[0m"
    curl -fsSL https://antigravity.google/cli/install.sh | bash
else
    # Auto-update disabled in background to prevent process conflicts
    true
fi

# Run the auto-patcher Python script
if [ -f /workspace/check_and_patch.py ]; then
    python3 /workspace/check_and_patch.py
fi

if command -v agy > /dev/null 2>&1; then
    agy "$@"
elif [ -f "$HOME/.local/bin/agy" ]; then
    "$HOME/.local/bin/agy" "$@"
else
    echo -e "\e[33m[!] agy not found.\e[0m"
fi

pwd > /workspace/.last_dir 2>/dev/null
echo ""
echo -e "\e[1;36m[Antigravity]\e[0m  CLI завершён - вы в Debian bash."
echo -e "\e[2m  Введите 'exit' для выхода из Debian.\e[0m"

cat > "$HOME/.bashrc" << 'BASHRC'
export PATH="$HOME/.local/bin:$PATH"
_agy_track_dir() { pwd > /workspace/.last_dir 2>/dev/null; }
PROMPT_COMMAND="_agy_track_dir${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
BASHRC

exec bash --rcfile "$HOME/.bashrc"
START_AGY
    chmod +x "$WORKSPACE_DIR/start-agy.sh"

    # Launch Debian: copy start-agy.sh from workspace then run it
    # shellcheck disable=SC2086
    proot-distro login debian         $EXTRA_BINDS         --no-kill-on-exit         -- /bin/bash -c 'cp /workspace/start-agy.sh /usr/local/bin/start-agy.sh && chmod +x /usr/local/bin/start-agy.sh && exec /usr/local/bin/start-agy.sh'
}
do_start() {
    if ! is_initialized; then
        do_init
    else
        do_start_inner
    fi
}

do_update() {
    show_banner
    log_info "Updating Antigravity CLI inside Debian..."
    proot-distro login debian -- /bin/bash -c \
        'export PATH="$HOME/.local/bin:$PATH"; curl -fsSL https://antigravity.google/cli/install.sh | bash'
    log_ok "Update done."
    read -r -p "  Press Enter to continue..."
}

do_shell() {
    local EXTRA_BINDS=""
    [ -d "$WORKSPACE_DIR" ] && EXTRA_BINDS="$EXTRA_BINDS --bind $WORKSPACE_DIR:/workspace"
    [ -d "/sdcard" ]        && EXTRA_BINDS="$EXTRA_BINDS --bind /sdcard:/sdcard"
    log_info "Entering Debian shell..."
    # shellcheck disable=SC2086
    proot-distro login debian $EXTRA_BINDS --no-kill-on-exit
}

run_patcher() {
    show_banner
    log_info "Checking Antigravity CLI Patcher..."
    
    PATCHER_DIR=""
    if [ -f "$WORKSPACE_DIR/open-antigravity-patcher/source/main.py" ]; then
        PATCHER_DIR="open-antigravity-patcher"
    else
        rm -rf "$WORKSPACE_DIR/open-antigravity-patcher"
    fi
    
    if [ -z "$PATCHER_DIR" ]; then
        log_info "Patcher folder not found in workspace."
        log_info "Cloning from GitHub (requires internet)..."
        if proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" -- /usr/bin/git clone https://github.com/AvenCores/open-antigravity-patcher.git /workspace/open-antigravity-patcher; then
            PATCHER_DIR="open-antigravity-patcher"
        fi
    fi
    
    if [ -n "$PATCHER_DIR" ]; then
        proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" -- /bin/bash -c "export TERM=xterm-256color; export PATCHER_DIR=$PATCHER_DIR; python3 /workspace/\$PATCHER_DIR/source/main.py; pkill -9 -x agy 2>/dev/null"
    else
        log_error "Patcher not available. Place open-antigravity-patcher folder in your workspace."
        sleep 3
    fi
}
do_configure_proxy() {
    mkdir -p "$WORKSPACE_DIR"
    [ -f "$PROXY_CONFIG" ]   && source "$PROXY_CONFIG"
    [ -f "$VLESS_SETTINGS" ] && source "$VLESS_SETTINGS"

    while true; do
        show_banner
        echo -e "  ${BOLD}Network & Proxy Settings${NC}"
        echo -e "  ========================"
        echo ""
        local ps="${RED}OFF${NC}"; [ "$USE_PROXY" = "true" ] && ps="${GREEN}ON${NC}"
        echo -e "  ${GREEN}1)${NC} Toggle proxy           [ $ps ]"
        echo -e "  ${GREEN}2)${NC} Set Proxy Type         [ ${CYAN}${PROXY_TYPE:-xray}${NC} ]"
        
        if [ "$PROXY_TYPE" = "xray" ] || [ "$PROXY_TYPE" = "hysteria2" ]; then
            echo -e "  ${GREEN}3)${NC} Import URL             [ VLESS or Hysteria 2 ]"
            local svr="${VLESS_ADDR:-none}"
            [ "${#svr}" -gt 25 ] && svr="${svr:0:22}..."
            echo -e "  ${GREEN}4)${NC} Manual Config Settings [ ${DIM}Server: $svr${NC} ]"
        else
            echo -e "  ${GREEN}3)${NC} Custom Proxy Address   [ ${CYAN}${PROXY_ADDR:-127.0.0.1}:${PROXY_PORT:-10808}${NC} ]"
        fi
        
        echo -e "  ${GREEN}0)${NC} Back to Main Menu"
        echo ""
        read -r -p "  > " cfg_opt
 
        case "$cfg_opt" in
            1)
                [ "$USE_PROXY" = "true" ] && USE_PROXY="false" || USE_PROXY="true"
                sed -i "s/USE_PROXY=.*/USE_PROXY=\"$USE_PROXY\"/" "$PROXY_CONFIG"
                ;;
            2)
                echo -e "\n  Select proxy type:"
                echo -e "    1) xray (VLESS/Reality)"
                echo -e "    2) hysteria2 (UDP High Speed)"
                echo -e "    3) socks5"
                echo -e "    4) http"
                read -r -p "  > " pt
                case "$pt" in
                    1) PT="xray";;
                    2) PT="hysteria2";;
                    3) PT="socks5";;
                    4) PT="http";;
                    *) PT="$PROXY_TYPE";;
                esac
                sed -i "s/PROXY_TYPE=.*/PROXY_TYPE=\"$PT\"/" "$PROXY_CONFIG"
                PROXY_TYPE="$PT"
                ;;
            3)
                if [ "$PROXY_TYPE" = "xray" ] || [ "$PROXY_TYPE" = "hysteria2" ]; then
                    show_banner
                    echo -e "  ${BOLD}Import Proxy URL${NC}"
                    echo -e "  Paste your vless:// or hysteria2:// link below:"
                    echo ""
                    read -r -p "  > " import_link
                    if [ -z "$import_link" ]; then continue; fi
                    
                    echo "$import_link" > "$WORKSPACE_DIR/vless_link_temp.txt"
                    if proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" --bind "/sdcard:/sdcard" -- /usr/bin/python3 /workspace/generate_proxy_config.py /workspace/vless_link_temp.txt "$XRAY_PORT" /workspace >/dev/null 2>&1; then
                        mv "$WORKSPACE_DIR/vless_link_temp.txt" "$WORKSPACE_DIR/vless_link.txt"
                        
                        if [ -f "$WORKSPACE_DIR/proxy_engine.txt" ]; then
                            local eng; eng=$(cat "$WORKSPACE_DIR/proxy_engine.txt")
                            if [ "$eng" = "xray" ] && [ -f "$WORKSPACE_DIR/xray_config.json" ]; then
                                VLESS_ADDR=$(grep -o '"address": "[^"]*' "$WORKSPACE_DIR/xray_config.json" | head -1 | cut -d'"' -f4)
                                VLESS_PORT=$(grep -o '"port": [0-9]*' "$WORKSPACE_DIR/xray_config.json" | head -1 | awk '{print $2}')
                            elif [ "$eng" = "hysteria" ] && [ -f "$WORKSPACE_DIR/hysteria_config.json" ]; then
                                local srv; srv=$(grep -o '"server": "[^"]*' "$WORKSPACE_DIR/hysteria_config.json" | head -1 | cut -d'"' -f4)
                                VLESS_ADDR="${srv%%:*}"
                                VLESS_PORT="${srv##*:}"
                            fi
                        fi
                        
                        cat << EOF > "$VLESS_SETTINGS"
VLESS_ADDR="$VLESS_ADDR"
VLESS_PORT="$VLESS_PORT"
VLESS_UUID=""
VLESS_FLOW=""
VLESS_SNI=""
VLESS_PUBKEY=""
VLESS_SHORTID=""
EOF
                        USE_PROXY="true"
                        sed -i 's/USE_PROXY=.*/USE_PROXY="true"/'   "$PROXY_CONFIG"
                        sed -i "s/PROXY_TYPE=.*/PROXY_TYPE=\"$PROXY_TYPE\"/" "$PROXY_CONFIG"
                        
                        log_ok "Proxy URL imported successfully. Proxy enabled."
                        sleep 1.5
                    else
                        rm -f "$WORKSPACE_DIR/vless_link_temp.txt"
                        log_error "Failed to parse URL. Make sure it's a valid vless:// or hysteria2:// link."
                        sleep 2
                    fi
                else
                    echo ""
                    read -r -p "  Address [$PROXY_ADDR]: " na; [ -n "$na" ] && PROXY_ADDR="$na"
                    read -r -p "  Port [$PROXY_PORT]: "   np; [ -n "$np" ] && PROXY_PORT="$np"
                    sed -i "s/PROXY_ADDR=.*/PROXY_ADDR=\"$PROXY_ADDR\"/" "$PROXY_CONFIG"
                    sed -i "s/PROXY_PORT=.*/PROXY_PORT=\"$PROXY_PORT\"/" "$PROXY_CONFIG"
                fi
                ;;
            4)
                if [ "$PROXY_TYPE" = "xray" ]; then
                    show_banner
                    echo -e "  ${BOLD}Manual Vless Configuration${NC}"
                    echo -e "  Leave blank to keep current value. Type 'none' to clear optional fields."
                    echo ""
                    read -r -p "  Server [$VLESS_ADDR]: "   t; [ -n "$t" ] && VLESS_ADDR="$t"
                    read -r -p "  Port [$VLESS_PORT]: "     t; [ -n "$t" ] && VLESS_PORT="$t"
                    read -r -p "  UUID [$VLESS_UUID]: "     t; [ -n "$t" ] && VLESS_UUID="$t"
                    read -r -p "  Flow [$VLESS_FLOW]: "     t; [ -n "$t" ] && { [ "$t" = "none" ] && VLESS_FLOW="" || VLESS_FLOW="$t"; }
                    read -r -p "  SNI [$VLESS_SNI]: "       t; [ -n "$t" ] && VLESS_SNI="$t"
                    read -r -p "  PubKey [$VLESS_PUBKEY]: " t; [ -n "$t" ] && VLESS_PUBKEY="$t"
                    read -r -p "  ShortID [$VLESS_SHORTID]: " t; [ -n "$t" ] && { [ "$t" = "none" ] && VLESS_SHORTID="" || VLESS_SHORTID="$t"; }
                    
                    if [ -n "$VLESS_PUBKEY" ]; then
                        VLESS_URL="vless://${VLESS_UUID}@${VLESS_ADDR}:${VLESS_PORT}?security=reality&flow=${VLESS_FLOW}&sni=${VLESS_SNI}&pbk=${VLESS_PUBKEY}&sid=${VLESS_SHORTID}"
                    else
                        VLESS_URL="vless://${VLESS_UUID}@${VLESS_ADDR}:${VLESS_PORT}?security=tls&flow=${VLESS_FLOW}&sni=${VLESS_SNI}"
                    fi
                    echo "$VLESS_URL" > "$WORKSPACE_DIR/vless_link.txt"

                    cat << EOF > "$VLESS_SETTINGS"
VLESS_ADDR="$VLESS_ADDR"
VLESS_PORT="$VLESS_PORT"
VLESS_UUID="$VLESS_UUID"
VLESS_FLOW="$VLESS_FLOW"
VLESS_SNI="$VLESS_SNI"
VLESS_PUBKEY="$VLESS_PUBKEY"
VLESS_SHORTID="$VLESS_SHORTID"
EOF
                    generate_xray_config
                    log_ok "Settings saved."
                    sleep 1
                elif [ "$PROXY_TYPE" = "hysteria2" ]; then
                    show_banner
                    echo -e "  ${BOLD}Manual Hysteria 2 Configuration${NC}"
                    echo -e "  Leave blank to keep current value. Type 'none' to clear optional fields."
                    echo ""
                    
                    read -r -p "  Server [$VLESS_ADDR]: "   t; [ -n "$t" ] && VLESS_ADDR="$t"
                    read -r -p "  Port [$VLESS_PORT]: "     t; [ -n "$t" ] && VLESS_PORT="$t"
                    read -r -p "  Auth/Password [$VLESS_UUID]: " t; [ -n "$t" ] && VLESS_UUID="$t"
                    read -r -p "  SNI [$VLESS_SNI]: "       t; [ -n "$t" ] && VLESS_SNI="$t"
                    read -r -p "  Obfs Type (none/salamander) [$VLESS_PUBKEY]: " t; [ -n "$t" ] && { [ "$t" = "none" ] && VLESS_PUBKEY="" || VLESS_PUBKEY="$t"; }
                    read -r -p "  Obfs Password [$VLESS_SHORTID]: " t; [ -n "$t" ] && { [ "$t" = "none" ] && VLESS_SHORTID="" || VLESS_SHORTID="$t"; }
                    
                    if [ -n "$VLESS_PUBKEY" ]; then
                        HY_URL="hysteria2://${VLESS_UUID}@${VLESS_ADDR}:${VLESS_PORT}?sni=${VLESS_SNI}&obfs=${VLESS_PUBKEY}&obfs-password=${VLESS_SHORTID}"
                    else
                        HY_URL="hysteria2://${VLESS_UUID}@${VLESS_ADDR}:${VLESS_PORT}?sni=${VLESS_SNI}"
                    fi
                    echo "$HY_URL" > "$WORKSPACE_DIR/vless_link.txt"
                    
                    cat << EOF > "$VLESS_SETTINGS"
VLESS_ADDR="$VLESS_ADDR"
VLESS_PORT="$VLESS_PORT"
VLESS_UUID="$VLESS_UUID"
VLESS_FLOW=""
VLESS_SNI="$VLESS_SNI"
VLESS_PUBKEY="$VLESS_PUBKEY"
VLESS_SHORTID="$VLESS_SHORTID"
EOF
                    generate_xray_config
                    log_ok "Settings saved."
                    sleep 1
                fi
                ;;
            0|q|exit)
                return 0
                ;;
            *)
                ;;
        esac
    done
}

do_reset() {
    show_banner
    log_warn "This will DELETE the Debian container and all settings!"
    read -r -p "  Type 'yes' to confirm: " c
    if [ "$c" = "yes" ]; then
        proot-distro remove debian 2>/dev/null || true
        rm -rf "$WORKSPACE_DIR"
        log_ok "Environment wiped. Restart the app to reinstall."
    fi
}

# -----------------------------------------------------------------------------
# Subcommand routing
case "${1:-}" in
    init|setup) do_init;            exit 0 ;;
    start)      do_start;           exit 0 ;;
    update)     do_update;          exit 0 ;;
    config)     do_configure_proxy; exit 0 ;;
    shell)      do_shell;           exit 0 ;;
    reset)      do_reset;           exit 0 ;;
esac

# -----------------------------------------------------------------------------
# One-Click Bootloader
show_banner

if is_initialized; then
    echo -e "  ${GREEN}${BOLD}Launching in 3 seconds...${NC}"
    echo -e "  ${DIM}Press any key to open the menu.${NC}"
    echo ""
else
    echo -e "  ${YELLOW}${BOLD}First run -- setup will begin automatically.${NC}"
    echo -e "  ${DIM}Press any key to open the menu instead.${NC}"
    echo ""
fi

if read -t 3 -n 1 -r; then
    while true; do
        show_banner
        local_proxy_status="OFF"
        [ -f "$PROXY_CONFIG" ] && source "$PROXY_CONFIG"
        [ "$USE_PROXY" = "true" ] && local_proxy_status="ON (${PROXY_TYPE})"
        last_dir="(none yet)"
        [ -f "$LAST_DIR_FILE" ] && last_dir=$(cat "$LAST_DIR_FILE")

        echo -e "  ${DIM}Workspace :${NC} ${CYAN}$WORKSPACE_DIR${NC}"
        echo -e "  ${DIM}Proxy     :${NC} ${CYAN}$local_proxy_status${NC}"
        echo -e "  ${DIM}Last dir  :${NC} ${BLUE}$last_dir${NC}"
        echo ""
        echo -e "  ${GREEN}1)${NC} Launch Antigravity CLI"
        echo -e "  ${GREEN}2)${NC} Update Antigravity CLI"
        echo -e "  ${GREEN}3)${NC} Network & Proxy settings"
        echo -e "  ${GREEN}4)${NC} Run Antigravity Patcher"
        echo -e "  ${GREEN}5)${NC} Open Debian shell"
        echo -e "  ${GREEN}6)${NC} Reset sandbox"
        echo -e "  ${GREEN}7)${NC} Exit"
        echo ""
        read -r -p "  > " opt
        case "$opt" in
            1) do_start ;;
            2) do_update ;;
            3) do_configure_proxy ;;
            4) run_patcher ;;
            5) do_shell ;;
            6) do_reset ;;
            7) exit 0 ;;
            *) log_warn "Invalid option."; sleep 1 ;;
        esac
    done
else
    do_start
fi
