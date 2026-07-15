# 🌌 antigravity-cli-mobile

<p align="center">
  <img src="logo.png" width="128" height="128" alt="Logo"/>
</p>

<p align="center">
  <b>A premium Android terminal client automating the offline setup, configuration, and operation of the Google Deepmind Antigravity CLI sandbox environment.</b>
</p>

<p align="center">
  <a href="https://github.com/Milordick/antigravity-cli-mobile/releases"><img src="https://img.shields.io/github/v/release/Milordick/antigravity-cli-mobile?color=blue&logo=github&style=for-the-badge" alt="GitHub release"/></a>
  <a href="https://www.gnu.org/licenses/gpl-3.0"><img src="https://img.shields.io/badge/License-GPL%20v3-blue.svg?style=for-the-badge" alt="License"/></a>
  <a href="#"><img src="https://img.shields.io/badge/Platform-Android%207.0%2B-green.svg?style=for-the-badge" alt="Platform"/></a>
</p>

---

## 🌍 Language / Язык
* [English Description](#-english-description)
* [Русское описание](#-русское-описание)

---

## 🇺🇸 English Description

**antigravity-cli-mobile** is a dedicated Android client wrapper designed to deploy and manage the **Google Deepmind Antigravity CLI** environment on mobile devices. Built on top of the robust **Termux** terminal emulator, it incorporates deep system automation, offline container provisioning, dynamic networking wrappers, and interface compatibility patches to deliver an out-of-the-box, premium developer experience.

### 🔗 Credits and Attribution
This project is built using:
* **[Termux App](https://github.com/termux/termux-app):** Core Android terminal emulator codebase.
* **[open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher):** The backend utility for bypassing regional eligibility screens and patching the active client binaries.

---

### 🚀 Key Technical Features in Detail

#### 1. ⚡ Zero-Configuration Offline Bootstrap (Debian Bookworm)
Installing a full Linux distribution on a mobile device usually requires downloading hundreds of megabytes of rootfs tarballs over a stable internet connection. 
* **The Solution:** We bundle a pre-compiled `debian-bookworm-aarch64` rootfs directly into the APK assets.
* **How it works:** During the first boot, the app extracts the rootfs and registers system binaries offline in under 30 seconds.
* **Offline Path Caching:** The installer automatically populates the localized directory (`/var/lib/proot-distro/dlcache/`), tricking the package manager into bypassing the network download phase.

#### 2. 🔒 Double-Bootstrap Race-Condition Protection
When starting the app for the first time, Android displays the storage permission dialog.
* **The Problem:** The permission overlay causes the terminal activity to pause and resume. This action triggers `onServiceConnected()` twice, launching two parallel threads that wipe and write the bootstrap concurrently, corrupting files and triggering the `"Unable to install bootstrap"` error.
* **The Solution:** Added a Java synchronized thread-safe gatekeeper lock (`mIsInstallingBootstrap`). If an installation is already active, subsequent launch events return early, guaranteeing a clean and crash-free first run.

#### 3. 🌐 Dynamic On-Demand Proxy Engines (Xray & Hysteria 2)
To keep the application size minimal and the first installation fast, proxy binaries (`xray` and `hysteria`) are not pre-packaged.
* **The Solution:** If the user imports a `vless://` (Reality) or `hysteria2://` link, the custom launcher script detects the missing engine and downloads it on-demand right before launching the proxy.
* **Automatic Configuration Parser:** An embedded Python script (`generate_proxy_config.py`) parses imported proxy URIs, maps internal ports, and outputs native configuration JSONs instantly.

#### 4. ⌨️ Fallback ASCII Keyboard Arrow Navigation
Certain custom Android locale fonts (found in Infinix XOS, TECNO HiOS, etc.) fail to map standard unicode arrow symbols (`←`, `→`, `↑`, `↓`), rendering them as broken Cyrillic character bugs (such as `ij`, `IJ`, `Ы`).
* **The Solution:** Remapped the toolbar keys to simple, universal ASCII fallbacks (`<-`, `->`, `^`, `v`). This guarantees clean, legible keys on all device makes, models, and custom system fonts.

---

### 📦 Releases & Downloads
To download the compiled APK, check the **[Releases](https://github.com/Milordick/antigravity-cli-mobile/releases)** tab. The package is bundled as a single universal build (`termux-app_apt-android-7-release_universal.apk`) supporting all mainstream ARM/x86 architectures.

---

## 🇷🇺 Русское Описание

**antigravity-cli-mobile** — это специализированное терминальное приложение для Android, предназначенное для развертывания, настройки и автоматического запуска мобильного изолированного окружения **Google Deepmind Antigravity CLI**. 

Проект создан на базе терминального эмулятора **Termux** и оснащен глубокой автоматизацией, локальным контейнером Debian, динамическим управлением прокси-подключениями и исправлениями интерфейса.

---

### 🚀 Подробное Описание Ключевых Функций

#### 1. ⚡ Автономная установка Debian за 30 секунд (Offline Bootstrap)
Классическая установка дистрибутивов в `proot-distro` требует скачивания тяжелых образов с GitHub при первом запуске, что невозможно без стабильного интернета.
* **Как решено:** Полный образ Debian Bookworm упакован непосредственно в ассеты APK.
* **Принцип работы:** Приложение при первом запуске автоматически создает кэш по пути `/var/lib/proot-distro/dlcache/` и распаковывает дистрибутив локально, полностью пропуская фазу скачивания.

#### 2. 🔒 Защита от конфликта параллельных потоков
В момент первого запуска система запрашивает у пользователя права на доступ к общей памяти (Storage Permission).
* **Проблема:** Переключение на диалоговое окно Android приостанавливает работу приложения. При возвращении в Termux служба запускается повторно, порождая второй поток распаковки Debian. Они начинали перезаписывать папки друг друга, вызывая ошибку `"Unable to install bootstrap"`.
* **Как решено:** В Java-код класса `TermuxInstaller` внедрена синхронизированная блокировка `mIsInstallingBootstrap`. Все повторные вызовы отсекаются на входе, гарантируя идеальный первый запуск без ошибок.

#### 3. 🌐 Умная подгрузка ядер прокси (Xray и Hysteria 2)
Для экономии памяти и трафика бинарные файлы ядер прокси не встраиваются в приложение изначально.
* **Как решено:** Скрипт автозапуска `start-agy.sh` проверяет наличие ядер непосредственно в момент активации прокси. 
* Если вы импортируете ссылку `vless://` или `hysteria2://`, приложение само определит архитектуру процессора и загрузит необходимое ядро из репозитория разработчиков.
* Встроенный парсер `generate_proxy_config.py` берет на себя всю работу по конвертации ссылок в JSON-конфигурации.

#### 4. ⌨️ Исправление навигационных стрелок
На некоторых прошивках телефонов (например, Infinix XOS, TECNO HiOS) системные шрифты некорректно сопоставляют стандартные юникод-стрелки (`←`, `→`, `↑`, `↓`), из-за чего на клавиатуре вместо них отображались буквы (`ij`, `Ы`, `я`).
* **Как решено:** Все стрелки переведены на универсальные ASCII-последовательности (`<-`, `->`, `^`, `v`). Это гарантирует корректное отображение клавиатуры на любой версии Android с любыми системными шрифтами.

---

### 📦 Релизы и Сборка
Готовый APK-файл всегда доступен в разделе **[Releases](https://github.com/Milordick/antigravity-cli-mobile/releases)**:
* **Файл:** `termux-app_apt-android-7-release_universal.apk` (универсальный билд для ARM64/ARMv7/x86/x86_64).

Для ручной сборки:
```bash
export TERMUX_SPLIT_APKS_FOR_RELEASE_BUILDS="0"
./gradlew assembleRelease
```
