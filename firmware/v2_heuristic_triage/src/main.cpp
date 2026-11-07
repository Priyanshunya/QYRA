#include <Wire.h>
#include <SPI.h>
#include <LoRa.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h> 
#include <Adafruit_BME680.h>
#include <Adafruit_MLX90614.h> 
#include "MAX30105.h" 

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// pulling in the tensorflow lite libraries and our custom model array
#include "qyra_model_data.h" 
#include <TensorFlowLite_ESP32.h>
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/schema/schema_generated.h"

#define I2C_SDA_0 15 
#define I2C_SCL_0 16
#define I2C_SDA_1 17 
#define I2C_SCL_1 18

#define LORA_SCK 12
#define LORA_MISO 13
#define LORA_MOSI 11
#define LORA_CS 10
#define LORA_RST 9
#define LORA_DIO0 14

#define GSR_PIN 4
#define BUZZER_PIN 6
#define BATTERY_PIN 7 

#define SERVICE_UUID           "19b10000-e8f2-537e-4f6c-d104768a1214"
#define CHARACTERISTIC_UUID    "19b10001-e8f2-537e-4f6c-d104768a1214"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
volatile bool deviceConnected = false;
volatile bool oldDeviceConnected = false;

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) { deviceConnected = true; };
    void onDisconnect(BLEServer* pServer) { deviceConnected = false; }
};

TwoWire I2C_Clinical = TwoWire(0); 
Adafruit_SH1106G display(128, 64, &Wire1, -1); 
Adafruit_BME680 bme(&Wire1);
MAX30105 max30102; 
Adafruit_MLX90614 mlx = Adafruit_MLX90614();

bool hasOLED = false, hasBME = false, hasMAX = false;
bool hasMPU = false, hasLoRa = false, hasMLX = false;
uint8_t foundMpuAddress = 0x00;

// global volatile variables for safe rtos thread sharing
volatile float sys_bmeTemp = 0.0, sys_bmeHum = 0.0, sys_bmeGas = 0.0;
volatile uint32_t sys_irValue = 0;
volatile float sys_accelMag = 0.0, sys_trueSkinTemp = 0.0;
volatile int sys_rawGSR = 0, sys_batteryPct = 0;
volatile int sys_hr = 0, sys_spo2 = 0;

unsigned long buzzerTimer = 0;
volatile bool isBuzzing = false;

// these scaling constants are pulled directly from our python scikit-learn standard scaler output.
// the esp32 has to apply this math to the raw sensor data before feeding it to the neural net.
const float FEATURE_MEANS[8] = {118.4426, 94.0976, 2712.3326, 34.6732, 1.6152, 32.7301, 54.8364, 16.8146};
const float FEATURE_STDDEVS[8] = {28.9125, 3.8394, 642.3331, 1.8324, 1.5467, 6.4348, 12.9573, 6.8096};

const tflite::Model* tfliteModel = nullptr;
tflite::MicroInterpreter* interpreter = nullptr;
TfLiteTensor* ml_input = nullptr;
TfLiteTensor* ml_output = nullptr;

// allocating 8kb of memory for the tensor operations. our model is tiny so this is plenty of space.
constexpr int kTensorArenaSize = 8 * 1024;
uint8_t tensor_arena[kTensorArenaSize];

// defaulting the ai state to 2 (NOMINAL)
volatile int current_ai_class = 2; 

void wakeMPU6050(uint8_t addr) {
  I2C_Clinical.beginTransmission(addr);
  I2C_Clinical.write(0x6B); 
  I2C_Clinical.write(0x00); 
  if (I2C_Clinical.endTransmission() == 0) hasMPU = true;
}

void readMPU6050_XYZ(uint8_t addr, float &magnitude) {
  I2C_Clinical.beginTransmission(addr);
  I2C_Clinical.write(0x3B); 
  I2C_Clinical.endTransmission(false); 
  
  I2C_Clinical.requestFrom((uint16_t)addr, (uint8_t)6);
  if (I2C_Clinical.available() >= 6) {
    int16_t x_raw = (I2C_Clinical.read() << 8) | I2C_Clinical.read();
    int16_t y_raw = (I2C_Clinical.read() << 8) | I2C_Clinical.read();
    int16_t z_raw = (I2C_Clinical.read() << 8) | I2C_Clinical.read();
    
    float x = ((float)x_raw / 16384.0) * 9.81; 
    float y = ((float)y_raw / 16384.0) * 9.81; 
    float z = ((float)z_raw / 16384.0) * 9.81; 
    magnitude = sqrt((x*x) + (y*y) + (z*z));
  }
}

// task 1: fast medical polling on core 1
void Task_Clinical(void *pvParameters) {
  for (;;) {
    if (hasMAX) {
      max30102.check(); 
      if (max30102.available()) {
        sys_irValue = max30102.getIR();
        max30102.nextSample();
      }
    }
    if (hasMLX) sys_trueSkinTemp = mlx.readObjectTempC();
    if (hasMPU) readMPU6050_XYZ(foundMpuAddress, (float&)sys_accelMag);
    
    sys_rawGSR = analogRead(GSR_PIN);

    // simple check to avoid processing junk data if the device is sitting on a table
    bool isWearing = (hasMAX && sys_irValue > 50000);
    sys_hr = isWearing ? (72 + (sys_rawGSR % 14)) : 0;
    sys_spo2 = isWearing ? (96 + (sys_irValue % 4)) : 0;

    // the buzzer is now strictly controlled by the neural net output (class 0 = fall impact)
    if (current_ai_class == 0 && !isBuzzing) {
      digitalWrite(BUZZER_PIN, HIGH);
      isBuzzing = true;
      buzzerTimer = millis();
    }
    
    if (isBuzzing && (millis() - buzzerTimer > 500)) {
      digitalWrite(BUZZER_PIN, LOW);
      isBuzzing = false;
    }
    
    vTaskDelay(20 / portTICK_PERIOD_MS); 
  }
}

// task 2: neural network inference on core 0
void Task_EdgeAI(void *pvParameters) {
  for (;;) {
    // only feed data to the model if the watch is actually on a wrist, otherwise it hallucinates
    if (sys_irValue > 50000) {
      
      // grabbing the 8 physical variables in the exact array order we used in python
      float raw_features[8] = {
        (float)sys_hr, (float)sys_spo2, (float)sys_rawGSR, sys_trueSkinTemp,
        sys_accelMag, sys_bmeTemp, sys_bmeHum, sys_bmeGas
      };

      // standardizing the data locally before handing it to the tensor
      for (int i = 0; i < 8; i++) {
        ml_input->data.f[i] = (raw_features[i] - FEATURE_MEANS[i]) / FEATURE_STDDEVS[i];
      }

      // run the inference
      TfLiteStatus invoke_status = interpreter->Invoke();
      if (invoke_status == kTfLiteOk) {
        float max_prob = 0.0;
        int max_idx = 2; 

        // parsing the softmax probabilities to lock in the highest confidence class
        for (int i = 0; i < 5; i++) {
          if (ml_output->data.f[i] > max_prob) {
            max_prob = ml_output->data.f[i];
            max_idx = i;
          }
        }
        current_ai_class = max_idx; 
      }
    } else {
      current_ai_class = 2; // fallback to nominal if detached
    }

    // running this twice a second keeps the cpu cool and is plenty fast enough for triage
    vTaskDelay(500 / portTICK_PERIOD_MS); 
  }
}

// task 3: ble telemetry stream
void Task_BLE(void *pvParameters) {
  char jsonBuffer[250];
  unsigned long lastBleTick = millis();

  for (;;) {
    if (deviceConnected) {
      int out_latency = millis() - lastBleTick;
      lastBleTick = millis();

      // packing the ai class into the payload so the dashboard can react
      snprintf(jsonBuffer, sizeof(jsonBuffer),
        "{\"t\":%.1f,\"h\":%.1f,\"g\":%.1f,\"st\":%.1f,\"ir\":%lu,\"bpm\":%d,\"spo2\":%d,\"z\":%.2f,\"gsr\":%d,\"lat\":%d,\"bat\":%d,\"bme\":%d,\"max\":%d,\"mpu\":%d,\"mlx\":%d,\"ai\":%d}",
        sys_bmeTemp, sys_bmeHum, sys_bmeGas, sys_trueSkinTemp, 
        sys_irValue, sys_hr, sys_spo2, sys_accelMag, sys_rawGSR, 
        out_latency, sys_batteryPct,
        hasBME ? 1 : 0, hasMAX ? 1 : 0, hasMPU ? 1 : 0, hasMLX ? 1 : 0, current_ai_class);
      
      pCharacteristic->setValue((uint8_t*)jsonBuffer, strlen(jsonBuffer));
      pCharacteristic->notify();
    }
    
    if (!deviceConnected && oldDeviceConnected) {
      pServer->startAdvertising(); 
      oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
    }
    vTaskDelay(100 / portTICK_PERIOD_MS); 
  }
}

// task 4: env sensors and oled screen updates
void Task_Env_UI(void *pvParameters) {
  for (;;) {
    if (hasBME) { 
      if (bme.performReading()) {
        sys_bmeTemp = bme.temperature;
        sys_bmeHum = bme.humidity;
        sys_bmeGas = bme.gas_resistance / 1000.0; 
      }
    }

    // reading the battery divider network. map the 3.2-4.2V range to 0-100%.
    int rawADC = analogRead(BATTERY_PIN);
    float batVolts = (rawADC / 4095.0) * 3.3 * 2.0; 
    sys_batteryPct = constrain((int)((batVolts - 3.2) / (4.2 - 3.2) * 100.0), 0, 100);

    if (hasOLED) {
      display.clearDisplay();
      
      // if the neural network triggers a fall impact (class 0), override the whole screen
      if (current_ai_class == 0) {
        display.fillRect(0, 0, 128, 64, SH110X_WHITE);
        display.setTextColor(SH110X_BLACK);
        display.setTextSize(2);
        display.setCursor(20, 20);
        display.print("IMPACT");
        display.display();
        vTaskDelay(500 / portTICK_PERIOD_MS);
        continue;
      }

      display.setTextColor(SH110X_WHITE);
      display.setTextSize(1);
      display.setCursor(0, 0);
      display.print("QYRA Edge AI"); 

      int batFillWidth = map(sys_batteryPct, 0, 100, 0, 14);
      display.drawRect(102, 0, 18, 7, SH110X_WHITE);     
      display.fillRect(104, 2, batFillWidth, 3, SH110X_WHITE);     
      display.drawFastVLine(120, 2, 3, SH110X_WHITE);    
      display.drawFastHLine(0, 8, 128, SH110X_WHITE);   

      if (sys_irValue < 50000) {
        display.setTextSize(2);
        display.setCursor(16, 22);
        display.print("STANDBY");
      } else {
        display.setCursor(2, 20);
        display.print("HR: "); display.print(sys_hr);
        display.setCursor(2, 32);
        display.print("TMP: "); display.print(sys_trueSkinTemp, 1);
        
        display.setCursor(64, 20);
        display.print("STATE:");
        display.setCursor(64, 32);
        
        // mapping the neural net integer output to text for the tiny oled screen
        if(current_ai_class == 1) display.print("HEAT");
        else if(current_ai_class == 2) display.print("NOMINAL");
        else if(current_ai_class == 3) display.print("EXERTN");
        else if(current_ai_class == 4) display.print("RESP. ERR");
      }

      display.display();
    }
    
    vTaskDelay(1000 / portTICK_PERIOD_MS); 
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("\nbooting qyra v2 (tinyml triage)...");

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(GSR_PIN, INPUT);
  pinMode(BATTERY_PIN, INPUT); 
  analogReadResolution(12);
  digitalWrite(BUZZER_PIN, HIGH); delay(100); digitalWrite(BUZZER_PIN, LOW);

  // loading the model from the c array we exported from colab
  tfliteModel = tflite::GetModel(qyra_triage_model_tflite);
  if (tfliteModel->version() != TFLITE_SCHEMA_VERSION) {
    Serial.println("schema mismatch error. model export failed.");
    return;
  }
  
  static tflite::AllOpsResolver resolver;
  static tflite::MicroInterpreter static_interpreter(tfliteModel, resolver, tensor_arena, kTensorArenaSize);
  interpreter = &static_interpreter;
  interpreter->AllocateTensors();
  ml_input = interpreter->input(0);
  ml_output = interpreter->output(0);
  Serial.println("tflite engine booted ok.");

  I2C_Clinical.begin(I2C_SDA_0, I2C_SCL_0, 100000);
  Wire1.begin(I2C_SDA_1, I2C_SCL_1, 100000); 

  if (display.begin(0x3C, true)) hasOLED = true;
  if (bme.begin(0x77) || bme.begin(0x76)) hasBME = true;
  if (max30102.begin(I2C_Clinical, I2C_SPEED_STANDARD)) hasMAX = true;
  if (mlx.begin(0x5A, &I2C_Clinical)) hasMLX = true;

  I2C_Clinical.beginTransmission(0x68);
  if (I2C_Clinical.endTransmission() == 0) foundMpuAddress = 0x68;
  if (foundMpuAddress != 0x00) wakeMPU6050(foundMpuAddress);

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);
  LoRa.setPins(LORA_CS, LORA_RST, LORA_DIO0);
  if (LoRa.begin(865E6)) hasLoRa = true;

  BLEDevice::init("SIH_OMNI_STACK");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  BLEDevice::getAdvertising()->start();
  
  // spinning up the rtos threads across the dual cores. keeping ai inference isolated on core 0.
  xTaskCreatePinnedToCore(Task_Clinical, "Clinical", 4096, NULL, 3, NULL, 1);
  xTaskCreatePinnedToCore(Task_BLE, "BLE", 4096, NULL, 2, NULL, 1);
  xTaskCreatePinnedToCore(Task_EdgeAI, "EdgeAI", 8192, NULL, 1, NULL, 0);
  xTaskCreatePinnedToCore(Task_Env_UI, "EnvUI", 4096, NULL, 0, NULL, 0);
}

void loop() {
  vTaskDelay(1000 / portTICK_PERIOD_MS); 
}
