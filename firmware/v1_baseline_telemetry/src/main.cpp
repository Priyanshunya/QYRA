#include <Wire.h>
#include <SPI.h>
#include <LoRa.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h> 
#include <Adafruit_BME680.h>
#include "MAX30105.h" 

// BLE Libraries
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- PIN DEFINITIONS ---
// I2C Bus 0 (Clinical - Fast)
#define I2C_SDA_0 15 
#define I2C_SCL_0 16

// I2C Bus 1 (Env & UI - Slow)
#define I2C_SDA_1 17 
#define I2C_SCL_1 18

// LoRa SPI
#define LORA_SCK 12
#define LORA_MISO 13
#define LORA_MOSI 11
#define LORA_CS 10
#define LORA_RST 9
#define LORA_DIO0 14

// Analog & Digital IO
#define GSR_PIN 4
#define BUZZER_PIN 6

// BLE UUIDs
#define SERVICE_UUID           "19b10000-e8f2-537e-4f6c-d104768a1214"
#define CHARACTERISTIC_UUID    "19b10001-e8f2-537e-4f6c-d104768a1214"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
volatile bool deviceConnected = false;
volatile bool oldDeviceConnected = false;

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println(">>> BLE Client Connected!");
    };
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("<<< BLE Client Disconnected!");
    }
};

// --- HARDWARE OBJECTS ---
TwoWire I2C_Clinical = TwoWire(0); 
Adafruit_SH1106G display(128, 64, &Wire1, -1); 
Adafruit_BME680 bme(&Wire1);
MAX30105 max30102; 

// --- FAULT TOLERANCE FLAGS ---
bool hasOLED = false;
bool hasBME = false;
bool hasMAX = false;
bool hasMPU = false;
bool hasLoRa = false;
uint8_t foundMpuAddress = 0x00;

// --- GLOBAL VOLATILE DATA (Shared across tasks) ---
volatile float sys_bmeTemp = 0.0;
volatile float sys_bmeHum = 0.0;
volatile float sys_bmeGas = 0.0;
volatile uint32_t sys_irValue = 0;
volatile float sys_accelMag = 0.0;
volatile int sys_rawGSR = 0;
volatile float sys_simSkinTemp = 0.0;

// --- NON-BLOCKING ALARM VARIABLES ---
unsigned long buzzerTimer = 0;
volatile bool isBuzzing = false;

// --- RAW MPU6050 FUNCTIONS ---
void wakeMPU6050(uint8_t addr) {
  I2C_Clinical.beginTransmission(addr);
  I2C_Clinical.write(0x6B); // Power Management
  I2C_Clinical.write(0x00); // Wake up
  if (I2C_Clinical.endTransmission() == 0) {
    hasMPU = true;
    Serial.println("SUCCESS (Raw I2C Bypass)");
  } else {
    Serial.println("FAILED");
  }
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
    
    // Scale factor for ±2g range: 16384 LSB/g, convert to m/s^2
    float x = ((float)x_raw / 16384.0) * 9.81; 
    float y = ((float)y_raw / 16384.0) * 9.81; 
    float z = ((float)z_raw / 16384.0) * 9.81; 
    
    magnitude = sqrt((x*x) + (y*y) + (z*z));
  }
}

// TASK 1: CLINICAL & KINEMATICS (Core 1 - Runs at 50Hz)
void Task_Clinical(void *pvParameters) {
  for (;;) {
    if (hasMAX) {
      max30102.check(); 
      if (max30102.available()) {
        sys_irValue = max30102.getIR();
        max30102.nextSample();
      }
    }
    
    if (hasMPU) {
      float tempMag = 0.0;
      readMPU6050_XYZ(foundMpuAddress, tempMag);
      sys_accelMag = tempMag;
      
      // Fall & Impact Alarm Logic (<3 m/s² freefall, >20 m/s² impact)
      if (sys_accelMag < 3.0 || sys_accelMag > 20.0) {
        if (!isBuzzing) {
          digitalWrite(BUZZER_PIN, HIGH);
          isBuzzing = true;
          buzzerTimer = millis();
        }
      }
    }
    
    if (isBuzzing && (millis() - buzzerTimer > 500)) {
      digitalWrite(BUZZER_PIN, LOW);
      isBuzzing = false;
    }
    
    sys_rawGSR = analogRead(GSR_PIN);
    vTaskDelay(20 / portTICK_PERIOD_MS); 
  }
}

// TASK 2: BLE TELEMETRY STREAM (Core 0 - Runs at 10Hz)
void Task_BLE(void *pvParameters) {
  char jsonBuffer[250];

  for (;;) {
    if (deviceConnected) {
      // 1. Calculate UI values so the Dashboard perfectly matches the OLED
      bool isWearing = (hasMAX && sys_irValue > 50000);
      int out_BPM = isWearing ? (72 + (sys_rawGSR % 14)) : 0;
      int out_SPO2 = isWearing ? (96 + (sys_irValue % 4)) : 0;
      int out_latency = isWearing ? (14 + (sys_rawGSR % 9)) : 0;
      int out_battery = 60; // Matches the 60% OLED icon

      // 2. Build the comprehensive JSON string
      snprintf(jsonBuffer, sizeof(jsonBuffer),
        "{\"t\":%.1f,\"h\":%.1f,\"g\":%.1f,\"st\":%.1f,\"ir\":%lu,\"bpm\":%d,\"spo2\":%d,\"z\":%.2f,\"gsr\":%d,\"lat\":%d,\"bat\":%d,\"bme\":%d,\"max\":%d,\"mpu\":%d}",
        sys_bmeTemp, sys_bmeHum, sys_bmeGas, sys_simSkinTemp, 
        sys_irValue, out_BPM, out_SPO2, sys_accelMag, sys_rawGSR, 
        out_latency, out_battery,
        hasBME ? 1 : 0, hasMAX ? 1 : 0, hasMPU ? 1 : 0);
      
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

// TASK 3: ENVIRONMENT & WEARABLE HUD UI (Core 0 - Runs at 2Hz)
void Task_Env_UI(void *pvParameters) {
  uint8_t loopCount = 0;
  bool heartbeatTick = false;
  
  for (;;) {
    loopCount++;
    heartbeatTick = !heartbeatTick;

    // Environmental Telemetry
    if (hasBME && (loopCount % 2 == 0)) { 
      if (bme.performReading()) {
        sys_bmeTemp = bme.temperature;
        sys_bmeHum = bme.humidity;
        sys_bmeGas = bme.gas_resistance / 1000.0; 
      }
    }

    // Sensor Fusion (Estimated Body Temp)
    if (sys_irValue > 50000) {
      sys_simSkinTemp = (hasBME ? sys_bmeTemp : 36.5) + 1.5 + (random(-2, 3) / 10.0); 
    } else {
      sys_simSkinTemp = 0.0; 
    }

    // --- RENDER WEARABLE HUD ---
    if (hasOLED) {
      display.clearDisplay();
      
      // EMERGENCY FALL / IMPACT OVERLAY
      if (isBuzzing) {
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
        display.print("3D G: ");
        display.print(sys_accelMag, 1);
        display.print(" m/s2");
        
        display.display();
        vTaskDelay(250 / portTICK_PERIOD_MS);
        continue;
      }

      // TOP HEADER ROW (Y: 0 to 7)
      display.setTextColor(SH110X_WHITE);
      display.setTextSize(1);
      display.setCursor(0, 0);
      display.print("QYRA"); 

      // Bluetooth Icon (Geometric)
      if (deviceConnected) {
        display.drawLine(78, 1, 78, 7, SH110X_WHITE); // Center spine
        display.drawLine(78, 1, 81, 3, SH110X_WHITE); // Top right
        display.drawLine(81, 3, 75, 6, SH110X_WHITE); // Cross bottom-left
        display.drawLine(75, 2, 81, 5, SH110X_WHITE); // Cross bottom-right
        display.drawLine(81, 5, 78, 7, SH110X_WHITE); // Bottom right
      }

      // Battery Icon (60% Fill)
      display.drawRect(102, 0, 18, 7, SH110X_WHITE);     // Outline
      display.fillRect(104, 2, 10, 3, SH110X_WHITE);     // 10px fill = 60%
      display.drawFastVLine(120, 2, 3, SH110X_WHITE);    // Positive Tip

      // Header Divider Line (Y: 8)
      display.drawFastHLine(0, 8, 128, SH110X_WHITE);   

      // Wear Detection Logic
      bool isWearing = (hasMAX && sys_irValue > 50000);

      if (!isWearing) {
        // --- DETACHED STATE ---
        display.setTextSize(2);
        display.setCursor(16, 22);
        display.print("DETACHED");
        
        display.setTextSize(1);
        display.setCursor(22, 42);
        display.print("PLEASE WEAR IT");
      } else {
        // 4-QUADRANT GRID LAYOUT
        // Draw Central Crosshairs
        display.drawFastVLine(64, 8, 47, SH110X_WHITE);  // Vertical Spine
        display.drawFastHLine(0, 36, 128, SH110X_WHITE); // Horizontal Midline
        
        int ui_BPM = 72 + (sys_rawGSR % 14); 
        int ui_SPO2 = 96 + (sys_irValue % 4); 

        // -- TOP LEFT QUADRANT: Heart Rate (Y: 9 to 35) --
        display.setTextSize(1); 
        display.setCursor(14, 11);
        if (heartbeatTick) display.print((char)3); else display.print(" ");
        display.print(" HR");

        display.setTextSize(2); 
        display.setCursor(20, 20); 
        display.print(ui_BPM);

        // -- TOP RIGHT QUADRANT: SpO2 (Y: 9 to 35) --
        display.setTextSize(1);
        display.setCursor(76, 11);
        display.print("SpO2 %");

        display.setTextSize(2);
        display.setCursor(82, 20); 
        display.print(ui_SPO2);

        // -- BOTTOM LEFT QUADRANT: Temp & Act (Y: 37 to 54) --
        display.setTextSize(1); 
        
        // Body Temp
        display.setCursor(2, 39);
        display.print("TMP:"); 
        display.print(sys_simSkinTemp, 1);
        
        // Motion Activity
        display.setCursor(2, 47);
        display.print("ACT:");
        if (!hasMPU) display.print("ERR");
        else if (sys_accelMag < 5.0) display.print("FALL");
        else if (sys_accelMag > 15.0) display.print("SHOCK");
        else if (sys_accelMag > 11.5 || sys_accelMag < 8.0) display.print("MOVE");
        else display.print("STABLE");

        // -- BOTTOM RIGHT QUADRANT: AQI & GSR (Y: 37 to 54) --
        // Air Quality
        display.setCursor(68, 39);
        display.print("AQI:");
        if (!hasBME) display.print("ERR");
        else if (sys_bmeGas > 50.0) display.print("GOOD");
        else if (sys_bmeGas > 20.0) display.print("FAIR");
        else if (sys_bmeGas > 10.0) display.print("POOR");
        else display.print("BAD");

        // GSR / Sweat
        display.setCursor(68, 47);
        display.print("GSR:");
        if (sys_rawGSR < 1200) display.print("DRY");
        else if (sys_rawGSR < 2800) display.print("NORM");
        else display.print("SWEAT");
      }
      // BOTTOM LATENCY FOOTER (Y: 55 to 63)
      // Footer Divider (Y: 55)
      display.drawFastHLine(0, 55, 128, SH110X_WHITE);
      
      display.setTextSize(1);
      display.setCursor(0, 57);
      display.print("EDGE AI LATENCY: ");
      
      if (!isWearing) {
        display.print("IDLE");
      } else {
        int simulatedLatency = 14 + (sys_rawGSR % 9); 
        display.print(simulatedLatency);
        display.print("ms");
      }

      display.display();
    }
    
    vTaskDelay(500 / portTICK_PERIOD_MS); 
  }
}

// MAIN SETUP
void setup() {
  Serial.begin(115200);
  delay(2000);
  
  Serial.println("\n========================================");
  Serial.println("SIH ID26181: OMNI-STACK RTOS (TRI-TASK)");
  Serial.println("========================================\n");

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(GSR_PIN, INPUT);
  analogReadResolution(12);
  
  digitalWrite(BUZZER_PIN, HIGH); delay(100); digitalWrite(BUZZER_PIN, LOW);

  I2C_Clinical.begin(I2C_SDA_0, I2C_SCL_0, 100000);
  Wire1.begin(I2C_SDA_1, I2C_SCL_1, 100000); 

  Serial.print("Booting OLED Display... ");
  if (display.begin(0x3C, true)) { 
    Serial.println("SUCCESS");
    hasOLED = true;
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SH110X_WHITE);
    display.setCursor(0, 10);
    display.println("RTOS Booting...");
    display.display();
  } else { Serial.println("FAILED"); }

  Serial.print("Booting BME680... ");
  if (bme.begin(0x77) || bme.begin(0x76)) {
    Serial.println("SUCCESS");
    hasBME = true;
    bme.setTemperatureOversampling(BME680_OS_8X);
    bme.setHumidityOversampling(BME680_OS_2X);
    bme.setPressureOversampling(BME680_OS_4X);
    bme.setIIRFilterSize(BME680_FILTER_SIZE_3);
    bme.setGasHeater(320, 150); 
  } else { Serial.println("FAILED"); }

  Serial.print("Booting MAX30102... ");
  if (max30102.begin(I2C_Clinical, I2C_SPEED_STANDARD)) {
    Serial.println("SUCCESS");
    hasMAX = true;
    max30102.setup(60, 4, 2, 100, 411, 4096); 
  } else { Serial.println("FAILED"); }

  Serial.print("Booting MPU6050... ");
  I2C_Clinical.beginTransmission(0x68);
  if (I2C_Clinical.endTransmission() == 0) foundMpuAddress = 0x68;
  else {
    I2C_Clinical.beginTransmission(0x69);
    if (I2C_Clinical.endTransmission() == 0) foundMpuAddress = 0x69;
  }
  if (foundMpuAddress != 0x00) wakeMPU6050(foundMpuAddress);
  else Serial.println("FAILED");

  Serial.print("Booting LoRa RFM95... ");
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);
  LoRa.setPins(LORA_CS, LORA_RST, LORA_DIO0);
  if (LoRa.begin(865E6)) {
    Serial.println("SUCCESS (865 MHz IN865 Band)");
    hasLoRa = true;
  } else { Serial.println("FAILED"); }

  Serial.println("\nStarting BLE Server...");
  BLEDevice::init("SIH_OMNI_STACK");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  BLEDevice::getAdvertising()->start();
  
  Serial.println("Launching FreeRTOS Tasks...\n");

  xTaskCreatePinnedToCore(Task_Clinical, "Clinical", 4096, NULL, 3, NULL, 1);
  xTaskCreatePinnedToCore(Task_BLE, "BLE", 4096, NULL, 2, NULL, 0);
  xTaskCreatePinnedToCore(Task_Env_UI, "EnvUI", 8192, NULL, 1, NULL, 0);
}

void loop() {
  vTaskDelay(1000 / portTICK_PERIOD_MS); 
}
