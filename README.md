# QYRA: Wearable Edge-AI Health & Disaster Companion
> **Smart India Hackathon 2026 | Team Vision.exe (Team ID: 162907) | PS 26181**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-ESP32--S3%20%7C%20FreeRTOS-blue)](https://www.espressif.com/)
[![Production Target](https://img.shields.io/badge/Production%20Target-Qualcomm%20QCC748M-orange)](https://www.qualcomm.com/)

---

## 🚀 Overview
**QYRA** is a secure, privacy-by-design edge wearable engineered to provide continuous physiological triage and reliable off-grid emergency communication during critical infrastructure failures, such as disaster-induced cellular blackouts. 

Conventional health wearables suffer from cloud-dependency and single-sensor alarm fatigue. QYRA solves this via an **offline-first, multi-modal Edge-AI architecture** that processes biometrics locally on the wrist, protects user data under DPDP Act principles, and broadcasts encrypted SOS payloads via sub-GHz LoRa telemetry.

---

## 🛠️ System Architecture & Tech Stack

```text
+-----------------------+     +--------------------------+     +-----------------------------------+     +-------------------------+
|         SENSE         | --> |    EDGE COMPUTE          | --> |    AI INFERENCE                   | --> |     ACTION & ALERT      |
|                       |     |    (ESP32-S3 / FreeRTOS) |     |    (TinyML / PSI & RDI)           |     |                         |
+-----------------------+     +--------------------------+     +-----------------------------------+     +-------------------------+
| - MAX86141 (SpO2/HR)  |     |                          |     | - INT8 Quantized Model (<100KB)   |     | - Local OLED + Buzzer   |
| - GSR (Skin Cond.)    |     |                          |     | - Motion-Aware CMSIS-DSP Filtering|     | - Flutter Dashboard     |
| - LSM6DSOX (IMU/Falls)|     |                          |     | - Baseline Deviation Scoring      |     | - SX1262 LoRa (IN865)   |
| - BME688 (Gas/VOC)    |     |                          |     |                                   |     |                         |
| - TMP117 (Skin Temp)  |     |                          |     |                                   |     |                         |
+-----------------------+     +--------------------------+     +-----------------------------------+     +-------------------------+
### 1. Embedded & Firmware Stack
* **Microcontroller:** ESP32-S3 (Bench Prototype) / Qualcomm QCC748M (Production Target Roadmap).
* **RTOS:** FreeRTOS with dual-bus sensor isolation (Clinical high-speed sensors on SPI/I2C Bus 0; Environmental/UI on Bus 1) to eliminate bus-choking and sustain real-time biometric polling.
* **Framework:** ESP-IDF / PlatformIO.

### 2. Edge AI & Signal Processing
* **Inference Engine:** INT8-quantized TinyML model (<100 KB file size) executing locally on-device.
* **Signal Conditioning:** Motion-aware signal-quality assessment utilizing optimized DSP libraries to mitigate kinetic artifacts from raw optical PPG and GSR streams before inference.
* **Triage Modules:** 
  * **PSI (Heat-Strain Engine):** Fuses ambient heat, activity, and physiological trends to screen escalating heat-strain risk.
  * **RDI (Respiratory-Risk Engine):** Correlates SpO₂/HR trends with ambient air-quality context for respiratory advisories.

### 3. Connectivity & Emergency Mesh
* **Off-Grid Radio:** SX1262 LoRa transceiver configured for India's de-licensed **IN865 (865–867 MHz)** band (subject to WPC compliance pathways) alongside an ESP-NOW telemetry link.
* **Companion App:** Flutter-based mobile dashboard providing real-time vitals, offline alerts, and a multilingual **"Voice Guard" TTS engine** for outdoor workforce accessibility.

---

## 📊 Feasibility & Bill of Materials (BOM)
* **Cost Efficiency:** Fully functional bench-prototype hardware achieved under an itemized **~Rs. 3,000 BOM**, offering a major CapEx advantage over commercial medical pendants for scalable emergency response deployment.
* **Industrial Target:** The production roadmap evaluates the Qualcomm QCC748M tri-radio IoT SoC (325 MHz RISC-V MCU, hardware DSP/FPU, Bluetooth 5.4, Wi-Fi 6) targeting 7+ days of battery autonomy on a 500mAh LiPo cell inside a targeted IP67 rugged enclosure.

---

## 🔒 Privacy-by-Design (DPDP Aligned)
* Routine physiological analysis occurs locally on the device.
* Raw biometric numbers stay on the wearable by default; telemetry is abstracted into qualitative states (e.g., "STABLE", "ABNORMAL") before local transmission to the paired companion app.
* Local SQLite storage is secured via hardware-backed AES-256 cryptographic vaulting.

---
*Disclaimer: QYRA is intended for preventive health awareness and emergency support, not as a substitute for clinical diagnosis or professional medical care.*
