# QYRA: ML Pipeline & Physiological profiles

Since we do not have medical ethics board (IRB) approval to induce clinical hypoxia or heatstroke in human subjects for hackathon testing, we could not collect real-world data for the extreme triage states. We also couldn't just use basic `random()` number generation, or the neural network would end up as a glorified if-else statement that fails on real hardware.

To solve this, I built a state-space biological simulator and a complete TinyML training pipeline to generate mathematically sound synthetic telemetry.

### 1. Data Generation (`physiological_profiles.py`)
This Python script acts as a physiological digital twin, It generates continuous 10Hz telemetry for three distinct demographic profiles (Standard, Elderly, Industrial Worker).
* **Biological Inertia:** Heart rate and skin temperature use Exponential Moving Averages (EMA) to ramp up and cool down slowly over time. This forces the neural network to learn complex physiological gradients instead of flat thresholds.
* **Optical Motion Coupling:** When the MPU6050 registers high acceleration (>13.5 m/s²), the script mathematically injects dropout noise into the SpO2/BPM readings to simulate the MAX30102 sensor physically bouncing on the wrist.
* **Clinical Outliers:** Injects random ectopic heartbeats and 50Hz powerline hum into the GSR ADC readings so the model learns to ignore single-tick noise.

### 2. TinyML Training (`QYRA_Colab_Training.ipynb`)
This Google Colab notebook ingests the generated CSVs and trains three separate neural networks.
* **Architecture:** Kept intentionally shallow (24 -> 12 -> 5 Dense layers) so inference runs in under 3ms on the ESP32-S3's Core 0 without stalling the FreeRTOS clinical polling tasks.
* **Quantization:** Dynamic 8-bit integer quantization shrinks the models so all three fit comfortably inside the ESP32's flash memory.
* **C++ Generation:** Instead of dealing with raw `.tflite` files and SPIFFS, the script uses pure Python to dump the quantized hex arrays and standard scaler math directly into a single C++ header file (`qyra_multi_model.h`).

### How to Run
1. **Generate the data:** Run `python physiological_profiles.py` locally. This outputs three training CSVs and one sequential preview CSV.
2. **Train in Colab:** Upload the CSVs to the Colab files tab, run the notebook, and download the resulting `qyra_multi_model.h` file.
3. **Deploy:** Drop the generated `.h` file straight into the `src/` folder of the ESP32 firmware.
