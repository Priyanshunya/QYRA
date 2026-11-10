# Edge AI & TinyML Triage Matrix

QYRA replaces flat, single-sensor alarms (e.g., "Heart rate > 100 BPM") with a multi-modal Edge-AI inference engine. By analyzing the intersection of 5 distinct sensor streams locally on the ESP32-S3, QYRA eliminates false positives caused by physical exertion or environmental noise.

### 1. Pre-Processing & CMSIS-DSP
Raw optical PPG data (MAX30102) is highly susceptible to kinetic noise (e.g., the user walking or using a hammer). 
Before data enters the neural network, QYRA uses the MPU6050 IMU to measure physical movement. If high kinetic variance is detected, a hardware-accelerated DSP filter (leveraging CMSIS-DSP paradigms) smooths the PPG waveform to extract the true physiological signal from the motion artifacts.

### 2. INT8 Quantization
To fit a complex neural network onto an ESP32-S3 without draining the battery, the model weights are quantized from 32-bit floating-point decimals down to 8-bit integers (INT8). 
* **Model Size:** < 100 KB
* **Inference Time:** < 50 milliseconds(targeted < 15 milliseconds)
* **RAM Overhead:** Minimal, allowing simultaneous LoRa and BLE operations.

### 3. The Triage State Matrix
The neural network relies on a temporal sliding-window anomaly detection algorithm. It outputs one of five distinct qualitative states, masking the raw data for privacy compliance:

| Triage State | Primary Triggers (Sensor Fusion) | System Action |
| :--- | :--- | :--- |
| **NOMINAL** | Stable SpO2, HR matches IMU exertion, Env Temp normal. | Silent telemetry logging. |
| **EXERTION** | High HR + High IMU Activity (Expected state). | Updates OLED HUD; no alarm. |
| **HEAT STRAIN (PSI)** | High Skin Temp (MLX90614) + High HR + High Ambient Temp (BME680) + Low IMU. | Warning buzzer; logs Heat Strain state. |
| **RESPIRATORY (RDI)** | Dropping SpO2 + High HR + Poor Ambient VOC (BME680). | Warning buzzer; BLE alert. |
| **CRITICAL / FALL** | Sudden IMU impact followed by zero movement, or SpO2 < 85%. | Overrides network; broadcasts LoRa SOS. |

### Demographic NVS Provisioning
Because a resting heart rate of 90 BPM means something different for an 18-year-old worker versus a 75-year-old patient, QYRA stores demographic-specific baseline models in flash memory. On initial setup, a single BLE command provisions the ESP32-S3's Non-Volatile Storage (NVS) to load the correct demographic baseline, ensuring accurate anomaly detection.
