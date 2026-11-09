# QYRA WebBLE Engineering Dashboard (Pre-Market)

This folder contains the Web Bluetooth (WebBLE) companion dashboards used for rapid prototyping, hardware validation, and AI debugging. 

Before we move into production and build the final cross-platform mobile application (Flutter), we needed a lightweight way to connect to the ESP32-S3 prototype, visualize the 10Hz telemetry, and validate our TinyML models in real-time. Because this runs entirely in the browser using the Web Bluetooth API, it allows us to test the hardware-software handshake instantly without constantly compiling and side-loading APKs.

### 📁 Version History
* **`index_v1_baseline.html`**: Our initial V1 prototype dashboard. We used this to validate the raw I2C sensor stream and test basic client-side health thresholds before we had a working neural network.
* **`index_v2_edge_ai.html`**: The active V2 dashboard. It relies on the ESP32-S3's native TinyML engine for logic. This serves as our primary bench tool for NVS provisioning and Edge AI validation.

### 🧠 V2 Dashboard Capabilities
* **NVS Hardware Provisioning:** Allows us to select an ML demographic profile (Standard, Elderly, Industrial) from the UI. The dashboard sends a 1-byte command via BLE GATT to permanently lock the ESP32's tensor arena to that specific model.
* **Real-Time AI Validation:** Parses the inference integer streaming directly from the MCU's Core 0 and visually maps it to triage states (Nominal, Heat Strain, Fall Impact, etc.) alongside the raw vitals.
* **Local Data Logging & Export:** To comply with DPDP privacy standards during testing, health data (PHI) is kept strictly on the device using browser `localStorage`. We included a CSV export tool to pull 24-hour sensor dumps for offline analysis.
* **Emergency Mesh Integration:** Pulls physical GPS coordinates via the Browser Geolocation API to prepare accurate SOS payloads for the ESP32's LoRa transceiver.
* **Voice Alerts (TTS):** Uses the browser's native speech synthesis API to test multilingual voice alerts (English, Hindi, Tamil) triggered by the AI triage states.

### 🚀 How to Run
1. Flash the V2 firmware to the ESP32-S3 and power it on.
2. Double-click `index_v2_edge_ai.html` to open it in Chrome, Edge, or Opera.
3. Click **Connect** to open the browser's native Bluetooth pairing menu.
4. Select `SIH_OMNI_STACK`. The dashboard will instantly bind to the hardware and begin plotting the live JSON stream.
