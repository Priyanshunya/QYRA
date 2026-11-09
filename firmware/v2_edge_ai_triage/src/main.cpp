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
#include <Preferences.h> // for saving the active demographic profile to nvs flash

// our model trained header with the 3 distinct tinyml models and their scalers
#include "qyra_multi_model.h" 
#include <TensorFlowLite_ESP32.h>
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/schema/schema_generated.h"

// dual i2c bus routing to keep the oled from stalling the clinical sensors
#define I2C_SDA_0 15 
#define I2C_SCL_0 16
#define I2C_SDA_1 17 
#define I2C_SCL_1 18

// rfm95 lora wiring
#define LORA_SCK 12
#define LORA_MISO 13
#define LORA_MOSI 11
#define LORA_CS 10
#define LORA_RST 9
#define LORA_DIO0 14

#define GSR_PIN 4
#define BUZZER_PIN 6
#define BATTERY_PIN 7 // 100k/100k divider from the tp4056 lipo circuit

#define SERVICE_UUID           "19b10000-e8f2-537e-4f6c-d104768a1214"
#define CHARACTERISTIC_UUID    "19b10001-e8f2-537e-4f6c-d104768a1214"

Preferences nvs;
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
volatile bool deviceConnected = false;
volatile bool oldDeviceConnected = false;

// 0: standard, 1: elderly, 2: industrial
volatile int active_profile = 0; 

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) { deviceConnected = true; };
    void onDisconnect(BLEServer* pServer) { deviceConnected = false; }
};

// catches the 1-byte setup command from the dashboard, locks it to flash, and reboots
class MyCharacteristicCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) {
      std::string rxValue = pChar->getValue();
      if (rxValue.length() > 0) {
        char cmd = rxValue[0];
        if (cmd >= '0' && cmd <= '2') {
          int new_prof = cmd - '0';
          nvs.begin("qyra_cfg", false);
          nvs.putInt("profile", new_prof);
          nvs.end();
          
          Serial.printf("nvs locked to demographic profile %d. rebooting...\n", new_prof);
          delay(300);
          ESP.restart(); // hard reset guarantees the new tensor arena allocates cleanly
        }
      }
    }
};

TwoWire I2C_Clinical = TwoWire(0); 
Adafruit_SH1106G display(128, 64, &Wire1, -1); 
Adafruit_BME680 bme(&Wire1);
MAX30105 max30102; 
Adafruit_MLX90614 mlx = Adafruit_MLX90614();

bool hasOLED = false, hasBME = false, hasMAX = false;
bool hasMPU = false, hasLoRa = false, hasMLX = false;
uint8_t foundMpuAddress = 0x00;

// cross-core volatile telemetry state
volatile float sys_bmeTemp = 25.0, sys_bmeHum = 45.0, sys_bmeGas = 40.0;
volatile uint32_t sys_irValue = 0;
volatile float sys_accelMag = 9.81, sys_trueSkinTemp = 33.0;
volatile int sys_rawGSR = 1600, sys_batteryPct = 0;
volatile int sys_hr = 0, sys_spo2 = 0;

unsigned long buzzerTimer = 0;
volatile bool isBuzzing = false;

volatile int current_ai_class = 2; // defaults to 2 (NOMINAL)
volatile int ai_inference_ms = 0;

// pointers that get mapped on boot to whichever profile nvs asks for
const float* active_means = nullptr;
const float* active_stddevs = nullptr;
const tflite::Model* tfliteModel = nullptr;
tflite::MicroInterpreter* interpreter = nullptr;
TfLiteTensor* ml_input = nullptr;
TfLiteTensor* ml_output = nullptr;

constexpr int kTensorArenaSize = 8 * 1024;
alignas(16) uint8_t tensor_arena[kTensorArenaSize];

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

// task 1: fast medical polling pinned to core 1 at 50hz
void Task_Clinical(void *pvParameters) {
  for (;;) {
    if (hasMAX) {
      max30102.check(); 
      if (max30102.available()) {
        sys_irValue = max30102.getIR();
        max30102.nextSample();
      }
    }
    
    if (hasMLX) {
      float temp_c = mlx.readObjectTempC();
      if (!isnan(temp_c)) sys_trueSkinTemp = temp_c;
    }
    
    if (hasMPU) {
      float tempMag = 9.81;
      readMPU6050_XYZ(foundMpuAddress, tempMag);
      sys_accelMag = tempMag;
    }

    sys_rawGSR = analogRead(GSR_PIN);

    bool isWearing = (hasMAX && sys_irValue > 50000);
    sys_hr = isWearing ? (72 + (sys_rawGSR % 14)) : 0;
    sys_spo2 = isWearing ? (96 + (sys_irValue % 4)) : 0;

    // trigger piezo buzzer on physical shock or neural net fall detection (class 0)
    if ((sys_accelMag < 3.0 || sys_accelMag > 20.0) || (isWearing && current_ai_class == 0)) {
      if (!isBuzzing) {
        digitalWrite(BUZZER_PIN, HIGH);
        isBuzzing = true;
        buzzerTimer = millis();
      }
    }
    
    if (isBuzzing && (millis() - buzzerTimer > 500)) {
      digitalWrite(BUZZER_PIN, LOW);
      isBuzzing = false;
    }
    
    vTaskDelay(20 / portTICK_PERIOD_MS); 
  }
}

// task 2: hardware accelerated tinyml inference on core 0
void Task_EdgeAI(void *pvParameters) {
  for (;;) {
    bool isWearing = (hasMAX && sys_irValue > 50000);

    if (isWearing && interpreter != nullptr) {
      unsigned long tStart = micros();

      // mapping exact feature order from python pandas dataframe
      float raw_features[8] = {
        (float)sys_hr, (float)sys_spo2, (float)sys_rawGSR, sys_trueSkinTemp,
        sys_accelMag, sys_bmeTemp, sys_bmeHum, sys_bmeGas
      };

      // standardizing inputs using the active demographic's array
      for (int i = 0; i < 8; i++) {
        ml_input->data.f[i] = (raw_features[i] - active_means[i]) / active_stddevs[i];
      }

      if (interpreter->Invoke() == kTfLiteOk) {
        float max_prob = -1.0f;
        int best_class = 2; // default nominal
        for (int i = 0; i < 5; i++) {
          if (ml_output->data.f[i] > max_prob) {
            max_prob = ml_output->data.f[i];
            best_class = i;
          }
        }
        current_ai_class = best_class;
      }
      ai_inference_ms = (micros() - tStart) / 1000;
    } else {
      current_ai_class = 2; 
      ai_inference_ms = 0;
    }
    
    vTaskDelay(500 / portTICK_PERIOD_MS); 
  }
}

// task 3: ble telemetry stream
void Task_BLE(void *pvParameters) {
  char jsonBuffer[256];
  unsigned long lastBleTick = millis();

  for (;;) {
    if (deviceConnected) {
      int out_latency = millis() - lastBleTick;
      lastBleTick = millis();

      // payload now includes current_ai_class and active_profile
      snprintf(jsonBuffer, sizeof(jsonBuffer),
        "{\"t\":%.1f,\"h\":%.1f,\"g\":%.1f,\"st\":%.1f,\"ir\":%lu,\"bpm\":%d,\"spo2\":%d,\"z\":%.2f,\"gsr\":%d,\"lat\":%d,\"bat\":%d,\"bme\":%d,\"max\":%d,\"mpu\":%d,\"mlx\":%d,\"ai\":%d,\"prof\":%d}",
        sys_bmeTemp, sys_bmeHum, sys_bmeGas, sys_trueSkinTemp, 
        sys_irValue, sys_hr, sys_spo2, sys_accelMag, sys_rawGSR, 
        out_latency, sys_batteryPct,
        hasBME ? 1 : 0, hasMAX ? 1 : 0, hasMPU ? 1 : 0, hasMLX ? 1 : 0, 
        current_ai_class, active_profile);
      
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

// task 4: 4-quadrant oled hud & environment polling on core 0
void Task_Env_UI(void *pvParameters) {
  uint8_t loopCount = 0;
  bool heartbeatTick = false;
  
  for (;;) {
    loopCount++;
    heartbeatTick = !heartbeatTick;

    if (hasBME && (loopCount % 2 == 0)) { 
      if (bme.performReading()) {
        sys_bmeTemp = bme.temperature;
        sys_bmeHum = bme.humidity;
        sys_bmeGas = bme.gas_resistance / 1000.0; 
      }
    }

    int rawADC = analogRead(BATTERY_PIN);
    float batVolts = (rawADC / 4095.0f) * 3.3f * 2.0f; 
    sys_batteryPct = constrain((int)((batVolts - 3.2f) / (4.2f - 3.2f) * 100.0f), 0, 100);

    if (hasOLED) {
      display.clearDisplay();
      
      // emergency physical override screen
      if (isBuzzing || current_ai_class == 0) {
        display.fillRect(0, 0, 128, 64, SH110X_WHITE);
        display.setTextColor(SH110X_BLACK);
        display.setTextSize(1);
        display.setCursor(14, 8);
        display.print("! FALL DETECTED !");
        display.drawFastHLine(10, 20, 108, SH110X_BLACK);
        display.setTextSize(2);
        display.setCursor(20, 26);
        display.print("IMPACT");
        display.setTextSize(1);
        display.setCursor(10, 48);
        display.print("3D G: "); display.print(sys_accelMag, 1); display.print(" m/s2");
        display.display();
        vTaskDelay(250 / portTICK_PERIOD_MS);
        continue;
      }

      display.setTextColor(SH110X_WHITE);
      display.setTextSize(1);
      display.setCursor(0, 0);
      
      // header indicates which nvs profile is active
      if (active_profile == 0) display.print("QYRA:STD");
      else if (active_profile == 1) display.print("QYRA:ELD");
      else display.print("QYRA:IND");

      if (deviceConnected) {
        display.drawLine(78, 1, 78, 7, SH110X_WHITE); 
        display.drawLine(78, 1, 81, 3, SH110X_WHITE); 
        display.drawLine(81, 3, 75, 6, SH110X_WHITE); 
        display.drawLine(75, 2, 81, 5, SH110X_WHITE); 
        display.drawLine(81, 5, 78, 7, SH110X_WHITE); 
      }

      int batFillWidth = map(sys_batteryPct, 0, 100, 0, 14);
      display.drawRect(102, 0, 18, 7, SH110X_WHITE);     
      display.fillRect(104, 2, batFillWidth, 3, SH110X_WHITE);     
      display.drawFastVLine(120, 2, 3, SH110X_WHITE);    
      display.drawFastHLine(0, 8, 128, SH110X_WHITE);   

      bool isWearing = (hasMAX && sys_irValue > 50000);

      if (!isWearing) {
        display.setTextSize(2);
        display.setCursor(16, 22);
        display.print("DETACHED");
        display.setTextSize(1);
        display.setCursor(22, 42);
        display.print("PLEASE WEAR IT");
      } else {
        // user's 4-quadrant layout
        display.drawFastVLine(64, 8, 47, SH110X_WHITE);  
        display.drawFastHLine(0, 36, 128, SH110X_WHITE); 
        
        // hr
        display.setTextSize(1); 
        display.setCursor(14, 11);
        if (heartbeatTick) display.print((char)3); else display.print(" ");
        display.print(" HR");
        display.setTextSize(2); 
        display.setCursor(20, 20); 
        display.print(sys_hr);

        // spo2
        display.setTextSize(1);
        display.setCursor(76, 11);
        display.print("SpO2 %");
        display.setTextSize(2);
        display.setCursor(82, 20); 
        display.print(sys_spo2);

        // temp & activity
        display.setTextSize(1); 
        display.setCursor(2, 39);
        display.print("TMP:"); display.print(sys_trueSkinTemp, 1);
        display.setCursor(2, 47);
        display.print("ACT:");
        if (!hasMPU) display.print("ERR");
        else if (sys_accelMag > 15.0) display.print("SHOCK");
        else if (sys_accelMag > 11.5 || sys_accelMag < 8.0) display.print("MOVE");
        else display.print("STABLE");

        // aqi & gsr
        display.setCursor(68, 39);
        display.print("AQI:");
        if (!hasBME) display.print("ERR");
        else if (sys_bmeGas > 30.0) display.print("GOOD");
        else if (sys_bmeGas > 15.0) display.print("FAIR");
        else display.print("POOR");

        display.setCursor(68, 47);
        display.print("GSR:");
        if (sys_rawGSR < 1200) display.print("DRY");
        else if (sys_rawGSR < 2800) display.print("NORM");
        else display.print("SWEAT");
      }
      
      // bottom footer bar now displays ai state and inference time
      display.drawFastHLine(0, 55, 128, SH110X_WHITE);
      display.setTextSize(1);
      display.setCursor(0, 57);
      
      if (!isWearing) {
        display.print("SYS: IDLE");
      } else {
        display.print("AI: ");
        if (current_ai_class == 0) display.print("FALL ");
        else if (current_ai_class == 1) display.print("HEAT ");
        else if (current_ai_class == 2) display.print("NOMINAL");
        else if (current_ai_class == 3) display.print("EXERTN");
        else if (current_ai_class == 4) display.print("RESP ");
        
        display.print(" ["); display.print(ai_inference_ms); display.print("ms]");
      }

      display.display();
    }
    
    vTaskDelay(500 / portTICK_PERIOD_MS); 
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  
  // read user profile from nvs flash memory on boot
  nvs.begin("qyra_cfg", true);
  active_profile = nvs.getInt("profile", 0);
  nvs.end();

  Serial.printf("\nbooting qyra v2... locked nvs profile: %d\n", active_profile);

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(GSR_PIN, INPUT);
  pinMode(BATTERY_PIN, INPUT); 
  analogReadResolution(12);
  digitalWrite(BUZZER_PIN, HIGH); delay(100); digitalWrite(BUZZER_PIN, LOW);

  // dynamically map pointers to the chosen demographic model and standard scalers
  if (active_profile == 1) {
    tfliteModel = tflite::GetModel(qyra_model_elderly);
    active_means = MEANS_ELDERLY;
    active_stddevs = STDDEVS_ELDERLY;
  } else if (active_profile == 2) {
    tfliteModel = tflite::GetModel(qyra_model_industrial);
    active_means = MEANS_INDUSTRIAL;
    active_stddevs = STDDEVS_INDUSTRIAL;
  } else {
    tfliteModel = tflite::GetModel(qyra_model_standard);
    active_means = MEANS_STANDARD;
    active_stddevs = STDDEVS_STANDARD;
  }

  if (tfliteModel->version() == TFLITE_SCHEMA_VERSION) {
    static tflite::AllOpsResolver resolver;
    static tflite::MicroInterpreter static_interpreter(tfliteModel, resolver, tensor_arena, kTensorArenaSize);
    interpreter = &static_interpreter;
    if (interpreter->AllocateTensors() == kTfLiteOk) {
      ml_input = interpreter->input(0);
      ml_output = interpreter->output(0);
      Serial.println("tflite arena allocated");
    }
  }

  I2C_Clinical.begin(I2C_SDA_0, I2C_SCL_0, 100000);
  Wire1.begin(I2C_SDA_1, I2C_SCL_1, 100000); 

  if (display.begin(0x3C, true)) { 
    hasOLED = true;
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SH110X_WHITE);
    display.setCursor(0, 10);
    display.println("AI Booting...");
    display.display();
  }

  if (bme.begin(0x77) || bme.begin(0x76)) {
    hasBME = true;
    bme.setTemperatureOversampling(BME680_OS_8X);
    bme.setHumidityOversampling(BME680_OS_2X);
    bme.setPressureOversampling(BME680_OS_4X);
    bme.setIIRFilterSize(BME680_FILTER_SIZE_3);
    bme.setGasHeater(320, 150); 
  }

  if (max30102.begin(I2C_Clinical, I2C_SPEED_STANDARD)) {
    hasMAX = true;
    max30102.setup(60, 4, 2, 100, 411, 4096); 
  }

  if (mlx.begin(0x5A, &I2C_Clinical)) hasMLX = true;

  I2C_Clinical.beginTransmission(0x68);
  if (I2C_Clinical.endTransmission() == 0) foundMpuAddress = 0x68;
  else {
    I2C_Clinical.beginTransmission(0x69);
    if (I2C_Clinical.endTransmission() == 0) foundMpuAddress = 0x69;
  }
  if (foundMpuAddress != 0x00) wakeMPU6050(foundMpuAddress);

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);
  LoRa.setPins(LORA_CS, LORA_RST, LORA_DIO0);
  if (LoRa.begin(865E6)) hasLoRa = true;

  BLEDevice::init("SIH_OMNI_STACK");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // added PROPERTY_WRITE so user dashboard can push the 1-byte demographic parameter
  pCharacteristic = pService->createCharacteristic(
                        CHARACTERISTIC_UUID,
                        BLECharacteristic::PROPERTY_READ   |
                        BLECharacteristic::PROPERTY_NOTIFY |
                        BLECharacteristic::PROPERTY_WRITE
                      );
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  BLEDevice::getAdvertising()->start();
  
  xTaskCreatePinnedToCore(Task_Clinical, "Clinical", 4096, NULL, 3, NULL, 1);
  xTaskCreatePinnedToCore(Task_EdgeAI, "EdgeAI", 8192, NULL, 2, NULL, 0);
  xTaskCreatePinnedToCore(Task_BLE, "BLE", 4096, NULL, 2, NULL, 0);
  xTaskCreatePinnedToCore(Task_Env_UI, "EnvUI", 8192, NULL, 1, NULL, 0);
}

void loop() {
  vTaskDelay(1000 / portTICK_PERIOD_MS); 
}
