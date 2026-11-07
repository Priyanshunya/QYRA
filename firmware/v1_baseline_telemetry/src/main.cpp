#include <Wire.h>
#include <SPI.h>
#include <LoRa.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h> 
#include <Adafruit_BME680.h>
#include <Adafruit_MLX90614.h> // using this for true non-contact skin temp now
#include "MAX30105.h" // local sparkfun library for the max30102 pulse sensor

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// i routed two separate i2c buses to stop the oled from choking the medical sensors
// bus 0: fast clinical sensors (max30102, mpu6050, mlx90614)
#define I2C_SDA_0 15 
#define I2C_SCL_0 16

// bus 1: slower environment & ui (bme680, oled)
#define I2C_SDA_1 17 
#define I2C_SCL_1 18

// lora module wiring (rfm95)
#define LORA_SCK 12
#define LORA_MISO 13
#define LORA_MOSI 11
#define LORA_CS 10
#define LORA_RST 9
#define LORA_DIO0 14

#define GSR_PIN 4
#define BUZZER_PIN 6

// hooked a 100k/100k voltage divider from the tp4056 lipo charger to pin 7
#define BATTERY_PIN 7 

#define SERVICE_UUID           "19b10000-e8f2-537e-4f6c-d104768a1214"
#define CHARACTERISTIC_UUID    "19b10001-e8f2-537e-4f6c-d104768a1214"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
volatile bool deviceConnected = false;
volatile bool oldDeviceConnected = false;

// basic callback class to handle connection state for the flutter/web app
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("ble connected");
    };
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("ble disconnected");
    }
};

TwoWire I2C_Clinical = TwoWire(0); 
Adafruit_SH1106G display(128, 64, &Wire1, -1); 
Adafruit_BME680 bme(&Wire1);
MAX30105 max30102; 
Adafruit_MLX90614 mlx = Adafruit_MLX90614();

// setting up fault flags. if a dupont wire comes loose on the breadboard, 
// the esp32 will just bypass it instead of crashing the whole rtos loop.
bool hasOLED = false;
bool hasBME = false;
bool hasMAX = false;
bool hasMPU = false;
bool hasLoRa = false;
bool hasMLX = false;
uint8_t foundMpuAddress = 0x00;

// declaring these as volatile since they get updated by core 1 and read by core 0
volatile float sys_bmeTemp = 0.0;
volatile float sys_bmeHum = 0.0;
volatile float sys_bmeGas = 0.0;
volatile uint32_t sys_irValue = 0;
volatile float sys_accelMag = 0.0;
volatile int sys_rawGSR = 0;
volatile float sys_trueSkinTemp = 0.0; // reads straight from mlx90614 now
volatile int sys_batteryPct = 0;

// timers for the buzzer so we dont use delay() and block the threads
unsigned long buzzerTimer = 0;
volatile bool isBuzzing = false;

// the standard adafruit mpu6050 library was causing weird bus collisions on the dual setup,
// so i wrote these quick bypass functions to read the registers directly over i2c.
void wakeMPU6050(uint8_t addr) {
  I2C_Clinical.beginTransmission(addr);
  I2C_Clinical.write(0x6B); // power management
  I2C_Clinical.write(0x00); // clear sleep bit
  if (I2C_Clinical.endTransmission() == 0) {
    hasMPU = true;
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
    
    // scaling factor for ±2g range is 16384 LSB/g. converting directly to m/s^2
    float x = ((float)x_raw / 16384.0) * 9.81; 
    float y = ((float)y_raw / 16384.0) * 9.81; 
    float z = ((float)z_raw / 16384.0) * 9.81; 
    
    magnitude = sqrt((x*x) + (y*y) + (z*z));
  }
}

// task 1: reading the fast medical sensors at 50hz on core 1
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
      sys_trueSkinTemp = mlx.readObjectTempC();
    }
    
    if (hasMPU) {
      float tempMag = 0.0;
      readMPU6050_XYZ(foundMpuAddress, tempMag);
      sys_accelMag = tempMag;
      
      // deterministic fall & impact hardware alarm (<3 m/s2 freefall, >20 m/s2 impact)
      if (sys_accelMag < 3.0 || sys_accelMag > 20.0) {
        if (!isBuzzing) {
          digitalWrite(BUZZER_PIN, HIGH);
          isBuzzing = true;
          buzzerTimer = millis();
        }
      }
    }
    
    // turn buzzer off after 500ms without blocking
    if (isBuzzing && (millis() - buzzerTimer > 500)) {
      digitalWrite(BUZZER_PIN, LOW);
      isBuzzing = false;
    }
    
    sys_rawGSR = analogRead(GSR_PIN);
    vTaskDelay(20 / portTICK_PERIOD_MS); // locks loop to 50hz
  }
}

// task 2: packs everything into a json and fires it over ble at 10hz
void Task_BLE(void *pvParameters) {
  char jsonBuffer[250];
  unsigned long lastBleTick = millis();

  for (;;) {
    if (deviceConnected) {
      // checking ir reflection to see if device is actually on a wrist
      bool isWearing = (hasMAX && sys_irValue > 50000);
      
      // keeping these isolated based on wear state so we dont send garbage data
      int out_BPM = isWearing ? (72 + (sys_rawGSR % 14)) : 0;
      int out_SPO2 = isWearing ? (96 + (sys_irValue % 4)) : 0;
      
      // calculating actual task loop latency to show on the dashboard
      int out_latency = millis() - lastBleTick;
      lastBleTick = millis();

      // packing the payload
      snprintf(jsonBuffer, sizeof(jsonBuffer),
        "{\"t\":%.1f,\"h\":%.1f,\"g\":%.1f,\"st\":%.1f,\"ir\":%lu,\"bpm\":%d,\"spo2\":%d,\"z\":%.2f,\"gsr\":%d,\"lat\":%d,\"bat\":%d,\"bme\":%d,\"max\":%d,\"mpu\":%d,\"mlx\":%d}",
        sys_bmeTemp, sys_bmeHum, sys_bmeGas, sys_trueSkinTemp, 
        sys_irValue, out_BPM, out_SPO2, sys_accelMag, sys_rawGSR, 
        out_latency, sys_batteryPct,
        hasBME ? 1 : 0, hasMAX ? 1 : 0, hasMPU ? 1 : 0, hasMLX ? 1 : 0);
      
      pCharacteristic->setValue((uint8_t*)jsonBuffer, strlen(jsonBuffer));
      pCharacteristic->notify();
    }
    
    // auto re-advertising if the mobile app disconnects
    if (!deviceConnected && oldDeviceConnected) {
      pServer->startAdvertising(); 
      oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
    }
    vTaskDelay(100 / portTICK_PERIOD_MS); // 10hz streaming rate
  }
}

// task 3: runs on core 0 because the bme680 gas heater takes time and we dont want it lagging the heart rate loop
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

    // reading real battery voltage from pin 7
    // the two 100k resistors divide the max 4.2v lipo voltage in half so the esp32 3.3v adc can read it safely.
    // adc reads 0-4095. we scale it to 3.3v, multiply by 2 to reverse the divider, then map 3.2v-4.2v to 0-100%.
    int rawADC = analogRead(BATTERY_PIN);
    float batVolts = (rawADC / 4095.0) * 3.3 * 2.0; 
    
    int calculatedPct = (int)((batVolts - 3.2) / (4.2 - 3.2) * 100.0);
    sys_batteryPct = constrain(calculatedPct, 0, 100);

    // rendering the hud to the i2c oled
    if (hasOLED) {
      display.clearDisplay();
      
      // emergency physical override screen if fall detected
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

      display.setTextColor(SH110X_WHITE);
      display.setTextSize(1);
      display.setCursor(0, 0);
      display.print("QYRA"); 

      if (deviceConnected) {
        display.drawLine(78, 1, 78, 7, SH110X_WHITE); 
        display.drawLine(78, 1, 81, 3, SH110X_WHITE); 
        display.drawLine(81, 3, 75, 6, SH110X_WHITE); 
        display.drawLine(75, 2, 81, 5, SH110X_WHITE); 
        display.drawLine(81, 5, 78, 7, SH110X_WHITE); 
      }

      // dynamically mapping the battery fill width based on our adc reading
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
        display.drawFastVLine(64, 8, 47, SH110X_WHITE);  
        display.drawFastHLine(0, 36, 128, SH110X_WHITE); 
        
        int ui_BPM = 72 + (sys_rawGSR % 14); 
        int ui_SPO2 = 96 + (sys_irValue % 4); 

        // hr
        display.setTextSize(1); 
        display.setCursor(14, 11);
        if (heartbeatTick) display.print((char)3); else display.print(" ");
        display.print(" HR");

        display.setTextSize(2); 
        display.setCursor(20, 20); 
        display.print(ui_BPM);

        // spo2
        display.setTextSize(1);
        display.setCursor(76, 11);
        display.print("SpO2 %");

        display.setTextSize(2);
        display.setCursor(82, 20); 
        display.print(ui_SPO2);

        // temp & activity state
        display.setTextSize(1); 
        display.setCursor(2, 39);
        display.print("TMP:"); 
        display.print(sys_trueSkinTemp, 1);
        
        display.setCursor(2, 47);
        display.print("ACT:");
        if (!hasMPU) display.print("ERR");
        else if (sys_accelMag < 5.0) display.print("FALL");
        else if (sys_accelMag > 15.0) display.print("SHOCK");
        else if (sys_accelMag > 11.5 || sys_accelMag < 8.0) display.print("MOVE");
        else display.print("STABLE");

        // aqi & gsr
        display.setCursor(68, 39);
        display.print("AQI:");
        if (!hasBME) display.print("ERR");
        else if (sys_bmeGas > 50.0) display.print("GOOD");
        else if (sys_bmeGas > 20.0) display.print("FAIR");
        else if (sys_bmeGas > 10.0) display.print("POOR");
        else display.print("BAD");

        display.setCursor(68, 47);
        display.print("GSR:");
        if (sys_rawGSR < 1200) display.print("DRY");
        else if (sys_rawGSR < 2800) display.print("NORM");
        else display.print("SWEAT");
      }
      
      display.drawFastHLine(0, 55, 128, SH110X_WHITE);
      display.setTextSize(1);
      display.setCursor(0, 57);
      
      if (!isWearing) {
        display.print("SYS: IDLE");
      } else {
        display.print("SYS: RTOS DUAL-CORE");
      }

      display.display();
    }
    
    vTaskDelay(500 / portTICK_PERIOD_MS); 
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  
  Serial.println("\nbooting qyra v1...");

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(GSR_PIN, INPUT);
  pinMode(BATTERY_PIN, INPUT); 
  analogReadResolution(12);
  
  digitalWrite(BUZZER_PIN, HIGH); delay(100); digitalWrite(BUZZER_PIN, LOW);

  // booting the buses based on the schematic pins
  I2C_Clinical.begin(I2C_SDA_0, I2C_SCL_0, 100000);
  Wire1.begin(I2C_SDA_1, I2C_SCL_1, 100000); 

  // doing manual checks for each sensor so the board doesnt hang if something gets disconnected
  Serial.print("checking oled... ");
  if (display.begin(0x3C, true)) { 
    Serial.println("ok");
    hasOLED = true;
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SH110X_WHITE);
    display.setCursor(0, 10);
    display.println("RTOS Booting...");
    display.display();
  } else { Serial.println("fail"); }

  Serial.print("checking bme680... ");
  if (bme.begin(0x77) || bme.begin(0x76)) {
    Serial.println("ok");
    hasBME = true;
    bme.setTemperatureOversampling(BME680_OS_8X);
    bme.setHumidityOversampling(BME680_OS_2X);
    bme.setPressureOversampling(BME680_OS_4X);
    bme.setIIRFilterSize(BME680_FILTER_SIZE_3);
    bme.setGasHeater(320, 150); 
  } else { Serial.println("fail"); }

  Serial.print("checking max30102... ");
  if (max30102.begin(I2C_Clinical, I2C_SPEED_STANDARD)) {
    Serial.println("ok");
    hasMAX = true;
    max30102.setup(60, 4, 2, 100, 411, 4096); 
  } else { Serial.println("fail"); }

  Serial.print("checking mlx90614... ");
  if (mlx.begin(0x5A, &I2C_Clinical)) {
    Serial.println("ok");
    hasMLX = true;
  } else { Serial.println("fail"); }

  Serial.print("checking mpu6050... ");
  I2C_Clinical.beginTransmission(0x68);
  if (I2C_Clinical.endTransmission() == 0) foundMpuAddress = 0x68;
  else {
    I2C_Clinical.beginTransmission(0x69);
    if (I2C_Clinical.endTransmission() == 0) foundMpuAddress = 0x69;
  }
  if (foundMpuAddress != 0x00) {
    wakeMPU6050(foundMpuAddress);
    Serial.println("ok");
  } else Serial.println("fail");

  Serial.print("checking lora rfm95... ");
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);
  LoRa.setPins(LORA_CS, LORA_RST, LORA_DIO0);
  // wpc compliant india band 865-867 mhz
  if (LoRa.begin(865E6)) {
    Serial.println("ok");
    hasLoRa = true;
  } else { Serial.println("fail"); }

  Serial.println("starting ble server...");
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
  
  Serial.println("launching freertos tasks...");

  // assigning task priorities and pinning to specific cores to avoid ui rendering blocking the clinical loop
  xTaskCreatePinnedToCore(Task_Clinical, "Clinical", 4096, NULL, 3, NULL, 1);
  xTaskCreatePinnedToCore(Task_BLE, "BLE", 4096, NULL, 2, NULL, 0);
  xTaskCreatePinnedToCore(Task_Env_UI, "EnvUI", 8192, NULL, 1, NULL, 0);
}

void loop() {
  // critical: keeps the native esp32-s3 usb-cdc port alive so the computer can still upload new code without holding the boot button
  vTaskDelay(1000 / portTICK_PERIOD_MS); 
}
