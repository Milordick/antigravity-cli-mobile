<p align="center">
  <img src="logo.png" width="140" height="140" alt="Antigravity CLI Mobile Logo"/>
</p>

<h1 align="center">antigravity-cli-mobile</h1>

<p align="center">
  <b>Premium Android terminal client for the Google Deepmind Antigravity CLI — fully offline, fully automated.</b>
</p>

<p align="center">
  <a href="https://github.com/Milordick/antigravity-cli-mobile/releases"><img src="https://img.shields.io/github/v/release/Milordick/antigravity-cli-mobile?color=6e40c9&logo=github&style=for-the-badge&label=Latest+Release" alt="GitHub release"/></a>
  <a href="https://www.gnu.org/licenses/gpl-3.0"><img src="https://img.shields.io/badge/License-GPL%20v3-blue.svg?style=for-the-badge" alt="License"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Platform-Android%207.0%2B-brightgreen.svg?style=for-the-badge" alt="Platform"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Architecture-ARM64%20%7C%20ARMv7%20%7C%20x86%20%7C%20x86__64-orange.svg?style=for-the-badge" alt="Architectures"/></a>
</p>

---

## 🌍 Language / Язык

- [🇺🇸 English Description](#-english-description)
- [🇷🇺 Русское описание](#-русское-описание)

---

## 🇺🇸 English Description

**antigravity-cli-mobile** is a fully self-contained Android terminal application built to deploy, configure, and run the **Google Deepmind Antigravity CLI** on mobile devices — completely offline, right out of the box, with zero user configuration required.

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

| File | Architectures | Min Android |
|---|---|---|
| `termux-app_apt-android-7-release_universal.apk` | arm64-v8a, armeabi-v7a, x86, x86_64 | Android 7.0 (API 24) |

---

## 🚀 Feature Deep-Dive

### 1. ⚡ Zero-Configuration Offline Debian Bootstrap

Installing a full Linux distribution inside `proot-distro` normally requires downloading a 200+ MB rootfs tarball from GitHub. On mobile networks, in regions with unstable connectivity, or in airplane mode — this simply fails.

**Our solution:**

- A pre-compiled **Debian Bookworm (ARM64)** rootfs (~42 MB compressed) is **bundled directly inside the APK** as an asset.
- At first launch, `TermuxInstaller.java` extracts the Termux bootstrap zip, then immediately copies the Debian rootfs into the exact cache path that `proot-distro` expects (`/data/.../var/lib/proot-distro/dlcache/`).
- `proot-distro install debian` detects the pre-cached file and completes installation **without a single network request**.
- **Total time from first launch to a running Debian shell: under 30 seconds**, even offline.

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

The AGY CLI binary contains an eligibility check blocking use outside specific regions. The app integrates the **[open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher)** workflow:

- `check_and_patch.py` is copied to the workspace on every launch.
- Scans the AGY binary for known unpatched byte signatures across **Linux ARM64 ELF**, **x86_64 ELF**, and **macOS arm64 Mach-O** formats.
- If unpatched → auto-clones the patcher, performs **memory-pattern injection** (replaces the eligibility gate with a NOP slide), restarts AGY.
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
│       └── TermuxInstaller.java        ← Bootstrap installer + offline Debian seeding
├── terminal-emulator/                  ← VT100/VT220 emulator library
├── terminal-view/                      ← Android View rendering the terminal
└── termux-shared/                      ← Shared utilities, constants, file ops
```

---

## 📄 License

GNU General Public License v3.0 — see [LICENSE.md](LICENSE.md).

---
---

## 🇷🇺 Русское Описание

**antigravity-cli-mobile** — это самодостаточное Android-приложение-терминал для развёртывания, настройки и запуска **Google Deepmind Antigravity CLI** на мобильных устройствах. Полностью автономно, без интернета при первом запуске, без ручной настройки.

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

| Файл | Архитектуры | Минимальный Android |
|---|---|---|
| `termux-app_apt-android-7-release_universal.apk` | arm64-v8a, armeabi-v7a, x86, x86_64 | Android 7.0 (API 24) |

---

## 🚀 Подробное описание ключевых функций

### 1. ⚡ Полностью автономная установка Debian (Offline Bootstrap)

Стандартная установка через `proot-distro` требует скачивания образа 200+ МБ с GitHub. Без интернета — не работает.

**Наше решение:**

- Предскомпилированный rootfs **Debian Bookworm (ARM64)** (~42 МБ) **встроен прямо в APK**.
- При первом запуске `TermuxInstaller.java` копирует образ в точный путь кэша, ожидаемый `proot-distro` (`/data/.../var/lib/proot-distro/dlcache/`).
- `proot-distro install debian` обнаруживает файл и завершает установку **без единого сетевого запроса**.
- **Время до работающего Debian shell: менее 30 секунд** — даже без интернета.

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

AGY CLI проверяет регион при запуске. Приложение интегрирует **[open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher)**:

- `check_and_patch.py` сканирует бинарник на наличие известных непатченных байт-паттернов (Linux ARM64 ELF, x86_64 ELF, macOS Mach-O).
- Если не пропатчен → авто-клонирует патчер, выполняет инъекцию байт-паттерна (заменяет eligibility-gate на NOP) и перезапускает AGY.
- Если уже пропатчен → ничего не делает, работает мгновенно.

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

GNU General Public License v3.0 — смотри [LICENSE.md](LICENSE.md).
