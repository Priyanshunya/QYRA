# RTOS Architecture & Asymmetric Task Isolation

To achieve clinical-grade reliability on a commercial ESP32-S3 microcontroller, QYRA utilizes a highly customized FreeRTOS task scheduler. We implement an **asymmetric dual-core architecture** combined with a **physically isolated dual I2C bus topology**.

### The Problem with Single-Core Wearables
In standard Arduino/hobbyist firmware loops, writing pixels to an OLED screen or calculating a neural network matrix blocks the CPU. If the CPU is blocked, it misses the microscopic timing windows required to read the MAX30102 PPG sensor, resulting in corrupt heart-rate data and false AI predictions.

### The QYRA Dual-Core Solution
We explicitly pin FreeRTOS tasks to specific silicon cores to guarantee deterministic timing for critical physiological data.

#### Core 1: The Clinical Core (High Priority)
Core 1 is strictly reserved for high-frequency, low-latency hardware interrupts and medical sensor polling.
* **Clinical I2C Bus 0 (100kHz):** MAX30102 (HR/SpO2), MPU6050 (IMU), MLX90614 (Skin Temp).
* **Task:** `vitals_poll_task`
* **Frequency:** 50Hz strict loop.
* **Behavior:** Reads raw sensor data and pushes it into a thread-safe FreeRTOS RingBuffer.

#### Core 0: The Application Core (Variable Priority)
Core 0 handles heavy computations and slow external communications. Because it reads from the RingBuffer, it can stall or delay without ever interrupting the hardware polling on Core 1.
* **Environment I2C Bus 1 (100kHz):** BME680 (Gas/Env) and 1.3" OLED Display.
* **Task 1 (AI):** Pulls windows of data from the RingBuffer and runs the INT8 TinyML inference.
* **Task 2 (UI):** Updates the OLED triage HUD based on AI outputs.
* **Task 3 (Comms):** Packages SOS states and transmits via the SX1276 LoRa transceiver and WebBLE.

### Memory & Inter-Process Communication (IPC)
Data is passed between Core 1 and Core 0 using standard FreeRTOS queues. This prevents race conditions where the AI tries to read a variable at the exact microsecond the sensor is updating it.
