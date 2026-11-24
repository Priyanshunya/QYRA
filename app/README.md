# QYRA Android App

Offline-first Android companion app for the QYRA ESP32-S3 wearable node, built with Flutter.

## Download

Get the latest installable APK (`qyra_v0.9_beta.apk`) from the [Releases](https://github.com/Priyanshunya/QYRA/releases) page. Requires Android 8.0 or higher.

## Features

- **Direct BLE Telemetry:** Connects automatically to `QYRA_EDGE_NODE` over BLE GATT with zero cloud dependency.
- **Lock-Screen Monitoring:** Uses an Android foreground service so vitals tracking and alerts stay active while the phone is locked.
- **Insights & Alerts:** Displays live vitals,ML insights, sensor charts, PHI privacy toggles, GPS coordinates, and offline voice (TTS) emergency alerts.
- **Device Control:** Supports NVS user-profile provisioning over BLE and local CSV telemetry export.

## Background Setup Note

To stop Android from pausing the BLE connection when the screen is off, disable battery restrictions for **QYRA** in your phone's App Info settings (set Battery to **No restrictions / Unrestricted**, and enable **Autostart** on Xiaomi, Poco, Oppo, Vivo, or Realme devices).
