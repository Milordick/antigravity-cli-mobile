<p align="center">
  <img src="logo.png" width="140" height="140" alt="Antigravity CLI Mobile Logo"/>
</p>

<h1 align="center">antigravity-cli-mobile</h1>

<p align="center">
  <b>Android terminal client for the Antigravity CLI — fully automated.</b>
</p>

<p align="center">
  <a href="https://github.com/Milordick/antigravity-cli-mobile/releases"><img src="https://img.shields.io/github/v/release/Milordick/antigravity-cli-mobile?color=6e40c9&logo=github&style=for-the-badge&label=Latest+Release" alt="GitHub release"/></a>
  <a href="https://www.gnu.org/licenses/gpl-3.0"><img src="https://img.shields.io/badge/License-GPL%20v3-blue.svg?style=for-the-badge" alt="License"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Platform-Android%207.0%2B-brightgreen.svg?style=for-the-badge" alt="Platform"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Architecture-ARM64%20%7C%20ARMv7%20%7C%20x86%20%7C%20x86__64-orange.svg?style=for-the-badge" alt="Architectures"/></a>
  <a href="https://pay.cloudtips.ru/p/0ef570e5"><img src="https://img.shields.io/badge/Support-Donate-ff5f5f.svg?style=for-the-badge&logo=heart" alt="Donate"/></a>
</p>

---

## 🌍 Language / Язык

- [English](#english)
- [Русский](#русский)

---

## English

**antigravity-cli-mobile** is a fully self-contained Android terminal application built to deploy, configure, and run the **Antigravity CLI** on mobile devices — right out of the box, with zero user configuration required.

It is built on a deep fork of the open-source **[Termux](https://github.com/termux/termux-app)** terminal emulator, with a significant layer of custom engineering on top: an embedded Debian Bookworm Linux container, a smart Bash orchestration system, an on-demand proxy engine loader, automatic region-bypass patching, and hardware-compatibility fixes — all woven together into a single APK that just works.

### 🔗 Credits & Open-Source Attribution

This project stands on the shoulders of giants:

| Component | Author | Role |
|---|---|---|
| [Termux App](https://github.com/termux/termux-app) | Termux Team | Core terminal emulator, bootstrap installer, proot-distro runtime |
| [open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher) | AvenCores | Binary patcher that removes the regional eligibility gate from the AGY CLI |
| [Xray-core](https://github.com/XTLS/Xray-core) | XTLS Project | VLESS/XTLS Reality proxy engine (downloaded on-demand) |
| Hysteria 2 | Hysteria Project | UDP-based proxy engine (downloaded on-demand) |

---

## 📦 Releases & Downloads

Pre-compiled APK builds are published in the **[Releases](https://github.com/Milordick/antigravity-cli-mobile/releases)** tab.

> Install the **universal** build unless you have a specific reason to use an architecture-specific one. It works on all devices.

### Available APK Variants

| Variant | File suffix | Target CPU | When to use |
|---|---|---|---|
| **Universal** ✅ | `_universal.apk` | All (arm64 + arm32 + x86 + x86_64) | **Recommended for all users** |
| ARM64 | `_arm64-v8a.apk` | 64-bit ARM (most modern phones) | Smaller size, same performance |
| ARMv7 | `_armeabi-v7a.apk` | 32-bit ARM (older phones, 2013–2017) | For old/budget devices only |
| x86_64 | `_x86_64.apk` | 64-bit Intel/AMD (emulators, Chromebooks) | Android emulators, x86 tablets |
| x86 | `_x86.apk` | 32-bit Intel (legacy emulators) | Very old emulators only |

---

## 🚀 Feature Deep-Dive

### 1. ⚡ Pre-Cached Debian Bootstrap

Installing a full Linux distribution inside `proot-distro` normally requires downloading a 200+ MB rootfs tarball from GitHub. On mobile networks, in regions with unstable connectivity, or in airplane mode — this simply fails.

**Our solution:**

- A pre-compiled **Debian Bookworm (ARM64)** rootfs (~42 MB compressed) is **bundled directly inside the APK** as an asset. *(Note: Offline bootstrap is optimized for ARM64/aarch64 devices. Other architectures like x86_64 or armv7 will automatically fallback to standard online download).*
- At first launch, `TermuxInstaller.java` extracts the Termux bootstrap zip, then immediately copies the Debian rootfs into the exact cache path that `proot-distro` expects (`/data/.../var/lib/proot-distro/dlcache/`).
- `proot-distro install debian` detects the pre-cached file and completes installation **without a single network request**.
- **Total time from first launch to a running Debian shell: under 30 seconds**, thanks to pre-cached rootfs.

---

### 2. 🔒 Double-Bootstrap Race-Condition Fix

Android's storage permission dialog introduces a destructive race condition:

1. App launches → `setupBootstrapIfNeeded()` starts an extraction thread.
2. The permission dialog **pauses the Activity** → the terminal service reconnects.
3. `onServiceConnected()` fires again → a **second** extraction thread spawns.
4. Both threads concurrently wipe and rewrite the prefix directory, corrupting symlinks → `"Unable to install bootstrap"` crash.

**Fix:** A `static synchronized` boolean gate (`mIsInstallingBootstrap`) in `TermuxInstaller.java` ensures the bootstrap runs exactly once, cleanly.

---

### 3. 🌐 On-Demand Proxy Engines (Xray & Hysteria 2)

Proxy binaries are **not bundled** in the APK. The `start-agy.sh` launcher inside the Debian container checks for the binary **only when the user activates the proxy**:

- If missing → downloads the correct architecture variant automatically (`arm64-v8a`, `arm32-v7a`, `64`...).
- If present → starts the proxy immediately, no download needed.

---

### 4. 🔑 One-Click Proxy URL Import (VLESS & Hysteria 2)

The built-in Python parser (`generate_proxy_config.py`) accepts a raw proxy share link and produces a native JSON config:

- **`vless://`** — Parses UUID, host, port, security mode (Reality / TLS / none), flow, WebSocket path, gRPC service name, Reality public key + shortId. Outputs a full `xray_config.json` with dual SOCKS5 + HTTP inbounds.
- **`hysteria2://` / `hy2://`** — Parses auth token, server address, obfuscation, TLS SNI, insecure flag. Outputs `hysteria_config.json`.

All configs persist in `/sdcard/AntigravityWorkspace/` — accessible from both Android and the Debian container.

---

### 5. 🛡️ Automatic AGY Binary Patcher (Region Bypass)

The AGY CLI binary contains eligibility checks blocking use outside specific regions. The app integrates a heavily modified **[open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher)** workflow with pinned version execution:

- `check_and_patch.py` is copied to the workspace on every launch.
- Patcher repository is pinned to a stable commit (`b9a01e8`) to prevent upstream changes from breaking the application.
- Uses a custom **multi-gate parser** (injecting both Gate 1 and Gate 2 patches on Linux ARM64 ELF) to completely bypass both backend eligibility checks and UI-level block layouts.
- If already patched → skips everything silently.

---

### 6. 🧩 Persistent Session & Workspace Tracking

A `PROMPT_COMMAND` hook in `/etc/bash.bashrc` tracks the user's working directory on every prompt. On next launch, `start-agy.sh` restores the exact directory automatically — making it feel like a persistent desktop session.

---

### 7. ⌨️ Universal ASCII Arrow Key Compatibility

Custom Android ROM fonts (e.g. **Infinix XOS**, **TECNO HiOS**, **itel**) fail to render Unicode arrows (`←`, `→`, `↑`, `↓`), showing broken characters like `ij`, `Ы`, `я` instead.

**Fix:** All toolbar arrow keys are replaced with ASCII art equivalents (`<-`, `->`, `^`, `v`) — works on 100% of devices.

---

### 8. 🔄 3-Second Autolaunch Menu

On startup: auto-launches in 3 seconds if initialized, or auto-starts full setup on first run. Press any key to open the interactive menu:

1. 🚀 Launch Antigravity CLI
2. 🔄 Update Antigravity CLI
3. 🌐 Network & Proxy Settings
4. 🩹 Run Antigravity Patcher
5. 🐚 Open raw Debian shell
6. 🗑️ Reset sandbox (full wipe)

---

### 9. 🏥 Auto-Healing Container

On every launch, the app verifies all required Debian packages (`python3`, `git`, `python3-packaging`) and silently reinstalls any missing ones — recovering broken environments without user intervention.

---

## 🚀 Quick Start Guide

### Step 1 — Install the APK

Download the latest `termux-app_apt-android-7-release_universal.apk` from the **[Releases](https://github.com/Milordick/antigravity-cli-mobile/releases)** tab and install it. Android may ask you to allow installation from unknown sources — this is expected.

> ⚠️ **Important:** Do NOT install from Google Play. This is a standalone side-loaded app.

---

### Step 2 — First Launch (Fully Automatic)

On first launch the app runs a **fully automated setup sequence**. No input required — just watch it go:

```
[ First Launch Flow ]

  App opens
    └── Storage permission dialog appears
          └── Tap ALLOW
                └── Bootstrap installs (Termux base tools)
                      └── Debian Bookworm unpacked from APK assets (~30 sec)
                            └── apt-get installs: python3, git, curl, ca-certificates...
                                  └── Antigravity CLI installed inside Debian
                                        └── ✅ Ready — AGY shell opens automatically
```

After setup completes, the Antigravity CLI starts automatically inside the Debian container.

> 💡 **No internet required** for the Debian rootfs — it's bundled in the APK. Internet is only needed for `apt-get` package installation and the AGY CLI installer.

---

### Step 3 — Subsequent Launches (3-Second Autolaunch)

Every time you open the app after setup:

```
App opens → Shows status banner (Workspace path, Proxy status, Last directory)
         → "Launching in 3 seconds..."
         → [Press any key] → Opens the interactive menu
         → [Wait 3 seconds] → AGY CLI starts automatically
```

---

### Step 4 — Configure a Proxy (Optional)

If you need a proxy to reach certain resources:

1. Press any key at the 3-second countdown to open the **Main Menu**.
2. Choose **`3) Network & Proxy settings`**.
3. Choose **`2) Set Proxy Type`** → select `xray` (VLESS/Reality) or `hysteria2`.
4. Choose **`3) Import URL`** → paste your `vless://...` or `hysteria2://...` link.
5. The app parses the link, generates the config, and **automatically enables the proxy**.
6. Choose **`0) Back`** → **`1) Launch Antigravity CLI`** — proxy is now active.

---

### Step 5 — Run the Patcher (If Needed)

If AGY shows a regional eligibility screen:

1. Open the **Main Menu** → **`4) Run Antigravity Patcher`**.
2. The patcher auto-downloads if not present, patches the AGY binary, and restarts it.
3. Done — no eligibility screen anymore.

---

## 📋 Main Menu Reference

```
╔══════════════════════════════════════════╗
║     ANTIGRAVITY CLI  //  DEBIAN SANDBOX  ║
╚══════════════════════════════════════════╝

  Workspace : /sdcard/AntigravityWorkspace
  Proxy     : ON (xray)          ← current proxy status
  Last dir  : /workspace/myproject

  1) Launch Antigravity CLI      ← Start AGY in Debian container
  2) Update Antigravity CLI      ← Re-run official install script
  3) Network & Proxy settings    ← Full proxy configuration submenu
  4) Run Antigravity Patcher     ← Bypass regional eligibility check
  5) Open Debian shell           ← Raw bash inside Debian container
  6) Reset sandbox               ← ⚠️ Wipes EVERYTHING (Debian + workspace)
  7) Exit
```

---

## ⚙️ Network & Proxy Settings — Full Reference

Access via **Main Menu → 3**.

```
  Network & Proxy Settings
  ========================

  1) Toggle proxy           [ ON / OFF ]       ← Enable or disable the proxy
  2) Set Proxy Type         [ xray ]           ← Choose proxy engine
  3) Import URL             [ VLESS or Hysteria 2 ]
  4) Manual Config Settings [ Server: ... ]   ← Edit fields manually
  0) Back to Main Menu
```

### Option 2 — Set Proxy Type

| Choice | Engine | Protocol | Best For |
|:---:|---|---|---|
| `1` | **xray** | VLESS + XTLS-Reality / TLS | Standard V2Ray/Xray servers |
| `2` | **hysteria2** | UDP (QUIC-based) | High-speed, lossy networks |
| `3` | **socks5** | SOCKS5 | External SOCKS5 proxy |
| `4` | **http** | HTTP CONNECT | Corporate/external HTTP proxy |

### Option 3 — Import URL

Paste a full proxy share link. Supported formats:

| Protocol | Example |
|---|---|
| VLESS Reality | `vless://uuid@host:443?security=reality&flow=xtls-rprx-vision&pbk=KEY&sid=ID&sni=SNI` |
| VLESS TLS | `vless://uuid@host:443?security=tls&sni=SNI` |
| Hysteria 2 | `hysteria2://password@host:443?sni=SNI` |
| Hysteria 2 + obfs | `hysteria2://pass@host:443?sni=SNI&obfs=salamander&obfs-password=OBF` |

On success: config is saved, proxy is auto-enabled. On error: the raw link is shown for troubleshooting.

### Option 4 — Manual Config Settings (xray)

Instead of a URL, you can fill in individual fields:

| Field | Description |
|---|---|
| **Server** | Hostname or IP of the proxy server |
| **Port** | Server port (typically 443) |
| **UUID** | User ID |
| **Flow** | `xtls-rprx-vision` (Reality) or blank |
| **SNI** | Server Name Indication for TLS |
| **PubKey** | Reality public key |
| **ShortID** | Reality short ID (leave blank if none) |

For **Hysteria 2** manual config, the fields map to: Server, Port, Auth/Password, SNI, Obfs Type (`salamander` or blank), Obfs Password.

> 💡 Leave any field blank to keep the existing value. Type `none` to clear an optional field.

---

## 💡 Tips, Quirks & Known Behaviours

### 🔋 Background Behaviour
- The Debian container runs as a **foreground process** tied to the terminal session. Closing the app stops AGY and the proxy.
- To keep a long-running task alive, use `nohup command &` inside the Debian shell.

### 🌐 Proxy Environment Variables
When the proxy is enabled, these variables are set automatically inside Debian:
```bash
export HTTP_PROXY="http://127.0.0.1:10809"
export HTTPS_PROXY="http://127.0.0.1:10809"
export ALL_PROXY="http://127.0.0.1:10809"
```
This makes `apt`, `curl`, `pip`, `npm`, and any other CLI tool route through the proxy without extra configuration.

### 📁 Workspace Location
All persistent data lives in `/sdcard/AntigravityWorkspace/` on the Android side, mounted as `/workspace` inside Debian:

| File | Purpose |
|---|---|
| `proxy_config.sh` | Proxy on/off toggle and type |
| `vless_settings.sh` | Manual VLESS fields |
| `vless_link.txt` | Last imported proxy URL |
| `xray_config.json` | Generated Xray config |
| `hysteria_config.json` | Generated Hysteria2 config |
| `proxy_engine.txt` | Active engine (`xray` or `hysteria`) |
| `.last_dir` | Last working directory in Debian |
| `check_and_patch.py` | Auto-patcher script |
| `open-antigravity-patcher/` | Patcher source (cloned on first use) |

### ⚠️ Reset Sandbox
**Menu → 6 → type `yes`** performs a complete wipe:
- Deletes the entire Debian container (`proot-distro remove debian`)
- Deletes the entire `/sdcard/AntigravityWorkspace/` folder
- On next launch, the full first-run setup runs again from scratch

### 🔄 Updating AGY
**Menu → 2** runs `curl -fsSL https://antigravity.google/cli/install.sh | bash` inside Debian. This updates the AGY binary to the latest version. After update, re-run the patcher if needed (Menu → 4).

### 🐚 Raw Debian Shell
**Menu → 5** drops you into a plain `bash` shell inside the Debian container with `/workspace` and `/sdcard` mounted. Useful for manual debugging, installing packages, or advanced configuration.

---

## 💖 Support / Donation

If you find this project useful, you can support its development by donating via CloudTips:

👉 **[Support via CloudTips](https://pay.cloudtips.ru/p/0ef570e5)**

---

## 🏗️ Building from Source

```bash
git clone https://github.com/Milordick/antigravity-cli-mobile.git
cd antigravity-cli-mobile

export TERMUX_SPLIT_APKS_FOR_RELEASE_BUILDS="0"
./gradlew assembleRelease
# Output: app/build/outputs/apk/release/termux-app_apt-android-7-release_universal.apk
```

**Requirements:** Android SDK with NDK, JDK 11+, Gradle 7+

---

## 📁 Project Structure

```
termux-app/
├── app/src/main/
│   ├── assets/
│   │   ├── agy-manager.sh              ← Main orchestration script (875 lines)
│   │   ├── generate_proxy_config.py    ← VLESS/Hysteria2 URL → JSON parser
│   │   ├── check_and_patch.py          ← Auto-patcher for AGY binary
│   │   └── debian-bookworm-aarch64-pd-v4.17.3.tar.xz  ← Bundled Debian rootfs (~42MB)
│   └── java/com/termux/app/
│       └── TermuxInstaller.java        ← Bootstrap installer + pre-cached Debian seeding
├── terminal-emulator/                  ← VT100/VT220 emulator library
├── terminal-view/                      ← Android View rendering the terminal
└── termux-shared/                      ← Shared utilities, constants, file ops
```

---

## 📄 License

This project is licensed under the **[GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html)**.

### License Breakdown

| Component | License | Notes |
|---|---|---|
| `app/` (this project's custom code) | GPL v3.0 | Original automation, scripts, and modifications |
| `terminal-emulator/`, `terminal-view/` | Apache 2.0 | From [Android-Terminal-Emulator](https://github.com/jackpal/Android-Terminal-Emulator) |
| `termux-shared/` | MIT / Apache 2.0 | See [`termux-shared/LICENSE.md`](termux-shared/LICENSE.md) |
| Termux bootstrap packages | GPL v3.0 | From [termux/termux-packages](https://github.com/termux/termux-packages) |
| Debian Bookworm rootfs (bundled asset) | Various (DFSG-compatible) | Standard Debian package licenses apply |
| [open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher) | As-is (upstream) | Used as a runtime dependency, cloned on-demand |

By using this application you accept the terms of all applicable licenses listed above.

---
---

## Русский

**antigravity-cli-mobile** — это самодостаточное Android-приложение-терминал для развёртывания, настройки и запуска **Antigravity CLI** на мобильных устройствах. С автоматической установкой и без ручной настройки.

Построено на базе глубокого форка **[Termux](https://github.com/termux/termux-app)** с обширным слоем собственной инженерии: встроенный контейнер Debian Bookworm, умная система Bash-скриптов, загрузчик прокси-ядер по требованию, автоматическое снятие региональной блокировки и исправления совместимости — всё в одном APK.

### 🔗 Благодарности и атрибуция

| Компонент | Автор | Роль |
|---|---|---|
| [Termux App](https://github.com/termux/termux-app) | Команда Termux | Ядро терминального эмулятора, bootstrap-установщик, среда proot-distro |
| [open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher) | AvenCores | Бинарный патчер для снятия региональной проверки AGY CLI |
| [Xray-core](https://github.com/XTLS/Xray-core) | XTLS Project | Прокси-ядро VLESS/XTLS Reality (загружается по требованию) |
| Hysteria 2 | Hysteria Project | UDP-прокси (загружается по требованию) |

---

## 📦 Релизы и загрузки

Готовые APK-файлы публикуются в разделе **[Releases](https://github.com/Milordick/antigravity-cli-mobile/releases)**.

> Устанавливай **universal** сборку, если нет конкретной причины выбирать другую. Работает на всех устройствах.

### Варианты APK

| Вариант | Суффикс файла | Целевой CPU | Когда использовать |
|---|---|---|---|
| **Universal** ✅ | `_universal.apk` | Все (arm64 + arm32 + x86 + x86_64) | **Рекомендуется всем** |
| ARM64 | `_arm64-v8a.apk` | 64-бит ARM (большинство современных телефонов) | Меньший размер, та же производительность |
| ARMv7 | `_armeabi-v7a.apk` | 32-бит ARM (старые телефоны, 2013–2017) | Только для старых/бюджетных устройств |
| x86_64 | `_x86_64.apk` | 64-бит Intel/AMD (эмуляторы, Chromebook) | Эмуляторы Android, x86-планшеты |
| x86 | `_x86.apk` | 32-бит Intel (старые эмуляторы) | Только очень старые эмуляторы |

---

## 🚀 Подробное описание ключевых функций

### 1. ⚡ Предварительно кэшированная установка Debian (Pre-Cached Bootstrap)

Стандартная установка через `proot-distro` требует скачивания образа 200+ МБ с GitHub. Без интернета — не работает.

**Наше решение:**

- Предскомпилированный rootfs **Debian Bookworm (ARM64)** (~42 МБ) **встроен прямо в APK**. *(Примечание: автономная распаковка оптимизирована для ARM64/aarch64 устройств. На других архитектурах, таких как x86_64 или armv7, базовый образ будет скачан из GitHub).*
- При первом запуске `TermuxInstaller.java` копирует образ в точный путь кэша, ожидаемый `proot-distro` (`/data/.../var/lib/proot-distro/dlcache/`).
- `proot-distro install debian` обнаруживает файл и завершает установку **без единого сетевого запроса**.
- **Время до работающего Debian shell: менее 30 секунд** благодаря кэшированию.

---

### 2. 🔒 Защита от гонки потоков при первом запуске

Диалог разрешения хранилища Android создаёт скрытое состояние гонки: диалог приостанавливает Activity → служба переподключается → запускается второй поток распаковки → оба потока одновременно уничтожают файлы → ошибка `"Unable to install bootstrap"`.

**Решение:** Статический синхронизированный флаг `mIsInstallingBootstrap` в `TermuxInstaller.java` — bootstrap выполняется ровно один раз, чисто.

---

### 3. 🌐 Загрузка прокси-ядер по требованию (Xray и Hysteria 2)

Бинарники прокси **не встроены** в APK. Лаунчер `start-agy.sh` внутри Debian проверяет наличие ядра **только при активации прокси пользователем**: нет — скачивает нужную архитектуру автоматически; есть — запускает сразу.

---

### 4. 🔑 Импорт прокси по ссылке (VLESS и Hysteria 2)

Встроенный Python-парсер (`generate_proxy_config.py`) принимает ссылку и генерирует нативный JSON-конфиг:

- **`vless://`** → `xray_config.json` с двойными inbound'ами SOCKS5 + HTTP, поддержка Reality, TLS, WebSocket, gRPC.
- **`hysteria2://`** → `hysteria_config.json` с поддержкой обфускации, TLS SNI и insecure.

Все конфиги хранятся в `/sdcard/AntigravityWorkspace/`.

---

### 5. 🛡️ Автоматический патч бинарника AGY (обход региональной блокировки)

AGY CLI содержит региональные ограничения, блокирующие работу. Приложение интегрирует глубоко модифицированный воркфлоу **[open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher)** с фиксацией версий:

- `check_and_patch.py` копируется в рабочее пространство при каждом запуске.
- Репозиторий патчера жестко зафиксирован на стабильном коммите (`b9a01e8`), чтобы внешние изменения кода не нарушили работу приложения.
- Применяется кастомный **многоуровневый патч (multi-gate)**, который одновременно нейтрализует проверку на стороне сервера (Gate 1) и скрывает плашку блокировки на уровне интерфейса (Gate 2).
- Если уже пропатчен → операция пропускается без задержки.

---

### 6. 🧩 Постоянное отслеживание сессии и рабочей директории

Хук `PROMPT_COMMAND` в `/etc/bash.bashrc` сохраняет текущую директорию при каждом новом промпте. При следующем запуске `start-agy.sh` автоматически восстанавливает её — как постоянная десктопная сессия.

---

### 7. ⌨️ Универсальные ASCII-стрелки

Кастомные прошивки (**Infinix XOS**, **TECNO HiOS**, **itel**) некорректно отображают Unicode-стрелки (`←`, `→`, `↑`, `↓`) как `ij`, `Ы`, `я`.

**Решение:** Все стрелки заменены на ASCII (`<-`, `->`, `^`, `v`) — работает на 100% устройств.

---

### 8. 🔄 Меню с автозапуском за 3 секунды

При старте: авто-запуск через 3 секунды (или авто-установка при первом запуске). Любая клавиша открывает меню: запуск AGY, обновление, настройка прокси, запуск патчера, Debian shell, сброс sandbox.

---

### 9. 🏥 Авто-восстановление контейнера

При каждом запуске проверяет наличие всех пакетов Debian (`python3`, `git`, `python3-packaging`) и молча переустанавливает недостающие — восстанавливает повреждённую среду без участия пользователя.

---

## 🚀 Быстрый старт

### Шаг 1 — Установить APK

Скачай последний `termux-app_apt-android-7-release_universal.apk` из раздела **[Releases](https://github.com/Milordick/antigravity-cli-mobile/releases)** и установи. Android может попросить разрешить установку из неизвестных источников — это ожидаемо.

> ⚠️ **Важно:** Не устанавливай из Google Play. Это отдельное приложение, устанавливаемое вручную.

---

### Шаг 2 — Первый запуск (полностью автоматический)

При первом запуске приложение выполняет **полностью автоматическую установку**. Никаких действий не требуется:

```
[ Первый запуск ]

  Приложение открылось
    └── Запрос прав на хранилище — нажать ALLOW
          └── Установка bootstrap (базовые инструменты Termux)
                └── Распаковка Debian Bookworm из APK (~30 сек)
                      └── apt-get: python3, git, curl, ca-certificates...
                            └── Установка Antigravity CLI внутри Debian
                                  └── ✅ Готово — AGY shell открывается автоматически
```

> 💡 **Интернет не нужен** для образа Debian — он встроен в APK. Интернет нужен только для `apt-get` и установщика AGY CLI.

---

### Шаг 3 — Последующие запуски (автозапуск за 3 секунды)

```
Приложение открылось → Показывает статус (Workspace, Прокси, Последняя директория)
                    → «Launching in 3 seconds...»
                    → [Нажать любую клавишу] → Открыть интерактивное меню
                    → [Подождать 3 секунды]  → AGY CLI запускается автоматически
```

---

### Шаг 4 — Настройка прокси (по желанию)

1. Нажать любую клавишу при обратном отсчёте → **Главное меню**.
2. Выбрать **`3) Network & Proxy settings`**.
3. Выбрать **`2) Set Proxy Type`** → выбрать `xray` или `hysteria2`.
4. Выбрать **`3) Import URL`** → вставить ссылку `vless://...` или `hysteria2://...`.
5. Приложение разбирает ссылку, генерирует конфиг и **автоматически включает прокси**.
6. **`0) Back`** → **`1) Launch Antigravity CLI`** — прокси уже активен.

---

### Шаг 5 — Запуск патчера (если нужно)

Если AGY показывает экран региональной недоступности:

1. **Главное меню → `4) Run Antigravity Patcher`**.
2. Патчер скачивается автоматически, патчит бинарник AGY и перезапускает его.
3. Готово — экран недоступности больше не появляется.

---

## 📋 Справочник по главному меню

```
╔══════════════════════════════════════════╗
║     ANTIGRAVITY CLI  //  DEBIAN SANDBOX  ║
╚══════════════════════════════════════════╝

  Workspace : /sdcard/AntigravityWorkspace
  Proxy     : ON (xray)         ← текущий статус прокси
  Last dir  : /workspace/myproject

  1) Launch Antigravity CLI     ← Запустить AGY в контейнере Debian
  2) Update Antigravity CLI     ← Переустановить официальный AGY CLI
  3) Network & Proxy settings   ← Подменю настройки прокси
  4) Run Antigravity Patcher    ← Обход региональной блокировки
  5) Open Debian shell          ← Чистый bash внутри Debian
  6) Reset sandbox              ← ⚠️ Полный сброс (Debian + workspace)
  7) Exit
```

---

## ⚙️ Настройки сети и прокси — Полный справочник

Доступ: **Главное меню → 3**.

```
  Network & Proxy Settings
  ========================

  1) Toggle proxy           [ ON / OFF ]       ← Вкл/выкл прокси
  2) Set Proxy Type         [ xray ]           ← Выбор движка
  3) Import URL             [ VLESS или Hysteria 2 ]
  4) Manual Config Settings [ Server: ... ]   ← Ручная настройка полей
  0) Back to Main Menu
```

### Пункт 2 — Тип прокси

| Выбор | Движок | Протокол | Для чего |
|:---:|---|---|---|
| `1` | **xray** | VLESS + XTLS-Reality / TLS | Стандартные V2Ray/Xray серверы |
| `2` | **hysteria2** | UDP (QUIC) | Высокая скорость, нестабильная сеть |
| `3` | **socks5** | SOCKS5 | Внешний SOCKS5 прокси |
| `4` | **http** | HTTP CONNECT | Корпоративный/внешний HTTP прокси |

### Пункт 3 — Импорт ссылки

Вставить полную прокси-ссылку. Поддерживаемые форматы:

| Протокол | Пример |
|---|---|
| VLESS Reality | `vless://uuid@host:443?security=reality&flow=xtls-rprx-vision&pbk=KEY&sid=ID&sni=SNI` |
| VLESS TLS | `vless://uuid@host:443?security=tls&sni=SNI` |
| Hysteria 2 | `hysteria2://password@host:443?sni=SNI` |
| Hysteria 2 + obfs | `hysteria2://pass@host:443?sni=SNI&obfs=salamander&obfs-password=OBF` |

При успехе: конфиг сохраняется, прокси включается автоматически.

### Пункт 4 — Ручная настройка (xray)

| Поле | Описание |
|---|---|
| **Server** | Хост или IP прокси-сервера |
| **Port** | Порт сервера (обычно 443) |
| **UUID** | Идентификатор пользователя |
| **Flow** | `xtls-rprx-vision` (Reality) или пусто |
| **SNI** | Server Name Indication для TLS |
| **PubKey** | Публичный ключ Reality |
| **ShortID** | Short ID для Reality (оставить пустым если нет) |

Для **Hysteria 2** вручную: Server, Port, Auth/Password, SNI, Obfs Type (`salamander` или пусто), Obfs Password.

> 💡 Оставь поле пустым чтобы сохранить текущее значение. Введи `none` чтобы очистить необязательное поле.

---

## 💡 Советы, особенности и нюансы

### 🔋 Поведение в фоне
- Debian-контейнер работает как **процесс переднего плана**, привязанный к сессии терминала. Закрытие приложения останавливает AGY и прокси.
- Для долгих фоновых задач используй `nohup команда &` внутри Debian shell.

### 🌐 Переменные окружения прокси
Когда прокси включён, внутри Debian автоматически устанавливаются переменные:
```bash
export HTTP_PROXY="http://127.0.0.1:10809"
export HTTPS_PROXY="http://127.0.0.1:10809"
export ALL_PROXY="http://127.0.0.1:10809"
```
Это заставляет `apt`, `curl`, `pip`, `npm` и любые другие CLI-инструменты использовать прокси без дополнительной настройки.

### 📁 Расположение файлов рабочего пространства
Все постоянные данные хранятся в `/sdcard/AntigravityWorkspace/` (со стороны Android), смонтированном как `/workspace` внутри Debian:

| Файл | Назначение |
|---|---|
| `proxy_config.sh` | Вкл/выкл прокси и тип |
| `vless_settings.sh` | Ручные параметры VLESS |
| `vless_link.txt` | Последняя импортированная ссылка |
| `xray_config.json` | Сгенерированный конфиг Xray |
| `hysteria_config.json` | Сгенерированный конфиг Hysteria2 |
| `proxy_engine.txt` | Активный движок (`xray` или `hysteria`) |
| `.last_dir` | Последняя рабочая директория в Debian |
| `check_and_patch.py` | Скрипт авто-патчера |
| `open-antigravity-patcher/` | Исходники патчера (клонируются при первом использовании) |

### ⚠️ Полный сброс
**Меню → 6 → ввести `yes`** выполняет полный сброс:
- Удаляет весь Debian-контейнер (`proot-distro remove debian`)
- Удаляет весь `/sdcard/AntigravityWorkspace/`
- При следующем запуске снова выполняется полная первоначальная установка

### 🔄 Обновление AGY
**Меню → 2** запускает `curl -fsSL https://antigravity.google/cli/install.sh | bash` внутри Debian. Обновляет AGY до последней версии. После обновления при необходимости повторно запусти патчер (Меню → 4).

### 🐚 Чистый Debian Shell
**Меню → 5** открывает обычный `bash` внутри Debian с примонтированными `/workspace` и `/sdcard`. Полезно для ручной отладки, установки пакетов и расширенной настройки.

---

## 💖 Поддержка проекта

Если вам нравится этот проект, вы можете поддержать его развитие чаевыми для разработчика через CloudTips:

👉 **[Поддержать через CloudTips](https://pay.cloudtips.ru/p/0ef570e5)**

---

## 🏗️ Сборка из исходников

```bash
git clone https://github.com/Milordick/antigravity-cli-mobile.git
cd antigravity-cli-mobile

export TERMUX_SPLIT_APKS_FOR_RELEASE_BUILDS="0"
./gradlew assembleRelease
# Результат: app/build/outputs/apk/release/termux-app_apt-android-7-release_universal.apk
```

**Требования:** Android SDK с NDK, JDK 11+, Gradle 7+

---

## 📄 Лицензия

Проект распространяется под лицензией **[GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html)**.

### Состав лицензий

| Компонент | Лицензия | Примечание |
|---|---|---|
| `app/` (оригинальный код этого проекта) | GPL v3.0 | Автоматизация, скрипты и модификации |
| `terminal-emulator/`, `terminal-view/` | Apache 2.0 | Из [Android-Terminal-Emulator](https://github.com/jackpal/Android-Terminal-Emulator) |
| `termux-shared/` | MIT / Apache 2.0 | Смотри [`termux-shared/LICENSE.md`](termux-shared/LICENSE.md) |
| Bootstrap-пакеты Termux | GPL v3.0 | Из [termux/termux-packages](https://github.com/termux/termux-packages) |
| Rootfs Debian Bookworm (встроенный актив) | Различные (DFSG-совместимые) | Применяются стандартные лицензии пакетов Debian |
| [open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher) | As-is (upstream) | Используется как runtime-зависимость, клонируется по требованию |

Используя это приложение, вы принимаете условия всех применимых лицензий, перечисленных выше.
