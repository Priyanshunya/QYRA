# QYRA Embedded Firmware

This directory tracks the evolution of the QYRA hardware prototype on the ESP32-S3. The system transitioned from a basic telemetry logger to a decentralized, dual-core RTOS running on-device machine learning.

### Directory Structure
* **`v1_baseline_telemetry/`**: Our initial prototype. It successfully established the I2C sensor array and basic Bluetooth GATT communication, but relied on basic thresholds (heuristics) that were prone to false positives during physical movement.
* **`v2_heuristic_triage/`**: The current production prototype. We migrated from hardcoded heuristics to an 8-bit quantized TinyML neural network. 

### Key Upgrades in V2
* **FreeRTOS Dual-Core Pinning:** Clinical sensors are pinned to Core 1 at 50Hz, while AI inference and UI updates are isolated on Core 0.
* **Dual I2C Buses:** Separated the fast clinical sensors from the slower environmental/OLED sensors to prevent bus collisions.
* **NVS Flash Provisioning:** Instead of pushing raw `.tflite` weights over BLE, demographic-specific models are pre-compiled into flash. A 1-byte BLE command securely locks the device to the user's profile on first boot.
