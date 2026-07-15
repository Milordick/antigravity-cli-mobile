# 🌌 antigravity-cli-mobile

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/Milordick/antigravity-cli-mobile?color=blue&logo=github)](https://github.com/Milordick/antigravity-cli-mobile/releases)
[![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform](https://img.shields.io/badge/Platform-Android%207.0%2B-green.svg)](#)

---

### 🇺🇸 Project Description

**antigravity-cli-mobile** is a customized terminal application for Android designed to automate the installation, configuration, and launch of the **Google Deepmind Antigravity CLI** sandbox environment on mobile devices. 

Built on top of the open-source **Termux** terminal emulator, it adds a completely offline bootstrap installation method, custom supervisor scripts, dynamic on-demand proxy support (Xray / Hysteria 2), and interface patches for perfect mobile keyboard compatibility.

#### 🔗 Related Projects & Credits:
* **Antigravity CLI Mobile** (This Repository)
* **[open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher)** — The open-source patcher used by our container to patch region restrictions and activate the Antigravity sandbox.
* **[Termux App](https://github.com/termux/termux-app)** — The foundational terminal emulator base.

---

### 🇷🇺 Описание проекта

**antigravity-cli-mobile** — это специализированное терминальное приложение для Android, предназначенное для автоматического развертывания, настройки и запуска изолированного окружения **Google Deepmind Antigravity CLI** на мобильных телефонах.

Проект построен на базе **Termux**. В него интегрирована полностью автономная (офлайн) установка Debian-контейнера, встроенные менеджеры автозапуска прокси (Xray / Hysteria 2) и адаптированная под мобильные экраны клавиатура навигации.

#### 🔗 Использованные инструменты и благодарности:
* **Antigravity CLI Mobile** (Данный репозиторий)
* **[open-antigravity-patcher](https://github.com/AvenCores/open-antigravity-patcher)** — Открытый патчер, используемый внутри контейнера для обхода региональных ограничений клиента Antigravity.
* **[Termux App](https://github.com/termux/termux-app)** — Оригинальный терминальный эмулятор, послуживший основой приложения.

---

## ⚡ Main Features / Основные фичи

### 🇺🇸 English
* **📦 Offline Debian Bootstrap:** Contains a pre-cached Debian Bookworm image. Installation completes in 30 seconds without internet.
* **🔒 Concurrent Safe Setup:** Synchronized thread locks prevent double-extraction bugs when requesting permissions.
* **🚀 Dynamic Proxy Provisioning:** Xray (VLESS) and Hysteria 2 are downloaded automatically only when selected.
* **⌨️ Fallback Arrow Keys:** Keyboard toolbar uses standard ASCII characters (`<-`, `->`, `^`, `v`), eliminating rendering issues and glyph bugs on customized system fonts.

### 🇷🇺 Русский
* **📦 Офлайн-установка Debian:** Установочный образ Debian Bookworm встроен в APK. Установка проходит за 30 секунд без интернета.
* **🔒 Безопасный запуск:** Специальный блокировщик потоков Java предотвращает сбои при выдаче прав доступа к памяти.
* **🚀 Умная подгрузка прокси:** Ядра Xray (VLESS) и Hysteria 2 скачиваются из сети только в момент активации подключения.
* **⌨️ Совместимые стрелки:** Стрелочки навигации переведены на стандартные ASCII-символы (`<-`, `->`, `^`, `v`), что убирает баги шрифтов (буквы `ij`, `Ы` вместо стрелок).

---

## 📦 Releases & Downloads / Релизы и загрузка

You can download the compiled universal release APK directly from the **[Releases](https://github.com/Milordick/antigravity-cli-mobile/releases)** section:
* **Latest Version:** `v0.159.0`
* **Artifact:** `termux-app_apt-android-7-release_universal.apk`

Вы можете скачать готовую собранную версию в разделе **[Releases](https://github.com/Milordick/antigravity-cli-mobile/releases)**:
* **Последняя версия:** `v0.159.0`
* **Файл:** `termux-app_apt-android-7-release_universal.apk`
