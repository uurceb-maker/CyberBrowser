# XrayBridge

This folder contains the Swift/C bridge scaffold for Xray-core integration.

## Included
- `XrayBridge.h`: C bridge header placeholder
- `XrayWrapper.swift`: Swift runtime wrapper and config generator

## Current status
- `XrayWrapper.start(...)` is a safe stub and logs startup.
- A real `libxray.xcframework` bridge can replace the stub later.

## Expected integration flow
1. Generate config JSON from server protocol/settings.
2. Write JSON to Documents (`xray_config.json`).
3. Call C bridge start with config path.
4. Route `WKWebsiteDataStore.proxyConfigurations` to `127.0.0.1:9090`.
