# CyberBrowser 🛡️

Gizlilik odaklı, reklam engelleyicili iOS tarayıcı — **Cyberpunk Edition**

![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![iOS](https://img.shields.io/badge/iOS-17.0+-blue)
![License](https://img.shields.io/badge/License-MIT-green)

## 🎨 Tema
- **Siyah** (#000000) arka plan
- **Sarı** (#FACC15) vurgu rengi
- **Beyaz** metin

## ✨ Özellikler

### 🛡️ Reklam Engelleme
- 100+ reklam domaini engelleme
- DOM temizleme, XHR/fetch interceptor
- YouTube reklam atlama
- Animasyonlu engelleme sayacı

### 🧩 Uzantı Sistemi
- 5 dahili uzantı (Karanlık Mod, Okuyucu Modu, Gizlilik Kalkanı, Çerez Engelleyici, YouTube Geliştirici)
- Özel JavaScript script ekleme
- manifest.json WebExtension import desteği

### 📑 Sekme Yönetimi
- 2'li grid görünüm, sayfa önizlemeleri
- Yeni sekme / sekme kapatma
- HTTPS güvenlik göstergesi

### 🔊 Arka Plan Çalışma
- Video/ses arka planda çalmaya devam eder
- Tracker engelleme ile hızlı sayfa yükleme

## 🏗️ Kurulum

1. Xcode 15+ açın
2. **File → New → Project → App** (SwiftUI)
3. Bu repo'daki dosyaları projeye ekleyin
4. **Target → Signing & Capabilities → + Background Modes → Audio**
5. `⌘R` ile çalıştırın

## 📁 Dosya Yapısı

```
CyberBrowser/
├── CyberBrowserApp.swift
├── Info.plist
├── Theme/Theme.swift
├── Models/
│   ├── BrowserTab.swift
│   ├── AdBlockEngine.swift
│   └── ExtensionManager.swift
├── Views/
│   ├── ContentView.swift
│   ├── WebView.swift
│   ├── AddressBar.swift
│   ├── BottomNavBar.swift
│   ├── AdBlockBanner.swift
│   ├── TabManagerView.swift
│   ├── MenuView.swift
│   └── ExtensionsView.swift
└── Services/
    ├── TabManager.swift
    └── AudioSessionManager.swift
```

## 📄 Lisans
MIT
