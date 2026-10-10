#!/bin/bash
# ==============================================================================
# Google Antigravity CLI Mobile -- Dual-Environment Manager & Debian Launcher
# ==============================================================================

[ -z "$PREFIX" ] && PREFIX="/data/data/com.agycli/files/usr"

WORKSPACE_DIR="/sdcard/AntigravityWorkspace"
PROXY_CONFIG="$WORKSPACE_DIR/proxy_config.sh"
VLESS_SETTINGS="$WORKSPACE_DIR/vless_settings.sh"
LAST_DIR_FILE="$WORKSPACE_DIR/.last_dir"
PROOT_BIN="$PREFIX/bin/proot"

# Ensure UTF-8 — C.UTF-8 всегда доступен в Termux, en_US может отсутствовать
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# Pure Google Blue Palette
ESC=$'\e'
C_RESET="${ESC}[0m"
C_BOLD="${ESC}[1m"
C_DIM="${ESC}[2m"

G1="${ESC}[38;2;26;115;232m"
G2="${ESC}[38;2;66;133;244m"
G3="${ESC}[38;2;102;157;246m"
G4="${ESC}[38;2;138;180;248m"
G5="${ESC}[38;2;168;199;250m"

G_WHITE="${ESC}[38;2;255;255;255m"
G_GRAY="${ESC}[38;2;154;160;166m"
G_GREEN="${ESC}[38;2;52;168;83m"
G_WARN="${ESC}[38;2;251;188;5m"
G_RED="${ESC}[38;2;234;67;53m"
G_MAGENTA="${ESC}[38;2;255;0;255m"

BG_SURFACE="${ESC}[48;2;24;26;31m"
BG_PODLOZHKA="${ESC}[48;2;16;18;22m"
BG_SELECT="${ESC}[48;2;26;115;232m"

# State
USE_PROXY="false"
PROXY_TYPE="xray"
PROXY_ADDR="127.0.0.1"
PROXY_PORT="10808"
XRAY_PORT="10808"
# Лок обновлений Antigravity: true (по умолч.) — глушим auto-updater и лочим
# бинарь, патч/регион-байпас держится. false — agy волен самообновляться.
UPDATE_LOCK="true"
StorageMode="FULL SYSTEM"
LastDirWork="$WORKSPACE_DIR"
LastDirFull="/storage/emulated/0"
IsFirstRun="false"

[ -f "$PROXY_CONFIG" ] && source "$PROXY_CONFIG"

IN_APP_MODE="false"
if [ "$1" == "--in-app" ]; then
    IN_APP_MODE="true"
fi

# ── UI safety helpers ────────────────────────────────────────────────────────
# drain_stdin: выбросить залипшие нажатия из буфера, чтобы следующий промпт
# (read -rsn1 / read -t) не проскакивал на старых клавишах, набитых во время
# анимаций спиннеров (там ввод не читается и копится).
# Только для TTY: пайпнутый stdin (автоматизация) не трогаем.
drain_stdin() { [ -t 0 ] || return 0; local _d; while read -t 0 -rsn1 _d 2>/dev/null; do :; done; }

# cell_width: видимая ширина строки в клетках терминала.
# ${#var} считает символы: эмодзи W-класса (📂📁🌐🔄🛠🗙🗄📦🔒 — 1 символ, 2 клетки)
# дают +1, а U+FE0F (VS16, напр. в 🛠️) — 0 клеток при 1 символе, даёт −1.
# Остальное (─ │ █ ▒ ● ○ ▶ ◀ • ✓ ✗ ✔ ↵ ↩) — 1 символ = 1 клетка, поправок нет.
cell_width() {
    local s; s=$(strip_ansi "$1")
    local w=${#s} tmp c e
    for e in "📂" "📁" "🌐" "🔄" "🛠" "🗙" "🗄" "📦" "🔒"; do
        tmp=${s//"$e"/}; c=$(( (${#s} - ${#tmp}) / ${#e} ))
        w=$((w + c))
    done
    tmp=${s//$'\uFE0F'/}; w=$((w - (${#s} - ${#tmp})))
    echo "$w"
}

# Гарантированно выйти из alternate screen и вернуть курсор при ЛЮБОМ выходе,
# включая Ctrl+C в меню/анимациях (иначе терминал остаётся пустым со скрытым
# курсором). Команды идемпотентны — безопасны и при штатном завершении.
# INT/TERM завершают скрипт кодом 130: иначе после trapped-прерывания во время
# read цикл меню продолжил бы работу и трактовал бы Ctrl+C как Enter.
trap 'printf "\e[?1049l\e[?25h"' EXIT
trap 'printf "\e[?1049l\e[?25h"; exit 130' INT TERM

get_console_width() {
    local w
    w=$(stty size 2>/dev/null | awk '{print $2}')
    if [ -z "$w" ] || [ "$w" = "0" ] || [ "$w" -lt 5 ]; then
        w=$(tput cols 2>/dev/null)
    fi
    if [ -z "$w" ] || [ "$w" = "0" ] || [ "$w" -lt 5 ]; then
        w=${COLUMNS:-65}
    fi
    [ -z "$w" ] && w=65
    if [ "$w" -lt 35 ]; then echo 35
    elif [ "$w" -gt 120 ]; then echo 120
    else echo "$w"; fi
}

strip_ansi() {
    # printf, а не echo -e: иначе \-последовательности в тексте (напр. имена
    # папок) интерпретируются и ломают подсчёт ширины/вёрстку строк.
    printf '%s' "$1" | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

print_spaces() {
    local n=$1
    if [ "$n" -gt 0 ]; then
        printf "%*s" "$n" ""
    fi
}

print_dashes() {
    local n=$1
    if [ "$n" -gt 0 ]; then
        local str=""
        for ((i=0; i<n; i++)); do str="${str}─"; done
        echo -n "$str"
    fi
}

print_blocks() {
    local n=$1
    if [ "$n" -gt 0 ]; then
        local str=""
        for ((i=0; i<n; i++)); do str="${str}█"; done
        echo -n "$str"
    fi
}

print_shades() {
    local n=$1
    if [ "$n" -gt 0 ]; then
        local str=""
        for ((i=0; i<n; i++)); do str="${str}▒"; done
        echo -n "$str"
    fi
}

show_header() {
    clear
    echo ""
    # Единый кламп [35..120] как в get_console_width: иначе на терминалах шире
    # 120 шапка расползается (панель/меню клампятся), а уже 33 — рваная рамка.
    local rawWidth=$(get_console_width)
    local isMobile="false"
    # Тот же порог, что у панели/меню (innerWidth<68 ⇔ W<72): на 65–71 колонках
    # раньше рисовалось десктопное лого с мобильной панелью.
    if [ "$rawWidth" -lt 72 ]; then
        isMobile="true"
    fi
    local innerWidth=$((rawWidth - 4))
    local topBorder="╭$(print_dashes $innerWidth)╮"
    echo -e " ${G2}${topBorder}${C_RESET}"
    
    local emptyLine
    emptyLine=$(print_spaces $innerWidth)
    echo -e " ${G2}│${BG_SURFACE}${emptyLine}${C_RESET}${G2}│${C_RESET}"

    local baseLogoWidth
    if [ "$isMobile" = "true" ]; then
        T2="  █████  ██████ ██    ██ "
        T3=" ██   ██ ██      ██  ██  "
        T4=" ███████ ██   ███ ████   "
        T5=" ██   ██ ██    ██  ██    "
        T6=" ██   ██  ██████   ██    "
        baseLogoWidth=25
    else
        T2="  █████    ██████  ██    ██   ██████  ██      ███  "
        T3=" ██   ██  ██        ██  ██   ██       ██      ███  "
        T4=" ███████  ██   ███   ████    ██       ██      ███  "
        T5=" ██   ██  ██    ██    ██     ██       ██      ███  "
        T6=" ██   ██   ██████     ██      ██████  ███████ ███  "
        baseLogoWidth=51
    fi

    local innerBoxBase=$((baseLogoWidth + 4))
    local pad=""
    if [ $((innerWidth % 2)) -ne $((innerBoxBase % 2)) ]; then pad=" "; fi
    
    local padLen=${#pad}
    local lTop="╭$(print_dashes $((baseLogoWidth + padLen)))╮"
    local lBot="╰$(print_dashes $((baseLogoWidth + padLen)))╯"

    local L1="${G1}${C_BOLD} ${lTop} "
    local L2="${G1}${C_BOLD} │${T2}${pad}│ "
    local L3="${G2}${C_BOLD} │${T3}${pad}│ "
    local L4="${G3}${C_BOLD} │${T4}${pad}│ "
    local L5="${G4}${C_BOLD} │${T5}${pad}│ "
    local L6="${G5}${C_BOLD} │${T6}${pad}│ "
    local L7="${G1}${C_BOLD} ${lBot} "
    
    local lines=("$L1" "$L2" "$L3" "$L4" "$L5" "$L6" "$L7")
    local logoWidth=$((innerBoxBase + padLen))
    
    local left=$(( (innerWidth - logoWidth) / 2 ))
    local right=$(( innerWidth - logoWidth - left ))

    local lPad=$(print_spaces $left)
    local rPad=$(print_spaces $right)

    for line in "${lines[@]}"; do
        echo -e " ${G2}│${BG_SURFACE}${lPad}${BG_PODLOZHKA}${line}${BG_SURFACE}${rPad}${C_RESET}${G2}│${C_RESET}"
    done

    echo -e " ${G2}│${BG_SURFACE}${emptyLine}${C_RESET}${G2}│${C_RESET}"
    
    local baseSubText
    if [ "$isMobile" = "true" ]; then
        if [ "$IN_APP_MODE" = "true" ]; then
            baseSubText=" Settings Overlay  •  Active Session "
        else
            baseSubText=" Antigravity CLI  •  Mobile "
        fi
    else
        if [ "$IN_APP_MODE" = "true" ]; then
            baseSubText=" Antigravity Settings Overlay  •  Active Debian Session "
        else
            baseSubText=" Google Antigravity CLI  •  Debian Sandbox  •  Mobile Edition "
        fi
    fi
    
    local baseLen=${#baseSubText}
    local subPad=""
    if [ $((innerWidth % 2)) -ne $((baseLen % 2)) ]; then subPad=" "; fi
    
    local subLen=$((baseLen + ${#subPad}))
    local subLeft=$(( (innerWidth - subLen) / 2 ))
    local subRight=$(( innerWidth - subLen - subLeft ))
    
    local subLpad=$(print_spaces $subLeft)
    local subRpad=$(print_spaces $subRight)

    local subFormat
    if [ "$isMobile" = "true" ]; then
        if [ "$IN_APP_MODE" = "true" ]; then
            subFormat="${G_WARN}${C_BOLD} Settings Overlay  ${G_GRAY}•${G_WHITE}  Active Session ${subPad}"
        else
            subFormat="${G_WHITE}${C_BOLD} Antigravity CLI  ${G_GRAY}•${G_WHITE}  Mobile ${subPad}"
        fi
    else
        if [ "$IN_APP_MODE" = "true" ]; then
            subFormat="${G_WARN}${C_BOLD} Antigravity Settings Overlay  ${G_GRAY}•${G_WHITE}  Active Debian Session ${subPad}"
        else
            subFormat="${G_WHITE}${C_BOLD} Google Antigravity CLI  ${G_GRAY}•${G_WHITE}  Debian Sandbox  ${G_GRAY}•${G_WHITE}  Mobile Edition ${subPad}"
        fi
    fi
    
    echo -e " ${G2}│${BG_SURFACE}${subLpad}${subFormat}${BG_SURFACE}${subRpad}${C_RESET}${G2}│${C_RESET}"
    echo -e " ${G2}│${BG_SURFACE}${emptyLine}${C_RESET}${G2}│${C_RESET}"
    
    local bottomBorder="╰$(print_dashes $innerWidth)╯"
    echo -e " ${G2}${bottomBorder}${C_RESET}"
}

show_status_panel() {
    local W=$(get_console_width)
    local innerWidth=$((W - 4))
    local isMobile="false"
    if [ "$innerWidth" -lt 68 ]; then isMobile="true"; fi
    
    local title="${G2}${C_BOLD}[ SYSTEM STATUS ]${C_RESET}"
    if [ "$IN_APP_MODE" = "true" ]; then title="${G_WARN}${C_BOLD}[ LIVE OVERLAY ]${C_RESET}"; fi
    
    local tRaw=$(strip_ansi "$title")
    local totalDashes=$((innerWidth + 2 - ${#tRaw} - 2))
    [ "$totalDashes" -lt 2 ] && totalDashes=2
    local dashLeftCount=$((totalDashes / 2))
    local dashRightCount=$((totalDashes - dashLeftCount))
    
    echo ""
    echo -e " ${G_GRAY}$(print_dashes $dashLeftCount) ${title} ${G_GRAY}$(print_dashes $dashRightCount)${C_RESET}"
    echo ""

    local activeDir="$LastDirWork"
    if [ -f "$LAST_DIR_FILE" ]; then activeDir=$(cat "$LAST_DIR_FILE"); fi
    # Normalize /storage/emulated/0 → /sdcard for consistent matching
    activeDir="${activeDir//\/storage\/emulated\/0\//\/sdcard\/}"
    if [[ "$activeDir" == "/sdcard"* && "$activeDir" != "$WORKSPACE_DIR"* ]]; then
        StorageMode="FULL SYSTEM"
    else
        StorageMode="WORKSPACE ONLY"
    fi
    # Translate to Debian mount path for display
    local displayDir="$activeDir"
    if [[ "$activeDir" == "$WORKSPACE_DIR"* ]]; then
        displayDir="/workspace${activeDir#$WORKSPACE_DIR}"
    elif [[ "$activeDir" == "/sdcard"* ]]; then
        displayDir="/phone${activeDir#/sdcard}"
    fi
    
    if [ "$isMobile" = "true" ]; then
        local d="$activeDir"
        if [ ${#d} -gt 18 ]; then d="...${d: -15}"; fi
        
        local proxyBadge="${G_RED}○ PROXY OFF${C_RESET}"
        if [ "$USE_PROXY" = "true" ]; then proxyBadge="${G_GREEN}● PROXY ON ${G_GRAY}(${PROXY_PORT})${C_RESET}"; fi
        
        local storageBadge="${G2}● WORKSPACE${C_RESET}"
        if [ "$StorageMode" = "FULL SYSTEM" ]; then storageBadge="${G_WARN}● FULL SYS${C_RESET}"; fi
        
        local pbRaw=$(strip_ansi "$proxyBadge")
        local sbRaw=$(strip_ansi "$storageBadge")
        
        local s1=" STATE: ● Agy Ready"
        if [ "$IN_APP_MODE" = "true" ]; then s1=" STATE: ● Agy Running (Tmux)"; fi
        local s2=" NET:   ${pbRaw}"
        local s3=" MODE:  ${sbRaw}"
        local s4=" DIR:   [ $d ]"
        
        local maxLen=${#s1}
        [ ${#s2} -gt $maxLen ] && maxLen=${#s2}
        [ ${#s3} -gt $maxLen ] && maxLen=${#s3}
        [ ${#s4} -gt $maxLen ] && maxLen=${#s4}
        
        local leftPadCount=$((1 + (innerWidth + 2 - maxLen) / 2))
        [ "$leftPadCount" -lt 1 ] && leftPadCount=1
        local lPad=$(print_spaces $leftPadCount)

        local stateStr="${G_GREEN}● Agy Ready${C_RESET}"
        if [ "$IN_APP_MODE" = "true" ]; then stateStr="${G_GREEN}● Agy Running (Tmux)${C_RESET}"; fi

        echo -e "${lPad}${G1}${C_BOLD} STATE:${C_RESET}  ${stateStr}"
        echo -e "${lPad}${G1}${C_BOLD} NET:${C_RESET}    ${proxyBadge}"
        echo -e "${lPad}${G1}${C_BOLD} MODE:${C_RESET}   ${storageBadge}"
        echo -e "${lPad}${G1}${C_BOLD} DIR:${C_RESET}    ${G_WHITE}[ ${d} ]${C_RESET}"
    else
        local proxyBadge="${G_RED}○ PROXY OFF${C_RESET}"
        if [ "$USE_PROXY" = "true" ]; then proxyBadge="${G_GREEN}● PROXY ACTIVE  ${G_GRAY}( ${PROXY_TYPE}  |  PORT ${PROXY_PORT} )${C_RESET}"; fi
        
        local storageBadge="${G2}● WORKSPACE ONLY  ${G_GRAY}( /sdcard/AntigravityWorkspace )${C_RESET}"
        if [ "$StorageMode" = "FULL SYSTEM" ]; then storageBadge="${G_WARN}● FULL ACCESS  ${G_GRAY}( /storage/emulated/0 )${C_RESET}"; fi
        
        local pbRaw=$(strip_ansi "$proxyBadge")
        local sbRaw=$(strip_ansi "$storageBadge")

        local s1=" APP STATE   :  ● AGY Ready to Launch"
        if [ "$IN_APP_MODE" = "true" ]; then s1=" APP STATE   :  ● AGY Running in Background"; fi
        local s2=" NETWORK     :  ${pbRaw}"
        local s3=" STORAGE     :  ${sbRaw}"
        local s4=" WORKING DIR :  [ $displayDir ]"
        
        local maxLen=${#s1}
        [ ${#s2} -gt $maxLen ] && maxLen=${#s2}
        [ ${#s3} -gt $maxLen ] && maxLen=${#s3}
        [ ${#s4} -gt $maxLen ] && maxLen=${#s4}
        
        local leftPadCount=$((1 + (innerWidth + 2 - maxLen) / 2))
        [ "$leftPadCount" -lt 1 ] && leftPadCount=1
        local lPad=$(print_spaces $leftPadCount)

        local stateStr="${G_GREEN}● AGY Ready to Launch${C_RESET}"
        if [ "$IN_APP_MODE" = "true" ]; then stateStr="${G_GREEN}● AGY Running in Background${C_RESET}"; fi

        echo -e "${lPad}${G1}${C_BOLD} APP STATE   :${C_RESET}  ${stateStr}"
        echo -e "${lPad}${G1}${C_BOLD} NETWORK     :${C_RESET}  ${proxyBadge}"
        echo -e "${lPad}${G1}${C_BOLD} STORAGE     :${C_RESET}  ${storageBadge}"
        echo -e "${lPad}${G1}${C_BOLD} WORKING DIR :${C_RESET}  ${G_WHITE}[ ${displayDir} ]${C_RESET}"
    fi
    echo ""
}

bootloader_timer() {
    if [ "$IN_APP_MODE" = "true" ]; then return 0; fi

    show_header
    show_status_panel
    
    local W=$(get_console_width)
    local innerWidth=$((W - 4))
    
    local t="\e[38;5;51m\e[1m[ SYSTEM BOOT SEQUENCE ]\e[0m"
    local tRaw="[ SYSTEM BOOT SEQUENCE ]"
    
    local totalDashes=$((innerWidth + 2 - ${#tRaw} - 2))
    [ "$totalDashes" -lt 2 ] && totalDashes=2
    local dashLeftCount=$((totalDashes / 2))
    local dashRightCount=$((totalDashes - dashLeftCount))
    
    echo -e " \e[38;5;238m$(print_dashes $dashLeftCount) ${t} \e[38;5;238m$(print_dashes $dashRightCount)${C_RESET}"
    echo ""
    
    local msg="\e[97m\e[1mPress any key to configure settings...\e[0m"
    if [ "$IsFirstRun" = "true" ]; then
        msg="\e[38;5;214m\e[1mFirst run detected. Press any key to configure...\e[0m"
    fi
    
    local mRaw=$(strip_ansi "$msg")
    local mPad=$((1 + (innerWidth + 2 - ${#mRaw}) / 2))
    [ "$mPad" -lt 1 ] && mPad=1
    echo -e "$(print_spaces $mPad)$msg"
    echo ""
    
    printf '\e[?25l'
    drain_stdin # сбросить залипший ввод, иначе таймер мгновенно скипнется
    
    local total_ms=30
    # Адаптивная ширина бара — гарантированно влезает в innerWidth без переноса
    local barWidth=$((innerWidth - 24))
    if [ "$barWidth" -gt 30 ]; then barWidth=30; fi
    if [ "$barWidth" -lt 10 ]; then barWidth=10; fi
    
    for ((ms=total_ms; ms>0; ms--)); do
        local filled=$(( (total_ms - ms) * barWidth / total_ms ))
        local empty=$((barWidth - filled))
        local filledStr=$(print_blocks $filled)
        local emptyStr=$(print_shades $empty)
        local bar="\e[38;5;51m${filledStr}\e[38;5;238m${emptyStr}\e[0m"
        
        local sec=$((ms / 10))
        local dec=$((ms % 10))
        
        local timerStr="\e[38;5;51mBooting in ${sec}.${dec}s  [${bar}] \e[0m"
        if [ "$IsFirstRun" = "true" ]; then
            timerStr="\e[38;5;214mSetup in ${sec}.${dec}s  [${bar}] \e[0m"
        fi
        
        local tsRaw=$(strip_ansi "$timerStr")
        local tsPad=$((1 + (innerWidth + 2 - ${#tsRaw}) / 2))
        [ "$tsPad" -lt 1 ] && tsPad=1
        
        # \r + 2K — строго одна строка, без переноса. %b (не %s): timerStr
        # содержит литеральные \e[...]-последовательности, их надо интерпретировать.
        printf '\r\033[2K%s%b' "$(print_spaces $tsPad)" "$timerStr"
        
        if read -t 0.1 -rsn1 key; then
            printf '\033[?25h\n'
            return 0
        fi
    done
    
    printf '\033[?25h\n'
    return 1
}

invoke_menu() {
    local title="$1"; shift
    local options=("$@")
    local selectedIndex=0
    local optCount=${#options[@]}

    printf '\e[?1049h'   # alternate screen — keyboard resize won't shift rows
    printf '\e[?25l'     # hide cursor

    # ── Pre-compute layout ─────────────────────────────────────────────────────
    local W=$(get_console_width)
    local innerWidth=$((W - 4))
    local isMobile="false"
    [ "$innerWidth" -lt 68 ] && isMobile="true"

    local maxOptLen=0
    # Ширина каждого пункта в КЛЕТКАХ (cell_width): ${#} врёт на эмодзи
    # (📂/🛠️ = 2 клетки), иначе рамка выделения получается рваной.
    local -a optW=()
    for opt in "${options[@]}"; do
        local w; w=$(cell_width "$opt"); optW+=("$w")
        [ "$w" -gt "$maxOptLen" ] && maxOptLen=$w
    done
    local lpc=$((1 + (innerWidth + 2 - maxOptLen - 7) / 2))
    [ "$lpc" -lt 1 ] && lpc=1
    local lPad=$(print_spaces $lpc)

    local tFull="${G2}${C_BOLD}[ ${title} ]${C_RESET}"
    local td=$((innerWidth + 2 - $(cell_width "$tFull") - 2)); [ "$td" -lt 2 ] && td=2
    local dashL=$((td / 2)); local dashR=$((td - dashL))

    local controls
    if [ "$isMobile" = "true" ]; then
        [ "$IN_APP_MODE" = "true" ] \
            && controls="${G2}[↑↓] Nav${C_RESET} ${G_GRAY}•${C_RESET} ${G_GREEN}[ENT] Ok${C_RESET} ${G_GRAY}•${C_RESET} ${G_RED}[ESC] Close${C_RESET}" \
            || controls="${G2}[↑↓] Nav${C_RESET} ${G_GRAY}•${C_RESET} ${G_GREEN}[ENT] Ok${C_RESET} ${G_GRAY}•${C_RESET} ${G_RED}[ESC] Back${C_RESET}"
    else
        [ "$IN_APP_MODE" = "true" ] \
            && controls="${G2}[ ↑ / ↓ ] Navigate${C_RESET}   ${G_GRAY}•${C_RESET}   ${G_GREEN}[ ENTER ] Select${C_RESET}   ${G_GRAY}•${C_RESET}   ${G_RED}[ ESC ] Close Overlay${C_RESET}" \
            || controls="${G2}[ ↑ / ↓ ] Navigate${C_RESET}   ${G_GRAY}•${C_RESET}   ${G_GREEN}[ ENTER ] Select${C_RESET}   ${G_GRAY}•${C_RESET}   ${G_RED}[ ESC ] Back/Exit${C_RESET}"
    fi
    local cpl=$((1 + (innerWidth + 2 - $(cell_width "$controls")) / 2)); [ "$cpl" -lt 1 ] && cpl=1

    # ── Draw EVERYTHING (static parts + items + footer) ───────────────────────
    show_header
    show_status_panel
    # printf вместо echo -e: \-последовательности в заголовке (пути из
    # файлбраузера) не должны интерпретироваться и рвать вёрстку.
    printf '%s\n' " ${G_GRAY}$(print_dashes $dashL) ${tFull} ${G_GRAY}$(print_dashes $dashR)${C_RESET}"
    echo ""

    for ((i=0; i<optCount; i++)); do
        local optText="${options[$i]}"
        local padRight=$(print_spaces $((maxOptLen - optW[i])))
        if [ "$i" -eq "$selectedIndex" ]; then
            echo -e "${lPad}${G1}${C_BOLD}▶  ${BG_SELECT}${G_WHITE}${C_BOLD} ${optText}${padRight} ${C_RESET}${G1}${C_BOLD} ◀${C_RESET}"
        else
            # Префикс ровно 4 клетки ("  │ ") — текст начинается там же, где у
            # выбранного пункта после "▶  "+пробела подсветки (было 5, «лесенка»).
            echo -e "${lPad}${G_GRAY}  │ ${C_RESET}${optText}"
        fi
    done
    # Footer (3 lines: empty + dashes + controls)
    echo ""
    echo -e " ${G_GRAY}$(print_dashes $((innerWidth + 2)))${C_RESET}"
    printf '%s\n' "$(print_spaces $cpl)${controls}"
    # After printf '%s\n', cursor is on the line AFTER controls = row _fr

    # ── Query cursor position AFTER drawing — calculate item0_row BACKWARDS ────
    # Layout from bottom: controls(row C) → dashes(C-1) → empty(C-2) → item[n-1](C-3) → ... → item[0](C-2-n)
    # _fr = C+1 (one past controls due to the trailing \n)
    # item0_row = _fr - optCount - 3
    local _cpr=''
    printf '\e[6n'
    IFS='' read -rs -d 'R' -t 2 _cpr 2>/dev/null || true
    _cpr="${_cpr##*\[}"
    local _fr=0
    [[ "$_cpr" =~ ^([0-9]+)\; ]] && _fr="${BASH_REMATCH[1]}"
    if [ "$_fr" -lt $((optCount + 5)) ]; then
        # Fallback: put items near terminal bottom minus a safe margin
        _fr=$(( $(stty size 2>/dev/null | awk '{print $1}' || echo 40) ))
    fi
    local item0_row=$(( _fr - optCount - 3 ))
    [ "$item0_row" -lt 1 ] && item0_row=1
    printf '\e[%d;1H' "$_fr"   # park cursor at bottom

    # ── Differential update: ONLY 2 lines change per keypress ─────────────────
    _upd() {
        local idx=$1 sel=$2
        local optText="${options[$idx]}"
        local padRight=$(print_spaces $((maxOptLen - optW[idx])))
        printf '\e[%d;1H' "$((item0_row + idx))"
        printf '\e[2K'
        if [ "$sel" = "1" ]; then
            printf '%s' "${lPad}${G1}${C_BOLD}▶  ${BG_SELECT}${G_WHITE}${C_BOLD} ${optText}${padRight} ${C_RESET}${G1}${C_BOLD} ◀${C_RESET}"
        else
            printf '%s' "${lPad}${G_GRAY}  │ ${C_RESET}${optText}"
        fi
        printf '\e[%d;1H' "$_fr"
    }

    # ── Input loop ────────────────────────────────────────────────────────────
    # Сбросить залипший ввод (набитый во время прошлых анимаций), иначе первое
    # нажатие «съедается» ещё до того, как пользователь что-то нажал.
    drain_stdin
    while true; do
        read -rsn1 key
        if [[ $key == $'\e' ]]; then
            read -rsn2 -t 0.1 key2
            if [[ $key2 == '[A' ]]; then
                local prev=$selectedIndex
                selectedIndex=$(( (selectedIndex - 1 + optCount) % optCount ))
                _upd "$prev" 0; _upd "$selectedIndex" 1
            elif [[ $key2 == '[B' ]]; then
                local prev=$selectedIndex
                selectedIndex=$(( (selectedIndex + 1) % optCount ))
                _upd "$prev" 0; _upd "$selectedIndex" 1
            elif [[ -z $key2 ]]; then
                printf '\e[?1049l'; printf '\e[?25h'; return 255
            fi
        elif [[ $key == "" ]]; then
            printf '\e[?1049l'; printf '\e[?25h'; return $selectedIndex
        elif [[ "$key" =~ ^[0-9]$ ]]; then
            for ((idx=0; idx<optCount; idx++)); do
                local cleanText; cleanText=$(strip_ansi "${options[$idx]}")
                if [[ "$cleanText" == "$key."* || "$cleanText" == "$key "* ]]; then
                    printf '\e[?1049l'; printf '\e[?25h'; return "$idx"
                fi
            done
        elif [[ "$key" == "y" || "$key" == "Y" ]]; then
            if [[ "$title" == *"RESTART"* ]]; then
                printf '\e[?1049l'; printf '\e[?25h'; return 0
            fi
        elif [[ "$key" == "n" || "$key" == "N" ]]; then
            if [[ "$title" == *"RESTART"* ]]; then
                printf '\e[?1049l'; printf '\e[?25h'; return 1
            fi
        fi
    done
}

SELECTED_PATH=""
invoke_filebrowser() {
    local start_path="$1"
    local mode_name="$2"
    local current_path="$start_path"
    
    while true; do
        local options=("${G_GREEN}${C_BOLD}[ ✔ ] SELECT DIRECTORY${C_RESET}" "${G_WARN}[ ↵ ] .. (Go Up)${C_RESET}")
        local dirs=()
        
        # -A: включая dot-папки (кроме . и ..); @: симлинки — берём только те,
        # что ведут в каталоги (у symlinked dir ls ставит @, а не /).
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            if [[ "$d" == *@ ]]; then
                d="${d%@}"
                [ -d "$current_path/$d" ] || continue
            else
                d="${d%/}"
            fi
            [[ "$d" == "." || "$d" == ".." ]] && continue
            dirs+=("$d")
        done < <(ls -1AF "$current_path" 2>/dev/null | grep -E '/$|@$')
        
        for d in "${dirs[@]}"; do
            options+=("${G_WHITE}[ 📁 ] $d${C_RESET}")
        done
        
        local title_path="$current_path"
        if [ ${#title_path} -gt 30 ]; then title_path="...${title_path: -27}"; fi
        local title="📂 $title_path "
        [ -n "$mode_name" ] && title="$mode_name | $title"
        
        invoke_menu "$title" "${options[@]}"
        local sel=$?
        
        if [ "$sel" -eq 255 ]; then
            SELECTED_PATH=""
            return 255
        elif [ "$sel" -eq 0 ]; then
            SELECTED_PATH="$current_path"
            return 0
        elif [ "$sel" -eq 1 ]; then
            if [ "$current_path" != "/" ] && [ "$current_path" != "$start_path" ]; then
                current_path="$(dirname "$current_path")"
            fi
        else
            local dir_idx=$((sel - 2))
            local folder_name="${dirs[$dir_idx]}"
            if [ "$current_path" = "/" ]; then
                current_path="/$folder_name"
            else
                current_path="${current_path}/${folder_name}"
            fi
        fi
    done
}

# -----------------------------------------------------------------------------
# Core System Functions
# -----------------------------------------------------------------------------

# ensure_debian_dns: чинит /etc/resolv.conf внутри контейнера. proot-distro
# пишет туда 8.8.8.8, который у части провайдеров зарезан -> внутри Debian
# падает ЛЮБОЙ резолв (curl (28), apt), хотя снаружи всё летает.
# Логика: быстрый getent изнутри; не взлетел — перебор кандидатов записью
# в resolv.conf. Здоровый путь стоит ~1 getent, больной чинится сам.
ensure_debian_dns() {
    local rootfs="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
    [ -d "$rootfs" ] || return 0
    # Быстрая проверка: если resolv.conf уже содержит надежные DNS — не тратим время на сетевой getent при каждом старте
    if grep -q "77.88.8.8" "$rootfs/etc/resolv.conf" 2>/dev/null; then
        return 0
    fi
    printf 'nameserver 77.88.8.8\nnameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$rootfs/etc/resolv.conf" 2>/dev/null || return 1
    return 0
}

generate_xray_config() {
    [ -f "$PROXY_CONFIG" ] && source "$PROXY_CONFIG"
    XRAY_PORT="${XRAY_PORT:-10808}"
    
    local res=1
    if [ "$IN_APP_MODE" = "true" ]; then
        if [ -f "$WORKSPACE_DIR/vless_link.txt" ]; then
            python3 /workspace/generate_proxy_config.py /workspace/vless_link.txt "$XRAY_PORT" /workspace >/dev/null 2>&1
            res=$?
        fi
    else
        local update_gen="false"
        if [ -f "$PREFIX/bin/generate_proxy_config.py" ]; then
            cp "$PREFIX/bin/generate_proxy_config.py" "$WORKSPACE_DIR/generate_proxy_config.py"
        elif [ -f "/sdcard/AntigravityWorkspace/generate_proxy_config.py" ]; then
            cp "/sdcard/AntigravityWorkspace/generate_proxy_config.py" "$WORKSPACE_DIR/generate_proxy_config.py"
        fi
        
        if [ -f "$WORKSPACE_DIR/vless_link.txt" ]; then
            proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" --bind "/storage/emulated/0:/phone" --bind "/storage/emulated/0:/sdcard" -- /usr/bin/python3 /workspace/generate_proxy_config.py /workspace/vless_link.txt "$XRAY_PORT" /workspace >/dev/null 2>&1
            res=$?
        fi
    fi
    if [ -f "$WORKSPACE_DIR/proxy_engine.txt" ]; then
        local eng; eng=$(cat "$WORKSPACE_DIR/proxy_engine.txt" 2>/dev/null)
        if [ "$eng" = "hysteria" ]; then PROXY_TYPE="hysteria2"; elif [ "$eng" = "xray" ]; then PROXY_TYPE="xray"; fi
        sed -i "s/PROXY_TYPE=.*/PROXY_TYPE=\"$PROXY_TYPE\"/" "$PROXY_CONFIG" 2>/dev/null || true
    fi
    return $res
}

restart_proxy_core() {
    [ -f "$PROXY_CONFIG" ] && source "$PROXY_CONFIG"
    pkill -x xray >/dev/null 2>&1 || true
    pkill -x hysteria >/dev/null 2>&1 || true
    if [ "$USE_PROXY" = "true" ]; then
        local engine="xray"
        [ -f /workspace/proxy_engine.txt ] && engine=$(cat /workspace/proxy_engine.txt 2>/dev/null)
        [ "$PROXY_TYPE" = "hysteria2" ] && engine="hysteria"
        [ "$PROXY_TYPE" = "xray" ] && engine="xray"

        if [ "$engine" = "xray" ]; then
            if [ ! -x /usr/local/bin/xray ]; then
                if [ -f /workspace/xray ]; then
                    cp /workspace/xray /usr/local/bin/xray && chmod +x /usr/local/bin/xray
                else
                    echo -e " ${G2}[*] Downloading Xray core...${C_RESET}"
                    local arch; arch=$(uname -m)
                    local xarch="64"
                    case "$arch" in aarch64) xarch="arm64-v8a" ;; x86_64) xarch="64" ;; armv7l) xarch="arm32-v7a" ;; esac
                    curl -# -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${xarch}.zip" \
                        && unzip -q -o /tmp/xray.zip -d /usr/local/bin/ xray \
                        && chmod +x /usr/local/bin/xray \
                        && rm -f /tmp/xray.zip
                fi
            fi
            if [ -f /workspace/xray_config.json ]; then
                if [ -x /usr/local/bin/xray ]; then
                    nohup /usr/local/bin/xray run -c /workspace/xray_config.json >/tmp/xray.log 2>&1 &
                    sleep 1
                    if pgrep -x xray >/dev/null 2>&1; then
                        echo -e " ${G_GREEN}[OK] Xray active (socks ${XRAY_PORT:-10808}, http $(( ${XRAY_PORT:-10808} + 1 )))${C_RESET}"
                    else
                        echo -e " ${G_RED}[!] Xray failed to start. /tmp/xray.log:${C_RESET}"
                        tail -n 4 /tmp/xray.log 2>/dev/null
                    fi
                else
                    echo -e " ${G_RED}[!] /usr/local/bin/xray download failed.${C_RESET}"
                fi
            else
                echo -e " ${G_WARN}[!] /workspace/xray_config.json not found.${C_RESET}"
            fi
        elif [ "$engine" = "hysteria" ]; then
            if [ ! -x /usr/local/bin/hysteria ]; then
                if [ -f /workspace/hysteria ]; then
                    cp /workspace/hysteria /usr/local/bin/hysteria && chmod +x /usr/local/bin/hysteria
                else
                    echo -e " ${G2}[*] Downloading Hysteria core...${C_RESET}"
                    local arch; arch=$(uname -m)
                    local hyarch="amd64"
                    case "$arch" in aarch64) hyarch="arm64" ;; x86_64) hyarch="amd64" ;; armv7l) hyarch="arm" ;; esac
                    curl -# -L -o /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${hyarch}" \
                        && chmod +x /usr/local/bin/hysteria
                fi
            fi
            if [ -f /workspace/hysteria_config.json ]; then
                if [ -x /usr/local/bin/hysteria ]; then
                    nohup /usr/local/bin/hysteria -c /workspace/hysteria_config.json client >/tmp/hysteria.log 2>&1 &
                    sleep 1
                    if pgrep -x hysteria >/dev/null 2>&1; then
                        echo -e " ${G_GREEN}[OK] Hysteria2 active (socks ${XRAY_PORT:-10808}, http $(( ${XRAY_PORT:-10808} + 1 )))${C_RESET}"
                    else
                        echo -e " ${G_RED}[!] Hysteria failed to start. /tmp/hysteria.log:${C_RESET}"
                        tail -n 4 /tmp/hysteria.log 2>/dev/null
                    fi
                else
                    echo -e " ${G_RED}[!] /usr/local/bin/hysteria download failed.${C_RESET}"
                fi
            else
                echo -e " ${G_WARN}[!] /workspace/hysteria_config.json not found.${C_RESET}"
            fi
        fi
    else
        echo -e " ${G_WHITE}[*] Proxy turned OFF.${C_RESET}"
    fi
}

restart_session() {
    clear
    show_header
    if [ "$IN_APP_MODE" = "true" ]; then
        echo -e " ${G2}[*] Restarting Antigravity session...${C_RESET}"
        
        # Determine target directory in Debian container
        local targetDir="/workspace"
        if [ -f "$WORKSPACE_DIR/.last_dir" ]; then
            local savedDir; savedDir=$(cat "$WORKSPACE_DIR/.last_dir" 2>/dev/null | tr -d '\r\n')
            savedDir="${savedDir//\/storage\/emulated\/0\//\/sdcard\/}"
            if [[ "$savedDir" == "$WORKSPACE_DIR"* ]]; then
                targetDir="/workspace${savedDir#$WORKSPACE_DIR}"
            elif [[ "$savedDir" == "/sdcard"* ]]; then
                targetDir="/phone${savedDir#/sdcard}"
                [ ! -d "$targetDir" ] && targetDir="/sdcard${savedDir#/sdcard}"
            elif [ -d "$savedDir" ]; then
                targetDir="$savedDir"
            fi
        fi
        [ ! -d "$targetDir" ] && targetDir="/workspace"

        # Kill running agy and respawn window 0 in the new working directory
        pkill -9 -x agy 2>/dev/null || true
        tmux respawn-pane -k -c "$targetDir" -t agy_session:0 "export LANG=C.UTF-8; export LC_ALL=C.UTF-8; bash /workspace/run-agy.sh" 2>/dev/null || true
        sleep 0.5
        tmux select-window -t agy_session:0 2>/dev/null || true
        exit 0
    else
        echo -e " ${G2}[*] Closing Antigravity session...${C_RESET}"
        tmux kill-session -t agy_session 2>/dev/null || true
        pkill -9 -x agy 2>/dev/null || true
        exit 0
    fi
}

is_initialized() {
    [ ! -d "$WORKSPACE_DIR" ] && return 1
    [ ! -f "$PROXY_CONFIG" ] && return 1
    [ ! -f "$PROOT_BIN" ] && return 1
    ! command -v proot-distro &>/dev/null && return 1
    [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/debian" ] && return 1
    return 0
}

request_storage() {
    if [ ! -w "/sdcard" ]; then
        show_header
        echo -e " ${G_WARN}[!] Storage access required. Tap ALLOW in the dialog.${C_RESET}"
        
        # ── Fix am wrapper if it was broken by com.termux -> com.agycli blind rename
        if [ -f "$PREFIX/bin/am" ]; then
            sed -i 's/com.agycli.termuxam.Am/com.termux.termuxam.Am/g' "$PREFIX/bin/am" 2>/dev/null || true
        fi

        termux-setup-storage
        local i=0
        while [ ! -w "/sdcard" ] && [ $i -lt 10 ]; do sleep 1; ((i++)); done
        if [ ! -w "/sdcard" ]; then exit 1; fi
    fi
}

do_init() {
    request_storage
    
    # ── REGION SELECTION ──
    clear
    echo -e "\n\e[38;5;51m\e[1m  [ REGION / MIRROR SELECTION ]\e[0m\n"
    echo -e "  \e[97m1.\e[0m CIS / Russia      \e[90m(Yandex, ghfast)\e[0m"
    echo -e "  \e[97m2.\e[0m Europe & Global   \e[90m(Debian Official, github)\e[0m"
    echo -e "  \e[97m3.\e[0m Asia              \e[90m(Tsinghua, ghproxy)\e[0m"
    echo ""
    echo -n -e "  \e[38;5;51mSelect your region (1-3) [1]:\e[0m "
    drain_stdin; read -t 15 -r m_choice || m_choice="1"
    [ -z "$m_choice" ] && m_choice="1"
    mkdir -p "$WORKSPACE_DIR"
    echo "$m_choice" > "$WORKSPACE_DIR/.mirror_region"

    clear
    echo -e "\n\n\n\n"

    mkdir -p "$WORKSPACE_DIR" "$PREFIX/tmp"

    if [ ! -f "$PROXY_CONFIG" ]; then
        cat << 'EOF' > "$PROXY_CONFIG"
USE_PROXY="false"
PROXY_TYPE="xray"
PROXY_ADDR="127.0.0.1"
PROXY_PORT="10808"
XRAY_PORT="10808"
UPDATE_LOCK="true"
EOF
        chmod +x "$PROXY_CONFIG"
    fi

    # Extra keys mapping for Settings Overlay button (⚙️)
    mkdir -p "$HOME/.termux"
    if ! grep -q "⚙️" "$HOME/.termux/termux.properties" 2>/dev/null; then
        if grep -q "extra-keys" "$HOME/.termux/termux.properties" 2>/dev/null; then
            sed -i "s/'\/'/{key: 'F12', display: '⚙️'}/g" "$HOME/.termux/termux.properties"
            sed -i "s/\"\//\"{key: 'F12', display: '⚙️'}\"/g" "$HOME/.termux/termux.properties"
        else
            cat << 'EOF' >> "$HOME/.termux/termux.properties"

extra-keys = [ \
  ['ESC',{key: 'F12', display: '⚙️'},'-','HOME','UP','END','PGUP'], \
  ['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN'] \
]
EOF
        fi
        termux-reload-settings 2>/dev/null || true
    fi

    CURRENT_STEP=0
    TOTAL_STEPS=10

    draw_ui() {
        local msg="$1"
        local frame="$2"
        local sub="$3"
        local p=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
        local w=24
        local filled=$(( w * p / 100 ))
        local empty=$(( w - filled ))
        # Адаптация под узкие экраны: строка статуса "[ f ] msg(≤23) sub" иначе
        # врапится (<54 кол.), а \r\e[2K чистит только последнюю визуальную
        # строку — мусор копится каждый кадр. Фикс. часть строки = 32 клетки.
        local _cw=$(stty size 2>/dev/null | awk '{print $2}'); [ -z "$_cw" ] && _cw=80
        local _maxsub=$((_cw - 32)); [ "$_maxsub" -lt 0 ] && _maxsub=0
        sub="${sub:0:$_maxsub}"
        
        printf "\e[s"
        printf "\e[1;1H\e[2K\n\e[2K  \e[38;5;51m\e[1m[ INSTALLING ANTIGRAVITY ]\e[0m\n\e[2K  \e[38;5;45m"
        for ((j=0; j<filled; j++)); do printf "█"; done
        printf "\e[38;5;239m"
        for ((j=0; j<empty; j++)); do printf "▒"; done
        printf "\e[0m  \e[38;5;51m%3d%%\e[0m\n\e[2K\n\e[u" "$p"
        
        if [ -n "$sub" ]; then
            printf "\r\e[2K  \e[38;5;214m[ %s ]\e[0m %-23s \e[90m%s\e[0m" "$frame" "${msg:0:23}" "$sub"
        else
            printf "\r\e[2K  \e[38;5;214m[ %s ]\e[0m %s..." "$frame" "${msg:0:23}"
        fi
    }

    spin_run_host() {
        local msg="$1"; shift
        local rc=0
        CURRENT_STEP=$((CURRENT_STEP + 1))
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        printf '\e[?25l'
        > "$PREFIX/tmp/__step.log"
        ("$@") </dev/null > "$PREFIX/tmp/__step.log" 2>&1 &
        local pid=$!
        local i=0
        local submsg=""
        while kill -0 "$pid" 2>/dev/null; do
            submsg=$(tail -c 200 "$PREFIX/tmp/__step.log" 2>/dev/null | tr '\r' '\n' | tail -n 1 | tr -dc '[:print:]' | cut -c1-22)
            draw_ui "$msg" "${frames[$((i % 10))]}" "$submsg"
            i=$((i+1))
            sleep 0.08
        done
        wait "$pid"; rc=$?
        draw_ui "$msg" "✓" ""
        if [ $rc -eq 0 ]; then
            printf '\r\e[2K  \e[38;5;46m[ ✓ ]\e[0m %s\n' "$msg"
        else
            printf '\r\e[2K  \e[38;5;196m[ ✗ ]\e[0m %s\n' "$msg"
            cat "$PREFIX/tmp/__step.log" 2>/dev/null || true
            exit 1
        fi
        printf '\e[?25h'
        return $rc
    }

    _install_proot() {
        if [ ! -f "$PROOT_BIN" ]; then
            pkg update -y -q
            pkg install proot -y -q
        fi
        chmod +x "$PROOT_BIN"
    }
    spin_run_host "Virtualization Core (proot)" _install_proot

    _install_debian() {
        if ! proot-distro list 2>/dev/null | grep -q 'debian'; then
            proot-distro install debian
        fi
    }
    spin_run_host "Subsystem Image (Debian)" _install_debian
    spin_run_host "Checking Debian DNS" ensure_debian_dns

    proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" --bind "/storage/emulated/0:/phone" --bind "/storage/emulated/0:/sdcard" -- /bin/bash << DEBIAN_SETUP
set -e
export DEBIAN_FRONTEND=noninteractive
CURRENT_STEP=$CURRENT_STEP
TOTAL_STEPS=$TOTAL_STEPS

draw_ui() {
    local msg="\$1"
    local frame="\$2"
    local sub="\$3"
    local p=\$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
    local w=24
    local filled=\$(( w * p / 100 ))
    local empty=\$(( w - filled ))
    # Адаптация под узкие экраны: см. комментарий в draw_ui do_init.
    local _cw=\$(stty size 2>/dev/null | awk '{print \$2}'); [ -z "\$_cw" ] && _cw=80
    local _maxsub=\$((_cw - 32)); [ "\$_maxsub" -lt 0 ] && _maxsub=0
    sub="\${sub:0:\$_maxsub}"
    
    printf "\e[s"
    printf "\e[1;1H\e[2K\n\e[2K  \e[38;5;51m\e[1m[ INSTALLING ANTIGRAVITY ]\e[0m\n\e[2K  \e[38;5;45m"
    for ((j=0; j<filled; j++)); do printf "█"; done
    printf "\e[38;5;239m"
    for ((j=0; j<empty; j++)); do printf "▒"; done
    printf "\e[0m  \e[38;5;51m%3d%%\e[0m\n\e[2K\n\e[u" "\$p"
    
    if [ -n "\$sub" ]; then
        printf "\r\e[2K  \e[38;5;214m[ %s ]\e[0m %-23s \e[90m%s\e[0m" "\$frame" "\${msg:0:23}" "\$sub"
    else
        printf "\r\e[2K  \e[38;5;214m[ %s ]\e[0m %s..." "\$frame" "\${msg:0:23}"
    fi
}

spin_run() {
    local msg="\$1"; shift
    local rc=0
    CURRENT_STEP=\$((CURRENT_STEP + 1))
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    printf '\e[?25l'
    > /tmp/__step.log
    ("\$@") </dev/null > /tmp/__step.log 2>&1 &
    local pid=\$!
    local i=0
    local submsg=""
    while kill -0 "\$pid" 2>/dev/null; do
        submsg=\$(tail -c 200 /tmp/__step.log 2>/dev/null | tr '\r' '\n' | tail -n 1 | tr -dc '[:print:]' | cut -c1-22)
        draw_ui "\$msg" "\${frames[\$((i % 10))]}" "\$submsg"
        i=\$((i+1))
        sleep 0.08
    done
    wait "\$pid"; rc=\$?
    draw_ui "\$msg" "✓" ""
    if [ \$rc -eq 0 ]; then
        printf '\r\e[2K  \e[38;5;46m[ ✓ ]\e[0m %s\n' "\$msg"
    else
        printf '\r\e[2K  \e[38;5;196m[ ✗ ]\e[0m %s\n' "\$msg"
        cat /tmp/__step.log
    fi
    printf '\e[?25h'
    return \$rc
}

M_CHOICE=\$(cat /workspace/.mirror_region 2>/dev/null | tr -d '\r\n' || echo 1)
[ -z "\$M_CHOICE" ] && M_CHOICE=1
AGY_VERSION="1.1.26"
AGY_VERSION=\$(echo "\$AGY_VERSION" | tr -d '\r\n')
readonly AGY_VERSION
# STRICT PIN: V1.3.8 fe12d5b — не менять без релиза (см. VERSIONS.lock)

if [ "\$M_CHOICE" = "1" ]; then
    sed -i -E 's|(deb|ftp)\.debian\.org|mirror.yandex.ru|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
    sed -i -E 's|(deb|ftp)\.debian\.org|mirror.yandex.ru|g' /etc/apt/sources.list 2>/dev/null || true
    MIRRORS=(
        "https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghfast.top/https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghproxy.net/https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://gh-proxy.com/https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
    )
elif [ "\$M_CHOICE" = "3" ]; then
    sed -i -E 's|(deb|ftp)\.debian\.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || true
    sed -i -E 's|(deb|ftp)\.debian\.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list 2>/dev/null || true
    MIRRORS=(
        "https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghproxy.net/https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://gh-proxy.com/https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghfast.top/https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
    )
else
    MIRRORS=(
        "https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghfast.top/https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghproxy.net/https://github.com/google-antigravity/antigravity-cli/releases/download/\${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
    )
fi

APT_OPTS="-o Acquire::Retries=3 -o Acquire::http::Timeout=10 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
spin_run "Updating Repositories" apt-get \$APT_OPTS update
spin_run "Installing Core Packages" apt-get \$APT_OPTS install -y --no-install-recommends curl ca-certificates unzip procps xz-utils python3 git python3-packaging
mkdir -p "\$HOME/.local/bin" "\$HOME/.local/share/agy"

download_engine() {
    for url in "\${MIRRORS[@]}"; do
        if curl -sS -fL --connect-timeout 5 --speed-limit 10000 --speed-time 15 --max-time 300 -o /tmp/agy_cli.tar.gz "\$url"; then
            return 0
        fi
    done
    return 1
}
# Целостность архива до распаковки: раньше битый тарболл умирал только на tar.
verify_engine() {
    # ВАЖНО: без pipefail выход пайпа = выход grep; tar может напечатать имя
    # члена и всё равно упасть на EOF — вывод забираем, код tar проверяем.
    [ -s /tmp/agy_cli.tar.gz ] || return 1
    local _list
    _list=$(tar tzf /tmp/agy_cli.tar.gz 2>/dev/null) || return 1
    echo "$_list" | grep -qE '(^|/)(antigravity|agy)$' || return 1
}
_do_install() {
    local _bin=""
    for _c in /tmp/antigravity /tmp/agy /tmp/agy_cli_linux_arm64/antigravity; do
        [ -f "\$_c" ] && _bin="\$_c" && break
    done
    [ -z "\$_bin" ] && _bin=\$(find /tmp \( -name 'antigravity' -o -name 'agy' \) -type f 2>/dev/null | head -1)
    [ -n "\$_bin" ] || return 1
    # Обрубки (частичная распаковка битого архива — в проде был 78КБ вместо
    # ~200МБ) — в топку, а не в bin. Пол 20МБ с запасом на будущие версии.
    local _sz; _sz=\$(stat -c %s "\$_bin" 2>/dev/null || echo 0)
    [ "\$_sz" -ge 20000000 ] || return 1
    mv "\$_bin" "\$HOME/.local/bin/agy" || return 1
    chmod +x "\$HOME/.local/bin/agy" 2>/dev/null || true
    rm -rf /tmp/agy_cli.tar.gz /tmp/agy_cli_linux_arm64
}
# Официальный установщик (SHA512, всегда latest). install.sh выходит рано, если
# agy уже есть — поэтому сносим перед запуском, чтобы поставить свежак.
install_official() {
    rm -f "\$HOME/.local/bin/agy"
    curl -fsSL https://antigravity.google/cli/install.sh | bash || return 1
    [ -x "\$HOME/.local/bin/agy" ] || return 1
    local _sz; _sz=\$(stat -c %s "\$HOME/.local/bin/agy" 2>/dev/null || echo 0)
    [ "\$_sz" -ge 20000000 ] || return 1
}
# Официальный путь; при провале (регион/блокировка run.app) — откат на зеркала.
engine_install() {
    if install_official; then return 0; fi
    echo "[*] Official installer unavailable — falling back to GitHub mirrors..."
    download_engine || return 1
    verify_engine || return 1
    rm -rf /tmp/antigravity /tmp/agy /tmp/agy_cli_linux_arm64
    tar -xzf /tmp/agy_cli.tar.gz -C /tmp/ || return 1
    _do_install || return 1
}
spin_run "Installing Antigravity Engine" engine_install

# Маркер = sha256 установленного (непропатченного) бинаря; меняется при любой
# переустановке/обновлении → авто-патчер перепатчит. Хардкод версии больше не нужен.
AGY_MARK=\$(sha256sum "\$HOME/.local/bin/agy" 2>/dev/null | cut -c1-16)
echo "\$AGY_MARK" > "\$HOME/.local/share/agy/.version_lock"
echo "[OK] agy installed (official/latest, mark \$AGY_MARK)."
DEBIAN_SETUP

    echo -e " ${G_GREEN}[OK] Setup complete!${C_RESET}"
    sleep 1
    do_start_inner
}

do_start_inner() {
    [ -f "$PROXY_CONFIG" ] && source "$PROXY_CONFIG"

    # Текущее состояние лока обновлений — в файл, видимый контейнеру как
    # /workspace/.update_lock (его читают start-agy.sh и check_and_patch.py).
    mkdir -p "$WORKSPACE_DIR"
    echo "${UPDATE_LOCK:-true}" > "$WORKSPACE_DIR/.update_lock"

    # Засеять офлайн-бандл патчера в workspace из $HOME (приложение кладёт его
    # туда всегда, без storage-разрешения) — чтобы на первом запуске run_patcher
    # распаковал его офлайн, а не уходил в git-фолбэк.
    if [ -f "$HOME/open-antigravity-patcher-v1.3.8.tar" ] && [ ! -s "$WORKSPACE_DIR/open-antigravity-patcher-v1.3.8.tar" ]; then
        cp "$HOME/open-antigravity-patcher-v1.3.8.tar" "$WORKSPACE_DIR/" 2>/dev/null || true
    fi

    # DNS внутри контейнера чиним при каждом старте (дешёвый getent, если жив).
    # Без этого падает всё сетевое: патчер-клон, xray-скачивание, agy-обновление.
    if [ "$IN_APP_MODE" != "true" ]; then
        ensure_debian_dns >/dev/null 2>&1 || echo -e " ${G_WARN}[!] Debian DNS repair failed — network features may not work.${C_RESET}"
        # Kill any stale tmux processes left over from prior sessions on Android host
        # and clean up leftover socket directories to prevent "access not allowed"
        pkill -9 -x tmux 2>/dev/null || true
        local _rootfs="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
        rm -rf "$_rootfs/tmp/tmux-*" 2>/dev/null || true
    fi

    # Если бинаря нет (удалён вручную после установки) — не уходим в вечный
    # цикл run-agy.sh с голым bash, а чиним через do_update и едем дальше.
    # Путь фиксирован на /root: внутри контейнера логин всегда root.
    local _agy_ok="false"
    if [ "$IN_APP_MODE" = "true" ]; then
        [ -x /root/.local/bin/agy ] && _agy_ok="true"
    else
        local _rootfs="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
        if [ -x "$_rootfs/root/.local/bin/agy" ]; then
            _agy_ok="true"
        elif proot-distro login debian -- test -x /root/.local/bin/agy 2>/dev/null; then
            _agy_ok="true"
        fi
    fi
    if [ "$_agy_ok" != "true" ]; then
        echo -e " ${G_WARN}[!] agy binary missing — running update to reinstall...${C_RESET}"
        sleep 1
        do_update || return $?
    fi

    local activeDir="$WORKSPACE_DIR"
    if [ -f "$LAST_DIR_FILE" ]; then activeDir=$(cat "$LAST_DIR_FILE"); fi
    # Normalize /storage/emulated/0 paths → /sdcard for consistent matching
    activeDir="${activeDir//\/storage\/emulated\/0\//\/sdcard\/}"
    local targetDir="/workspace"
    local sMode="WORKSPACE ONLY"
    if [[ "$activeDir" == "$WORKSPACE_DIR"* ]]; then
        targetDir="/workspace${activeDir#$WORKSPACE_DIR}"
    elif [[ "$activeDir" == "/sdcard"* ]]; then
        targetDir="/phone${activeDir#/sdcard}"
        sMode="FULL SYSTEM"
    fi

    # Массив, а не строка: пути с пробелами иначе рвутся на word splitting
    # (кавычки внутри строки бы не перепарсились — стало бы только хуже).
    local -a EXTRA_BINDS=()
    [ -d "$WORKSPACE_DIR" ] && EXTRA_BINDS+=(--bind "$WORKSPACE_DIR:/workspace")
    # Always mount phone storage unconditionally using the real Android path
    if [ -d "/storage/emulated/0" ]; then
        EXTRA_BINDS+=(--bind "/storage/emulated/0:/phone" --bind "/storage/emulated/0:/sdcard")
    elif [ -d "/sdcard" ]; then
        EXTRA_BINDS+=(--bind "/sdcard:/phone" --bind "/sdcard:/sdcard")
    fi

    if [ -f "$PREFIX/bin/check_and_patch.py" ]; then
        cp "$PREFIX/bin/check_and_patch.py" "$WORKSPACE_DIR/check_and_patch.py"
    fi

    # Copy this manager script into workspace for Tmux to use as overlay.
    # $0 бывает относительным (./agy-manager.sh) — резолвим, иначе cp при
    # чужом CWD скопирует не тот файл (или упадёт).
    local _self; _self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
    cp "$_self" "$WORKSPACE_DIR/agy-manager.sh"
    chmod +x "$WORKSPACE_DIR/agy-manager.sh"

    cat > "$WORKSPACE_DIR/start-agy.sh" << 'EOF'
#!/bin/bash
EOF
    echo "cd \"$targetDir\"" >> "$WORKSPACE_DIR/start-agy.sh"
    cat >> "$WORKSPACE_DIR/start-agy.sh" << 'EOF'
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# Load proxy configuration
[ -f /workspace/proxy_config.sh ] && source /workspace/proxy_config.sh

# Install Tmux if missing
if ! command -v tmux >/dev/null 2>&1; then
    echo -e "\e[33m[*] Installing Tmux for Overlay UI...\e[0m"
    apt-get update >/dev/null 2>&1 && apt-get install -y tmux >/dev/null 2>&1
fi

# ── Auto-patch agy binary (V1.3.8 MultiGate: x64 + arm64) ─────────────────────
_agy_bin="$HOME/.local/bin/agy"
_ver_lock="$HOME/.local/share/agy/.version_lock"
_pat_mark="$HOME/.local/share/agy/.patched_version"
if [ -f "$_agy_bin" ] && [ -f "$_ver_lock" ]; then
    _cur_ver=$(cat "$_ver_lock" 2>/dev/null)
    _pat_ver=$(cat "$_pat_mark" 2>/dev/null)
    if [ "$_cur_ver" != "$_pat_ver" ]; then
        echo -e "\e[34m[*]\e[0m Auto-patching agy v${_cur_ver} (V1.3.8)..."
        _lock=$(cat /workspace/.update_lock 2>/dev/null || echo true)
        # Temporarily unlock binary for patching
        chattr -i "$_agy_bin" 2>/dev/null || true
        chmod 755 "$_agy_bin" 2>/dev/null || true
        python3 - "$_agy_bin" "$_ver_lock" "$_pat_mark" "$_lock" << 'AUTOPATCH'
import sys, re, os
agy, ver_lock, marker = sys.argv[1], sys.argv[2], sys.argv[3]
lock = (len(sys.argv) < 5 or sys.argv[4] != 'false')  # update lock: ON по умолчанию
# V1.3.8 gates: CLI_GATE_X64 + CLI_GATE_ARM64 + ARM64_W2 + ARM64_W4 (сверено с source/patcher/agy/patcher.py)
GATES = [
    (re.compile(rb"\x48\x85\xc0\x0f\x84....\x80\x78\x08\x00\x0f\x85....", re.S), b"\x48\x85\xc0\x90", 9),  # CLI_GATE_X64
    (re.compile(rb"...\xb5...\xb4\x01\x20\x40\x39[\x01\x21\x41\x61\x81\xa1\xc1\xe1].[\x00-\x07]\x37" rb"...[\x94-\x97](?:\xe0\x4b\x00\xf9\xe1\x33\x00\xf9\xe2\x43\x00\xf9" rb"|\xe0\x4f\x00\xf9\xe1\x33\x00\xf9\xe2\x47\x00\xf9\xe3\x2f\x00\xf9)", re.S), b"\x21\x00\x80\x52", 8),  # CLI_GATE_ARM64
    (re.compile(rb"[\x01\x21\x41\x61\x81\xa1\xc1\xe1]..\xb5[\x00\x20\x40\x60\x80\xa0\xc0\xe0]..\xb4" rb"\x02\x20\x40\x39[\x02\x22\x42\x62\x82\xa2\xc2\xe2].[\x00-\x07]\x37...[\x94-\x97]", re.S), b"\x22\x00\x80\x52", 8),  # CLI_GATE_ARM64_W2
    (re.compile(rb"[\x00\x20\x40\x60\x80\xa0\xc0\xe0]..\xb4\x04\x20\x40\x39" rb"[\x04\x24\x44\x64\x84\xa4\xc4\xe4].[\x00-\x07]\x37\x04\x94\x44\xa9", re.S), b"\x24\x00\x80\x52", 4),  # CLI_GATE_ARM64_W4
]
# Embedded auto-updater endpoint; replaced with equal-length junk so ELF layout survives
UPDATER_URL = b"https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
DISABLED_URL = b"http://127.0.0.1:9999/disabled-auto-updater-server-url-disabled-block"
assert len(UPDATER_URL) == len(DISABLED_URL)
# Паттерны УЖЕ пропатченных гейтов: отличаем «уже готов» от «гейт не найден».
PATCHED = [
    re.compile(rb"\x48\x85\xc0\x0f\x84....\x48\x85\xc0\x90\x0f\x85....", re.S),  # CLI_GATE_X64
    re.compile(rb"...\xb5...\xb4\x21\x00\x80\x52[\x01\x21\x41\x61\x81\xa1\xc1\xe1].[\x00-\x07]\x37" rb"...[\x94-\x97](?:\xe0\x4b\x00\xf9\xe1\x33\x00\xf9\xe2\x43\x00\xf9" rb"|\xe0\x4f\x00\xf9\xe1\x33\x00\xf9\xe2\x47\x00\xf9\xe3\x2f\x00\xf9)", re.S),  # CLI_GATE_ARM64
    re.compile(rb"[\x01\x21\x41\x61\x81\xa1\xc1\xe1]..\xb5[\x00\x20\x40\x60\x80\xa0\xc0\xe0]..\xb4" rb"\x22\x00\x80\x52[\x02\x22\x42\x62\x82\xa2\xc2\xe2].[\x00-\x07]\x37...[\x94-\x97]", re.S),  # CLI_GATE_ARM64_W2
    re.compile(rb"[\x00\x20\x40\x60\x80\xa0\xc0\xe0]..\xb4\x24\x00\x80\x52" rb"[\x04\x24\x44\x64\x84\xa4\xc4\xe4].[\x00-\x07]\x37\x04\x94\x44\xa9", re.S),  # CLI_GATE_ARM64_W4
]
def _write_marker():
    ver = open(ver_lock).read().strip()
    os.makedirs(os.path.dirname(marker), exist_ok=True)
    open(marker, 'w').write(ver)
try:
    with open(agy, 'rb') as f: data = bytearray(f.read())
    raw = bytes(data)
    hits = 0
    for sig, fix, off in GATES:
        for m in sig.finditer(raw):
            pos = m.start() + off
            if data[pos:pos+len(fix)] != fix:
                data[pos:pos+len(fix)] = fix
                hits += 1
                print(f'  \033[32m✓\033[0m gate patched @ 0x{pos:08x} ({fix.hex()})')
    if lock:
        if UPDATER_URL in bytes(data):
            data = bytearray(bytes(data).replace(UPDATER_URL, DISABLED_URL))
            hits += 1
            print('  \033[32m✓\033[0m auto-updater URL neutralized (update lock ON)')
    else:
        if DISABLED_URL in bytes(data):
            data = bytearray(bytes(data).replace(DISABLED_URL, UPDATER_URL))
            hits += 1
            print('  \033[33m•\033[0m auto-updater URL restored (update lock OFF)')
    if hits:
        with open(agy, 'wb') as f: f.write(data)
        print(f'\033[32m[OK]\033[0m patch applied — eligibility screen off (update lock {"ON" if lock else "OFF"}) (V1.3.8)')
        _write_marker()
    elif any(p.search(raw) for p in PATCHED):
        print('\033[34m[*]\033[0m agy already patched — marker refreshed.')
        _write_marker()
    else:
        # Гейт не найден и следов патча нет: маркер НЕ пишем, иначе бинарь без
        # патча будет вечно считаться пропатченным. Повторим при след. запуске.
        print('\033[31m[!]\033[0m no gate matched AND no patched trace — binary left untouched, will retry next start.')
except Exception as e:
    print(f'\033[31m[!]\033[0m auto-patch error: {e}')
AUTOPATCH
        # Повторная блокировка только если лок обновлений включён; иначе
        # оставляем бинарь записываемым, чтобы agy мог самообновиться.
        if [ "$_lock" = "true" ]; then
            chmod 555 "$_agy_bin" 2>/dev/null || true
            chattr +i "$_agy_bin" 2>/dev/null || true
        else
            chattr -i "$_agy_bin" 2>/dev/null || true
            chmod 755 "$_agy_bin" 2>/dev/null || true
        fi
    fi
fi
# ─────────────────────────────────────────────────────────────────────────────

    # Пользовательский tmux.conf не затираем молча — один раз бэкапим.
    [ -f "$HOME/.tmux.conf" ] && [ ! -f "$HOME/.tmux.conf.agybak" ] && cp "$HOME/.tmux.conf" "$HOME/.tmux.conf.agybak"
    cat > "$HOME/.tmux.conf" << 'TMUX_CONF'
set -g default-terminal "xterm-256color"
set -ag terminal-overrides ",xterm-256color:Tc"
set -s escape-time 0
set -g mouse on
set -g history-limit 50000
set -g status off
set -g mode-style "fg=#555555,bg=default"
bind -n Pageup copy-mode -u -e
bind -n S-Pageup copy-mode -u -e
bind -T copy-mode WheelUpPane select-pane \; send-keys -X -N 2 scroll-up
bind -T copy-mode WheelDownPane select-pane \; send-keys -X -N 2 scroll-down
bind -T copy-mode-vi WheelUpPane select-pane \; send-keys -X -N 2 scroll-up
bind -T copy-mode-vi WheelDownPane select-pane \; send-keys -X -N 2 scroll-down
bind -T copy-mode Escape send-keys -X cancel
bind -T copy-mode-vi Escape send-keys -X cancel
bind -n F12 new-window -n "Settings" "export LANG=C.UTF-8; export LC_ALL=C.UTF-8; bash /workspace/agy-manager.sh --in-app"
TMUX_CONF

if [ "$USE_PROXY" = "true" ] && { [ "$PROXY_TYPE" = "xray" ] || [ "$PROXY_TYPE" = "hysteria2" ]; }; then
    ENGINE="xray"
    [ -f /workspace/proxy_engine.txt ] && ENGINE=$(cat /workspace/proxy_engine.txt 2>/dev/null)
    [ "$PROXY_TYPE" = "hysteria2" ] && ENGINE="hysteria"
    [ "$PROXY_TYPE" = "xray" ] && ENGINE="xray"
    pkill -x xray >/dev/null 2>&1 || true
    pkill -x hysteria >/dev/null 2>&1 || true
    if [ "$ENGINE" = "xray" ]; then
        if [ ! -f /usr/local/bin/xray ]; then
            if [ -f /workspace/xray ]; then
                cp /workspace/xray /usr/local/bin/xray && chmod +x /usr/local/bin/xray
            else
                ARCH=$(uname -m)
                case "$ARCH" in aarch64) XRAY_ARCH="arm64-v8a" ;; x86_64) XRAY_ARCH="64" ;; armv7l) XRAY_ARCH="arm32-v7a" ;; *) XRAY_ARCH="64" ;; esac
                curl -# -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" \
                    && unzip -q -o /tmp/xray.zip -d /usr/local/bin/ xray \
                    && chmod +x /usr/local/bin/xray \
                    && rm -f /tmp/xray.zip
            fi
        fi
        if [ -f /workspace/xray_config.json ]; then
            if [ -x /usr/local/bin/xray ]; then
                nohup /usr/local/bin/xray run -c /workspace/xray_config.json >/tmp/xray.log 2>&1 &
            else
                echo -e "\e[31m[!] PROXY CORE MISSING: /usr/local/bin/xray not installed — agy will run WITHOUT proxy! Check network and restart session.\e[0m"
                sleep 3
            fi
        fi
    elif [ "$ENGINE" = "hysteria" ]; then
        if [ ! -f /usr/local/bin/hysteria ]; then
            if [ -f /workspace/hysteria ]; then
                cp /workspace/hysteria /usr/local/bin/hysteria && chmod +x /usr/local/bin/hysteria
            else
                ARCH=$(uname -m)
                case "$ARCH" in aarch64) HY_ARCH="arm64" ;; x86_64) HY_ARCH="amd64" ;; armv7l) HY_ARCH="arm" ;; *) HY_ARCH="amd64" ;; esac
                curl -# -L -o /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${HY_ARCH}" \
                    && chmod +x /usr/local/bin/hysteria
            fi
        fi
        if [ -f /workspace/hysteria_config.json ]; then
            if [ -x /usr/local/bin/hysteria ]; then
                nohup /usr/local/bin/hysteria -c /workspace/hysteria_config.json client >/tmp/hysteria.log 2>&1 &
            else
                echo -e "\e[31m[!] PROXY CORE MISSING: /usr/local/bin/hysteria not installed — agy will run WITHOUT proxy! Check network and restart session.\e[0m"
                sleep 3
            fi
        fi
    fi
    local_port="${XRAY_PORT:-10808}"
    http_port=$(( local_port + 1 ))
    export HTTP_PROXY="http://127.0.0.1:${http_port}"
    export HTTPS_PROXY="$HTTP_PROXY"
    export ALL_PROXY="socks5h://127.0.0.1:${local_port}"
    export http_proxy="$HTTP_PROXY"
    export https_proxy="$HTTPS_PROXY"
    export all_proxy="$ALL_PROXY"
    export GRPC_PROXY="$HTTP_PROXY"
    export grpc_proxy="$HTTP_PROXY"
    export NO_PROXY="localhost,127.0.0.1"
    export no_proxy="$NO_PROXY"
    for _i in $(seq 1 20); do
        (exec 3<>/dev/tcp/127.0.0.1/${http_port}) 2>/dev/null && { exec 3>&-; break; }
        sleep 0.1
    done
fi
if [ "$USE_PROXY" = "true" ] && [ "$PROXY_TYPE" != "xray" ] && [ "$PROXY_TYPE" != "hysteria2" ]; then
    export HTTP_PROXY="${PROXY_TYPE}://${PROXY_ADDR}:${PROXY_PORT}"
    export HTTPS_PROXY="$HTTP_PROXY"
    export ALL_PROXY="$HTTP_PROXY"
    export http_proxy="$HTTP_PROXY"
    export https_proxy="$HTTPS_PROXY"
    export all_proxy="$ALL_PROXY"
    export GRPC_PROXY="$HTTP_PROXY"
    export grpc_proxy="$HTTP_PROXY"
    export NO_PROXY="localhost,127.0.0.1"
    export no_proxy="$NO_PROXY"
fi

cat > "/workspace/check_and_patch.py" << 'CHECK_PATCH'
import sys, re, os, subprocess
agy = os.path.expanduser("~/.local/bin/agy")
try:
    with open("/workspace/.update_lock") as _f: lock = (_f.read().strip() != "false")
except Exception:
    lock = True  # update lock ON по умолчанию

cache_file = os.path.expanduser("~/.local/share/agy/.patch_cache")
try:
    if os.path.exists(agy):
        st = os.stat(agy)
        cur_key = f"{st.st_size}_{st.st_mtime_ns}_{lock}_v1.3.8"
        if os.path.exists(cache_file):
            with open(cache_file, "r") as _cf:
                if _cf.read().strip() == cur_key:
                    sys.exit(0)
except Exception:
    pass

# V1.3.8 MultiGate: X64 + ARM64 + ARM64_W2 + ARM64_W4 (сверено с source/patcher/agy/patcher.py)
GATES = [
    (re.compile(rb"\x48\x85\xc0\x0f\x84....\x80\x78\x08\x00\x0f\x85....", re.S), b"\x48\x85\xc0\x90", 9),  # CLI_GATE_X64
    (re.compile(rb"...\xb5...\xb4\x01\x20\x40\x39[\x01\x21\x41\x61\x81\xa1\xc1\xe1].[\x00-\x07]\x37" rb"...[\x94-\x97](?:\xe0\x4b\x00\xf9\xe1\x33\x00\xf9\xe2\x43\x00\xf9" rb"|\xe0\x4f\x00\xf9\xe1\x33\x00\xf9\xe2\x47\x00\xf9\xe3\x2f\x00\xf9)", re.S), b"\x21\x00\x80\x52", 8),  # CLI_GATE_ARM64
    (re.compile(rb"[\x01\x21\x41\x61\x81\xa1\xc1\xe1]..\xb5[\x00\x20\x40\x60\x80\xa0\xc0\xe0]..\xb4" rb"\x02\x20\x40\x39[\x02\x22\x42\x62\x82\xa2\xc2\xe2].[\x00-\x07]\x37...[\x94-\x97]", re.S), b"\x22\x00\x80\x52", 8),  # CLI_GATE_ARM64_W2
    (re.compile(rb"[\x00\x20\x40\x60\x80\xa0\xc0\xe0]..\xb4\x04\x20\x40\x39" rb"[\x04\x24\x44\x64\x84\xa4\xc4\xe4].[\x00-\x07]\x37\x04\x94\x44\xa9", re.S), b"\x24\x00\x80\x52", 4),  # CLI_GATE_ARM64_W4
]
# Embedded auto-updater endpoint; equal-length replacement keeps ELF layout intact
UPDATER_URL = b"https://antigravity-cli-auto-updater-974169037036.us-central1.run.app"
DISABLED_URL = b"http://127.0.0.1:9999/disabled-auto-updater-server-url-disabled-block"
assert len(UPDATER_URL) == len(DISABLED_URL)
try:
    if not os.path.exists(agy):
        sys.exit(0)
    os.system(f"chattr -i {agy} 2>/dev/null")  # снять возможную иммутабельность для перезаписи
    with open(agy, 'rb') as f: data = bytearray(f.read())
    hits = 0
    for sig, fix, off in GATES:
        for m in sig.finditer(bytes(data)):
            pos = m.start() + off
            if data[pos:pos+len(fix)] != fix:
                data[pos:pos+len(fix)] = fix
                hits += 1
                print(f'\033[34m[*]\033[0m Auto-patcher (V1.3.8): gate patched @ 0x{pos:08x}')
    if lock:
        if UPDATER_URL in bytes(data):
            data = bytearray(bytes(data).replace(UPDATER_URL, DISABLED_URL))
            hits += 1
            print('\033[34m[*]\033[0m Auto-patcher (V1.3.8): auto-updater URL neutralized (lock ON)')
    else:
        if DISABLED_URL in bytes(data):
            data = bytearray(bytes(data).replace(DISABLED_URL, UPDATER_URL))
            hits += 1
            print('\033[33m[*]\033[0m Auto-patcher: auto-updater URL restored (lock OFF)')
    if hits:
        # Prevent "Text file busy" or "Permission denied"
        os.system("pkill -9 -x agy 2>/dev/null")
        os.system(f"chmod 755 {agy} 2>/dev/null")
        os.system(f"rm -f {agy}.tmp 2>/dev/null")
        with open(f"{agy}.tmp", 'wb') as f: f.write(data)
        os.system(f"chmod 755 {agy}.tmp")
        os.system(f"mv -f {agy}.tmp {agy}")
        print(f'\033[32m[OK]\033[0m patch applied — gates off (update lock {"ON" if lock else "OFF"}) (V1.3.8)')
    # Привести права бинаря к состоянию лока: ON → иммутабельный, OFF → записываемый.
    if lock:
        os.system(f"chmod 555 {agy} 2>/dev/null")
        os.system(f"chattr +i {agy} 2>/dev/null")
    else:
        os.system(f"chattr -i {agy} 2>/dev/null")
        os.system(f"chmod 755 {agy} 2>/dev/null")
    try:
        new_st = os.stat(agy)
        new_key = f"{new_st.st_size}_{new_st.st_mtime_ns}_{lock}_v1.3.8"
        os.makedirs(os.path.dirname(cache_file), exist_ok=True)
        with open(cache_file, "w") as _cf:
            _cf.write(new_key)
    except Exception:
        pass
except Exception as e:
    print(f'\033[31m[!]\033[0m auto-patch error: {e}')
CHECK_PATCH

cat > "/workspace/run-agy.sh" << 'RUN_AGY'
#!/bin/bash
while true; do
    # Run the auto-patcher Python script
    if [ -f /workspace/check_and_patch.py ]; then
        python3 /workspace/check_and_patch.py
    fi

    # Ensure proxy environment is loaded
    if [ -f /workspace/proxy_config.sh ]; then
        source /workspace/proxy_config.sh
        if [ "$USE_PROXY" = "true" ]; then
            _local_port="${XRAY_PORT:-10808}"
            _http_port=$(( _local_port + 1 ))
            if [ "$PROXY_TYPE" = "xray" ] || [ "$PROXY_TYPE" = "hysteria2" ]; then
                export HTTP_PROXY="http://127.0.0.1:${_http_port}"
                export HTTPS_PROXY="$HTTP_PROXY"
                export ALL_PROXY="socks5h://127.0.0.1:${_local_port}"
                export http_proxy="$HTTP_PROXY"
                export https_proxy="$HTTPS_PROXY"
                export all_proxy="$ALL_PROXY"
                export GRPC_PROXY="$HTTP_PROXY"
                export grpc_proxy="$HTTP_PROXY"
            else
                export HTTP_PROXY="${PROXY_TYPE}://${PROXY_ADDR}:${PROXY_PORT}"
                export HTTPS_PROXY="$HTTP_PROXY"
                export ALL_PROXY="$HTTP_PROXY"
                export http_proxy="$HTTP_PROXY"
                export https_proxy="$HTTPS_PROXY"
                export all_proxy="$ALL_PROXY"
                export GRPC_PROXY="$HTTP_PROXY"
                export grpc_proxy="$HTTP_PROXY"
            fi
            export NO_PROXY="localhost,127.0.0.1"
            export no_proxy="$NO_PROXY"
        else
            unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy GRPC_PROXY grpc_proxy NO_PROXY no_proxy
        fi
    fi

    # Ensure we are in target directory from .last_dir
    TARGET_DIR="/workspace"
    if [ -f /workspace/.last_dir ]; then
        SAVED_DIR=$(cat /workspace/.last_dir 2>/dev/null | tr -d '\r\n')
        SAVED_DIR="${SAVED_DIR//\/storage\/emulated\/0\//\/sdcard\/}"
        if [[ "$SAVED_DIR" == "/sdcard/AntigravityWorkspace"* ]]; then
            CANDIDATE="/workspace${SAVED_DIR#/sdcard/AntigravityWorkspace}"
            [ -d "$CANDIDATE" ] && TARGET_DIR="$CANDIDATE"
        elif [ -d "$SAVED_DIR" ]; then
            TARGET_DIR="$SAVED_DIR"
        elif [[ "$SAVED_DIR" == "/sdcard"* ]]; then
            CANDIDATE="/phone${SAVED_DIR#/sdcard}"
            [ -d "$CANDIDATE" ] && TARGET_DIR="$CANDIDATE"
        fi
    fi
    cd "$TARGET_DIR" 2>/dev/null || cd /workspace

    if command -v agy > /dev/null 2>&1; then
        agy "$@"
    elif [ -f "$HOME/.local/bin/agy" ]; then
        "$HOME/.local/bin/agy" "$@"
    else
        bash
    fi
    echo -e "\n\e[33m[!] AGY session closed. Restarting... (Ctrl+C to exit)\e[0m"
    sleep 1
    clear
done
RUN_AGY
chmod +x "/workspace/run-agy.sh"

if command -v tmux >/dev/null 2>&1; then
    pkill -9 -x tmux 2>/dev/null || true
    rm -rf /tmp/tmux-* 2>/dev/null || true
    exec tmux -u -f "$HOME/.tmux.conf" new-session -s agy_session "export LANG=C.UTF-8; export LC_ALL=C.UTF-8; bash /workspace/run-agy.sh" || exec bash "/workspace/run-agy.sh" "$@"
else
    exec bash "/workspace/run-agy.sh" "$@"
fi
EOF
    chmod +x "$WORKSPACE_DIR/start-agy.sh"

    proot-distro login debian "${EXTRA_BINDS[@]}" --no-kill-on-exit \
        -- /bin/bash -c 'cp /workspace/start-agy.sh /usr/local/bin/start-agy.sh && chmod +x /usr/local/bin/start-agy.sh && exec /usr/local/bin/start-agy.sh'
}

check_and_apply_upgrades() {
    local props="$HOME/.termux/termux.properties"
    mkdir -p "$HOME/.termux"

    # Always ensure extra-keys block is correct (F12, no macro)
    # If no extra-keys at all — append clean block.
    # If extra-keys exists but broken (has 'macro:' or no 'F12') — nuke block and rewrite.
    local needs_rewrite="false"
    if ! grep -q '^[[:space:]]*extra-keys' "$props" 2>/dev/null; then
        needs_rewrite="true"
    elif grep -q 'macro' "$props" 2>/dev/null || ! grep -q 'F12' "$props" 2>/dev/null; then
        # Remove the broken extra-keys block cleanly
        sed -i '/^[[:space:]]*extra-keys/,/^[[:space:]]*\]/d' "$props" 2>/dev/null || true
        needs_rewrite="true"
    fi

    if [ "$needs_rewrite" = "true" ]; then
        cat >> "$props" << 'EXTRAKEYS'

extra-keys = [ \
  ['ESC',{key: 'F12', display: '⚙️'},'-','HOME','UP','END','PGUP'], \
  ['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN'] \
]
EXTRAKEYS
        termux-reload-settings 2>/dev/null || true
    fi
}


do_start() {
    if ! is_initialized; then
        IsFirstRun="true"
        do_init
    else
        check_and_apply_upgrades
        do_start_inner
    fi
}

do_update() {
    # ── REGION SELECTION ──
    if [ ! -f "$WORKSPACE_DIR/.mirror_region" ]; then
        clear
        echo -e "\n\e[38;5;51m\e[1m  [ REGION / MIRROR SELECTION ]\e[0m\n"
        echo -e "  \e[97m1.\e[0m CIS / Russia      \e[90m(Yandex, ghfast)\e[0m"
        echo -e "  \e[97m2.\e[0m Europe & Global   \e[90m(Debian Official, github)\e[0m"
        echo -e "  \e[97m3.\e[0m Asia              \e[90m(Tsinghua, ghproxy)\e[0m"
        echo ""
        echo -n -e "  \e[38;5;51mSelect your region (1-3) [1]:\e[0m "
        drain_stdin; read -t 15 -r m_choice || m_choice="1"
        [ -z "$m_choice" ] && m_choice="1"
        mkdir -p "$WORKSPACE_DIR"
        echo "$m_choice" > "$WORKSPACE_DIR/.mirror_region"
    fi

    clear
    echo -e "\n\n\n\n"

    # Write install script to workspace (mounted as /workspace inside Debian)
    mkdir -p "$WORKSPACE_DIR"
    cat > "$WORKSPACE_DIR/__agy_install.sh" << 'INSTALL_SCRIPT'
#!/bin/bash
set -e
export PATH="$HOME/.local/bin:$PATH"

CURRENT_STEP=0
TOTAL_STEPS=3
# Ненулевой, если хоть один шаг обновления упал (set -e ниже глушим через ||).
FAILED=0

draw_ui() {
    local msg="$1"
    local frame="$2"
    local sub="$3"
    local p=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
    local w=24
    local filled=$(( w * p / 100 ))
    local empty=$(( w - filled ))
    # Адаптация под узкие экраны: см. комментарий в draw_ui do_init.
    local _cw=$(stty size 2>/dev/null | awk '{print $2}'); [ -z "$_cw" ] && _cw=80
    local _maxsub=$((_cw - 32)); [ "$_maxsub" -lt 0 ] && _maxsub=0
    sub="${sub:0:$_maxsub}"
    
    printf "\e[s"
    printf "\e[1;1H\e[2K\n\e[2K  \e[38;5;51m\e[1m[ UPDATING ANTIGRAVITY ]\e[0m\n\e[2K  \e[38;5;45m"
    for ((j=0; j<filled; j++)); do printf "█"; done
    printf "\e[38;5;239m"
    for ((j=0; j<empty; j++)); do printf "▒"; done
    printf "\e[0m  \e[38;5;51m%3d%%\e[0m\n\e[2K\n\e[u" "$p"
    
    if [ -n "$sub" ]; then
        printf "\r\e[2K  \e[38;5;214m[ %s ]\e[0m %-23s \e[90m%s\e[0m" "$frame" "${msg:0:23}" "$sub"
    else
        printf "\r\e[2K  \e[38;5;214m[ %s ]\e[0m %s..." "$frame" "${msg:0:23}"
    fi
}

spin_run() {
    local msg="$1"; shift
    local rc=0
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    printf '\e[?25l'
    > /tmp/__step.log
    ("$@") </dev/null > /tmp/__step.log 2>&1 &
    local pid=$!
    local i=0
    local submsg=""
    while kill -0 "$pid" 2>/dev/null; do
        submsg=$(tail -c 200 /tmp/__step.log 2>/dev/null | tr '\r' '\n' | tail -n 1 | tr -dc '[:print:]' | cut -c1-22)
        draw_ui "$msg" "${frames[$((i % 10))]}" "$submsg"
        i=$((i+1))
        sleep 0.08
    done
    wait "$pid"; rc=$?
    draw_ui "$msg" "✓" ""
    if [ $rc -eq 0 ]; then
        printf '\r\e[2K  \e[38;5;46m[ ✓ ]\e[0m %s\n' "$msg"
    else
        printf '\r\e[2K  \e[38;5;196m[ ✗ ]\e[0m %s\n' "$msg"
        cat /tmp/__step.log
    fi
    printf '\e[?25h'
    return $rc
}

M_CHOICE=$(cat /workspace/.mirror_region 2>/dev/null | tr -d '\r\n' || echo 1)
[ -z "$M_CHOICE" ] && M_CHOICE=1
AGY_VERSION="1.1.26"
AGY_VERSION=$(echo "$AGY_VERSION" | tr -d '\r\n')
readonly AGY_VERSION
# STRICT PIN: V1.3.8 fe12d5b — см. VERSIONS.lock

if [ "$M_CHOICE" = "1" ]; then
    MIRRORS=(
        "https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghfast.top/https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghproxy.net/https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://gh-proxy.com/https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
    )
elif [ "$M_CHOICE" = "3" ]; then
    MIRRORS=(
        "https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghproxy.net/https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://gh-proxy.com/https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghfast.top/https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
    )
else
    MIRRORS=(
        "https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghfast.top/https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
        "https://ghproxy.net/https://github.com/google-antigravity/antigravity-cli/releases/download/${AGY_VERSION}/agy_cli_linux_arm64.tar.gz"
    )
fi

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/agy"

download_engine() {
    for url in "${MIRRORS[@]}"; do
        if curl -sS -fL --connect-timeout 5 --speed-limit 10000 --speed-time 15 --max-time 300 -o /tmp/agy_cli.tar.gz "$url"; then
            return 0
        fi
    done
    return 1
}
# Целостность архива до распаковки: раньше битый тарболл умирал только на tar.
verify_engine() {
    # ВАЖНО: без pipefail выход пайпа = выход grep; tar может напечатать имя
    # члена и всё равно упасть на EOF — вывод забираем, код tar проверяем.
    [ -s /tmp/agy_cli.tar.gz ] || return 1
    local _list
    _list=$(tar tzf /tmp/agy_cli.tar.gz 2>/dev/null) || return 1
    echo "$_list" | grep -qE '(^|/)(antigravity|agy)$' || return 1
}
_do_install() {
    local _bin=""
    for _c in /tmp/antigravity /tmp/agy /tmp/agy_cli_linux_arm64/antigravity; do
        [ -f "$_c" ] && _bin="$_c" && break
    done
    [ -z "$_bin" ] && _bin=$(find /tmp \( -name 'antigravity' -o -name 'agy' \) -type f 2>/dev/null | head -1)
    [ -n "$_bin" ] || return 1
    # Обрубки (частичная распаковка битого архива — в проде был 78КБ вместо
    # ~200МБ) — в топку, а не в bin. Пол 20МБ с запасом на будущие версии.
    local _sz; _sz=$(stat -c %s "$_bin" 2>/dev/null || echo 0)
    [ "$_sz" -ge 20000000 ] || return 1
    mv "$_bin" "$HOME/.local/bin/agy" || return 1
    chmod +x "$HOME/.local/bin/agy" 2>/dev/null || true
    rm -rf /tmp/agy_cli.tar.gz /tmp/agy_cli_linux_arm64
}
# Официальный установщик (SHA512, latest); exits early если agy уже есть → сносим.
install_official() {
    rm -f "$HOME/.local/bin/agy"
    curl -fsSL https://antigravity.google/cli/install.sh | bash || return 1
    [ -x "$HOME/.local/bin/agy" ] || return 1
    local _sz; _sz=$(stat -c %s "$HOME/.local/bin/agy" 2>/dev/null || echo 0)
    [ "$_sz" -ge 20000000 ] || return 1
}
engine_install() {
    if install_official; then return 0; fi
    echo "[*] Official installer unavailable — falling back to GitHub mirrors..."
    download_engine || return 1
    verify_engine || return 1
    rm -rf /tmp/antigravity /tmp/agy /tmp/agy_cli_linux_arm64
    tar -xzf /tmp/agy_cli.tar.gz -C /tmp/ || return 1
    _do_install || return 1
}
spin_run "Installing Antigravity Engine" engine_install || FAILED=1

if [ "$FAILED" -eq 0 ]; then
    # Маркер = sha256 свежего (непропатченного) бинаря; меняется при каждой
    # переустановке → авто-патчер гарантированно перепатчит новый бинарь.
    AGY_MARK=$(sha256sum "$HOME/.local/bin/agy" 2>/dev/null | cut -c1-16)
    echo "$AGY_MARK" > "$HOME/.local/share/agy/.version_lock"
    rm -f "$HOME/.local/share/agy/.patch_cache" 2>/dev/null || true
else
    # Не врём про успех и не пишем version_lock по битому состоянию;
    # маркер увидит хостовая часть do_update (ниже) через /workspace.
    echo -e "\n  \e[38;5;196m[FAIL] Engine update failed — version lock NOT written.\e[0m"
    echo "FAILED" > /workspace/__agy_update_failed
fi
INSTALL_SCRIPT

    # Execute inside Debian (file-based, no bash -c variable hack)
    if [ "$IN_APP_MODE" = "true" ]; then
        bash "$WORKSPACE_DIR/__agy_install.sh"
    else
        proot-distro login debian \
            --bind "$WORKSPACE_DIR:/workspace" \
            --bind "/storage/emulated/0:/phone" \
            --bind "/storage/emulated/0:/sdcard" \
            -- /bin/bash /workspace/__agy_install.sh
    fi
    rm -f "$WORKSPACE_DIR/__agy_install.sh"
    if [ -f "$WORKSPACE_DIR/__agy_update_failed" ]; then
        rm -f "$WORKSPACE_DIR/__agy_update_failed"
        echo -e "  \e[90mPress any key to continue...\e[0m"
        drain_stdin; read -rsn1
    else
        echo -e "\n  \e[38;5;46m[OK] Engine successfully updated (latest).\e[0m"
        echo -e "  \e[90mPress any key to continue...\e[0m"
        drain_stdin; read -rsn1
    fi
}

run_patcher() {
    clear
    show_header
    echo -e " ${G2}[*] Initializing Patcher...${C_RESET}"
    rm -f /root/.local/share/agy/.patch_cache "$HOME/.local/share/agy/.patch_cache" 2>/dev/null || true
    
    # Патчер поставляется ОФЛАЙН как ассет приложения
    # (open-antigravity-patcher-v1.3.8.tar в workspace), как и Debian rootfs.
    # ВАЖНО: tar НЕ сжат gzip — aapt гунзипует .gz-ассеты и срезает расширение,
    # поэтому бандл шлём как plain .tar (APK всё равно DEFLATE-ит его в zip).
    local PATCHER_DIR="open-antigravity-patcher"
    local _bundle="open-antigravity-patcher-v1.3.8.tar"

    if [ ! -f "$WORKSPACE_DIR/$PATCHER_DIR/source/main.py" ]; then
        rm -rf "${WORKSPACE_DIR:?}/$PATCHER_DIR"
        if [ -f "$WORKSPACE_DIR/$_bundle" ]; then
            echo -e " ${G_GRAY}[*] Unpacking bundled Patcher v1.3.8 (offline)...${C_RESET}"
            if [ "$IN_APP_MODE" = "true" ]; then
                mkdir -p "/workspace/$PATCHER_DIR"
                tar xf "/workspace/$_bundle" -C "/workspace/$PATCHER_DIR" 2>/dev/null || true
            else
                proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" -- /bin/bash -c "mkdir -p /workspace/$PATCHER_DIR && tar xf /workspace/$_bundle -C /workspace/$PATCHER_DIR" 2>/dev/null || true
            fi
        else
            # Dev-фолбэк (запуск вне приложения, бандла нет): строго v1.3.8.
            # GIT_TERMINAL_PROMPT=0 — не висеть на запросе логина, если репо
            # приватен/удалён, а падать сразу (бандл — основной путь).
            echo -e " ${G_GRAY}[*] Bundle not found — cloning Patcher V1.3.8 from GitHub...${C_RESET}"
            if [ "$IN_APP_MODE" = "true" ]; then
                if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch V1.3.8 https://gitlab.com/avencores/open-antigravity-patcher.git "/workspace/$PATCHER_DIR" 2>/dev/null; then
                    GIT_TERMINAL_PROMPT=0 git clone https://gitlab.com/avencores/open-antigravity-patcher.git "/workspace/$PATCHER_DIR" 2>/dev/null \
                        && git -C "/workspace/$PATCHER_DIR" checkout fe12d5b 2>/dev/null || true
                fi
            else
                proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" -- /bin/bash -c '
                    export GIT_TERMINAL_PROMPT=0
                    repo="https://gitlab.com/avencores/open-antigravity-patcher.git"
                    if ! git clone --depth 1 --branch V1.3.8 "$repo" /workspace/open-antigravity-patcher 2>/dev/null; then
                        git clone "$repo" /workspace/open-antigravity-patcher 2>/dev/null \
                            && git -C /workspace/open-antigravity-patcher checkout fe12d5b 2>/dev/null || true
                    fi' 2>/dev/null || true
            fi
        fi
    fi

    if [ -f "$WORKSPACE_DIR/$PATCHER_DIR/source/main.py" ]; then
        echo -e "\r\e[2K  \e[38;5;46m[ ✓ ] Patcher v1.3.8 ready\e[0m"
        if [ "$IN_APP_MODE" = "true" ]; then
            export TERM=xterm-256color
            python3 "/workspace/$PATCHER_DIR/source/main.py"
        else
            proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" -- /bin/bash -c "export TERM=xterm-256color; python3 /workspace/$PATCHER_DIR/source/main.py"
        fi
    else
        echo -e " ${G_RED}[!] Failed to load patcher.${C_RESET}"
        sleep 2
    fi
}

do_toggle_update_lock() {
    [ -f "$PROXY_CONFIG" ] && source "$PROXY_CONFIG"
    if [ "$UPDATE_LOCK" = "false" ]; then UPDATE_LOCK="true"; else UPDATE_LOCK="false"; fi
    # Персист в PROXY_CONFIG (добавляем ключ, если его там ещё нет).
    if grep -q '^UPDATE_LOCK=' "$PROXY_CONFIG" 2>/dev/null; then
        sed -i "s/^UPDATE_LOCK=.*/UPDATE_LOCK=\"$UPDATE_LOCK\"/" "$PROXY_CONFIG"
    else
        echo "UPDATE_LOCK=\"$UPDATE_LOCK\"" >> "$PROXY_CONFIG"
    fi
    # Флаг для скриптов внутри контейнера (start-agy.sh / check_and_patch.py).
    mkdir -p "$WORKSPACE_DIR"
    echo "$UPDATE_LOCK" > "$WORKSPACE_DIR/.update_lock"

    clear
    show_header
    if [ "$UPDATE_LOCK" = "true" ]; then
        echo -e " ${G_GREEN}[OK] Update Lock ENABLED — auto-updater blocked, binary pinned & patched.${C_RESET}"
    else
        echo -e " ${G_WARN}[!] Update Lock DISABLED — Antigravity may self-update (patch re-applies on next launch).${C_RESET}"
    fi
    # Если сессия активна (overlay) — применяем прямо сейчас: check_and_patch.py
    # читает .update_lock и либо глушит+лочит, либо разлочивает+возвращает URL.
    if [ "$IN_APP_MODE" = "true" ] && [ -f /workspace/check_and_patch.py ]; then
        echo -e " ${G_GRAY}[*] Applying...${C_RESET}"
        python3 /workspace/check_and_patch.py 2>/dev/null || true
    fi
    echo -e " ${G_GRAY}Press any key to continue...${C_RESET}"
    drain_stdin; read -rsn1
}

do_configure_proxy() {
    while true; do
        [ -f "$PROXY_CONFIG" ] && source "$PROXY_CONFIG"
        local pStatus="OFF"
        [ "$USE_PROXY" = "true" ] && pStatus="ON"
        
        local opts=(
            "1. Toggle Proxy           [ Current: $pStatus ]"
            "2. Switch Proxy Protocol  [ Current: ${PROXY_TYPE:-xray} ]"
            "3. Import VLESS / Hy2 URL [ Paste Link ]"
            "0. Back"
        )
        
        invoke_menu "NETWORK & PROXY" "${opts[@]}"
        local sel=$?
        
        if [ "$sel" -eq 255 ] || [ "$sel" -eq 3 ]; then break; fi
        
        if [ "$sel" -eq 0 ]; then
            if [ "$USE_PROXY" = "true" ]; then USE_PROXY="false"; else USE_PROXY="true"; fi
            sed -i "s/USE_PROXY=.*/USE_PROXY=\"$USE_PROXY\"/" "$PROXY_CONFIG"
            if [ "$IN_APP_MODE" = "true" ]; then
                restart_proxy_core
                echo -e " ${G_GRAY}Press any key to continue...${C_RESET}"
                drain_stdin; read -rsn1
                local rOpts=("1. ⚡ Restart Session Now" "2. ↩ Later")
                invoke_menu "RESTART SESSION FOR PROXY?" "${rOpts[@]}"
                if [ $? -eq 0 ]; then restart_session; fi
            fi
        elif [ "$sel" -eq 1 ]; then
            local p_opts=("1. xray (VLESS/Reality)" "2. hysteria2 (UDP High Speed)" "3. socks5" "4. http" "0. Back")
            invoke_menu "SELECT PROTOCOL" "${p_opts[@]}"
            local p_sel=$?
            if [ "$p_sel" -eq 0 ]; then PROXY_TYPE="xray"
            elif [ "$p_sel" -eq 1 ]; then PROXY_TYPE="hysteria2"
            elif [ "$p_sel" -eq 2 ]; then PROXY_TYPE="socks5"
            elif [ "$p_sel" -eq 3 ]; then PROXY_TYPE="http"
            fi
            sed -i "s/PROXY_TYPE=.*/PROXY_TYPE=\"$PROXY_TYPE\"/" "$PROXY_CONFIG"
            if [ "$IN_APP_MODE" = "true" ]; then
                restart_proxy_core
                echo -e " ${G_GRAY}Press any key to continue...${C_RESET}"
                drain_stdin; read -rsn1
                local rOpts=("1. ⚡ Restart Session Now" "2. ↩ Later")
                invoke_menu "RESTART SESSION FOR PROXY?" "${rOpts[@]}"
                if [ $? -eq 0 ]; then restart_session; fi
            fi
        elif [ "$sel" -eq 2 ]; then
            clear
            show_header
            echo -e " ${G2}${C_BOLD}[ IMPORT PROXY URL ]${C_RESET}"
            echo -e " ${G_WHITE}Paste your vless:// or hysteria2:// link below:${C_RESET}"
            echo ""
            echo -ne " ${G_GREEN}> ${C_RESET}"
            read -r import_link
            if [ -n "$import_link" ]; then
                echo "$import_link" > "$WORKSPACE_DIR/vless_link_temp.txt"
                local import_success="false"
                if [ "$IN_APP_MODE" = "true" ]; then
                    if python3 /workspace/generate_proxy_config.py /workspace/vless_link_temp.txt "$XRAY_PORT" /workspace >/dev/null 2>&1; then import_success="true"; fi
                else
                    if proot-distro login debian --bind "$WORKSPACE_DIR:/workspace" --bind "/storage/emulated/0:/phone" --bind "/storage/emulated/0:/sdcard" -- /usr/bin/python3 /workspace/generate_proxy_config.py /workspace/vless_link_temp.txt "$XRAY_PORT" /workspace >/dev/null 2>&1; then import_success="true"; fi
                fi
                
                if [ "$import_success" = "true" ]; then
                    mv "$WORKSPACE_DIR/vless_link_temp.txt" "$WORKSPACE_DIR/vless_link.txt"
                    USE_PROXY="true"
                    sed -i 's/USE_PROXY=.*/USE_PROXY="true"/' "$PROXY_CONFIG"
                    if [ -f "$WORKSPACE_DIR/proxy_engine.txt" ]; then
                        local eng; eng=$(cat "$WORKSPACE_DIR/proxy_engine.txt" 2>/dev/null)
                        if [ "$eng" = "hysteria" ]; then PROXY_TYPE="hysteria2"; elif [ "$eng" = "xray" ]; then PROXY_TYPE="xray"; fi
                        sed -i "s/PROXY_TYPE=.*/PROXY_TYPE=\"$PROXY_TYPE\"/" "$PROXY_CONFIG"
                    fi
                    echo -e "\n ${G_GREEN}[OK] URL imported successfully! (${PROXY_TYPE})${C_RESET}"
                    if [ "$IN_APP_MODE" = "true" ]; then
                        restart_proxy_core
                        echo -e " ${G_GRAY}Press any key to continue...${C_RESET}"
                        drain_stdin; read -rsn1
                        local rOpts=("1. ⚡ Restart Session Now" "2. ↩ Later")
                        invoke_menu "RESTART SESSION FOR PROXY?" "${rOpts[@]}"
                        if [ $? -eq 0 ]; then restart_session; fi
                    fi
                else
                    rm -f "$WORKSPACE_DIR/vless_link_temp.txt"
                    echo -e "\n ${G_RED}[!] Failed to parse URL.${C_RESET}"
                    echo -e " ${G_GRAY}Press any key to continue...${C_RESET}"
                    drain_stdin; read -rsn1
                fi
            fi
        fi
    done
}

do_directory_picker() {
    while true; do
        local opts=("1. 📂 Browse Workspace      [ Isolated ]" "2. 🗄️ Browse Full System    [ Full Access ]" "0. ↩ Back")
        invoke_menu "DIRECTORY" "${opts[@]}"
        local choice=$?
        if [ "$choice" -eq 255 ] || [ "$choice" -eq 2 ]; then break; fi
        
        if [ "$choice" -eq 0 ]; then
            # In-app (inside Debian): browse from /workspace
            # Normal (Termux): browse from $WORKSPACE_DIR on Android
            local ws_start
            if [ "$IN_APP_MODE" = "true" ]; then
                ws_start="/workspace"
            else
                ws_start="$WORKSPACE_DIR"
                [ ! -d "$ws_start" ] && ws_start="/storage/emulated/0/AntigravityWorkspace"
                [ ! -d "$ws_start" ] && ws_start="/storage/emulated/0"
            fi
            invoke_filebrowser "$ws_start" "WORKSPACE"
            if [ -n "$SELECTED_PATH" ]; then
                local norm_path
                if [ "$IN_APP_MODE" = "true" ]; then
                    # /workspace/sub → /sdcard/AntigravityWorkspace/sub (for .last_dir)
                    norm_path="$WORKSPACE_DIR${SELECTED_PATH#/workspace}"
                else
                    norm_path="${SELECTED_PATH//\/storage\/emulated\/0\//\/sdcard\/}"
                fi
                echo "$norm_path" > "$WORKSPACE_DIR/.last_dir"
                StorageMode="WORKSPACE ONLY"
                SELECTED_PATH="$norm_path"
                break
            fi
        elif [ "$choice" -eq 1 ]; then
            # In-app (inside Debian): browse from /phone (bound to /storage/emulated/0)
            # Normal (Termux): browse from /storage/emulated/0 directly
            local fs_start
            if [ "$IN_APP_MODE" = "true" ]; then
                fs_start="/phone"
                [ ! -d "$fs_start" ] && fs_start="/sdcard"
            else
                fs_start="/storage/emulated/0"
                [ ! -d "$fs_start" ] && fs_start="/sdcard"
            fi
            invoke_filebrowser "$fs_start" "FULL SYSTEM"
            if [ -n "$SELECTED_PATH" ]; then
                local norm_path
                if [ "$IN_APP_MODE" = "true" ]; then
                    # /phone/sub → /sdcard/sub (for .last_dir)
                    norm_path="/sdcard${SELECTED_PATH#/phone}"
                else
                    norm_path="${SELECTED_PATH//\/storage\/emulated\/0\//\/sdcard\/}"
                fi
                echo "$norm_path" > "$WORKSPACE_DIR/.last_dir"
                StorageMode="FULL SYSTEM"
                SELECTED_PATH="$norm_path"
                break
            fi
        fi
    done
    
    if [ "$IN_APP_MODE" = "true" ] && [ -n "$SELECTED_PATH" ]; then
        # Translate stored path to Debian path for display
        local display_path="$SELECTED_PATH"
        if [[ "$display_path" == "$WORKSPACE_DIR"* ]]; then
            display_path="/workspace${display_path#$WORKSPACE_DIR}"
        elif [[ "$display_path" == "/sdcard"* ]]; then
            display_path="/phone${display_path#/sdcard}"
        fi
        local restartOpts=(
            "1. ⚡ Restart Session Now"
            "2. ↩ Later (Return to Menu)"
        )
        invoke_menu "RESTART SESSION?" "${restartOpts[@]}"
        local rChoice=$?
        if [ "$rChoice" -eq 0 ]; then
            restart_session
        fi
    fi
}

do_shell() {
    clear
    local -a EXTRA_BINDS=()
    [ -d "$WORKSPACE_DIR" ] && EXTRA_BINDS+=(--bind "$WORKSPACE_DIR:/workspace")
    [ -d "/sdcard" ]        && EXTRA_BINDS+=(--bind "/storage/emulated/0:/phone" --bind "/storage/emulated/0:/sdcard")
    echo -e " ${G2}[*] Entering Debian shell...${C_RESET}"
    proot-distro login debian "${EXTRA_BINDS[@]}" --no-kill-on-exit
}

do_reset() {
    clear
    show_header
    echo -e " ${G_RED}${C_BOLD}[!] WARNING [!]${C_RESET}"
    echo -e " ${G_WHITE}This will DELETE the Debian container and ALL settings!${C_RESET}"
    echo -e " ${G_WHITE}Type 'yes' to confirm:${C_RESET} "
    drain_stdin; read -r c
    if [ "$c" = "yes" ]; then
        proot-distro remove debian 2>/dev/null || true
        rm -rf "$WORKSPACE_DIR"
        echo -e " ${G_GREEN}[OK] Environment wiped. Restart the app to reinstall.${C_RESET}"
        exit 0
    fi
}

# --- Main Entry Point ---

! is_initialized && IsFirstRun="true"

main_loop() {
    if ! bootloader_timer; then
        clear
        echo -e "${G2}[*] Auto-launching Antigravity CLI...${C_RESET}"
        # do_start_inner заканчивается exec и не возвращается — цикл вокруг
        # него (и флаг .restart_requested) недостижим. Прямой вызов.
        do_start
        exit 0
    fi

    while true; do
        local W=$(get_console_width)
        local isMobile="false"
        if [ $((W - 4)) -lt 68 ]; then isMobile="true"; fi

        local lockBadge="ON"; [ "${UPDATE_LOCK:-true}" = "false" ] && lockBadge="OFF"

        local mainOptions=()
        if [ "$isMobile" = "true" ]; then
            if [ "$IN_APP_MODE" = "true" ]; then
                mainOptions=(
                    "1. 📂 Change Directory"
                    "2. 🌐 Network & Proxy"
                    "3. 🔄 Update Antigravity"
                    "4. 🛠️ Run Patcher"
                    "5. 🔒 Update Lock [ $lockBadge ]"
                    "6. 🗙 Restart Session"
                    "0. ↩ Close Settings"
                )
            else
                mainOptions=(
                    "1. Launch Antigravity"
                    "2. Select Workspace"
                    "3. Update CLI"
                    "4. Network & Proxy"
                    "5. Run Patcher"
                    "6. Update Lock [ $lockBadge ]"
                    "7. Debian Shell"
                    "0. Exit"
                )
            fi
        else
            if [ "$IN_APP_MODE" = "true" ]; then
                mainOptions=(
                    "1. 📂 Change Working Directory"
                    "2. 🌐 Network & Proxy Settings"
                    "3. 🔄 Update Antigravity CLI"
                    "4. 🛠️ Run Antigravity Patcher"
                    "5. 🔒 Update Lock [ $lockBadge ]"
                    "6. 🗙 Restart Antigravity Session"
                    "0. ↩ Return to App (Close Overlay)"
                )
            else
                mainOptions=(
                    "1. Launch Antigravity CLI"
                    "2. Select Workspace / Storage Mode"
                    "3. Update Antigravity CLI"
                    "4. Network & Proxy Settings"
                    "5. Run Antigravity Patcher"
                    "6. Update Lock [ $lockBadge ]"
                    "7. Enter Debian Shell"
                    "0. Exit Manager"
                )
            fi
        fi
        
        local title="MAIN MENU"
        if [ "$IN_APP_MODE" = "true" ]; then title="SETTINGS OVERLAY"; fi

        invoke_menu "$title" "${mainOptions[@]}"
        local selection=$?
        
        if [ "$selection" -eq 255 ] || ([ "$selection" -eq 6 ] && [ "$IN_APP_MODE" = "true" ]); then
            clear
            echo -e "${G2}[*] Closing settings overlay. Returning to Antigravity...${C_RESET}"
            break
        elif [ "$selection" -eq 7 ] && [ "$IN_APP_MODE" = "false" ]; then
            clear
            echo -e "${G2}[*] Exiting AgyCli Manager. Goodbye!${C_RESET}"
            exit 0
        fi

        if [ "$IN_APP_MODE" = "true" ]; then
            case "$selection" in
                0) do_directory_picker ;;
                1) do_configure_proxy ;;
                2) do_update ;;
                3) run_patcher ;;
                4) do_toggle_update_lock ;;
                5) restart_session ;;
            esac
        else
            case "$selection" in
                0)
                    do_start
                    ;;
                1) do_directory_picker ;;
                2) do_update ;;
                3) do_configure_proxy ;;
                4) run_patcher ;;
                5) do_toggle_update_lock ;;
                6) do_shell ;;
            esac
        fi
    done
}

main_loop
