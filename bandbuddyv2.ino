/*
    BAND BUDDY By Melissa Mony 
    May 2022
    Final project for 210 Embedded Systems Development
    
    Band Buddy is a discrete sound monitoring solution using Particle Argon that provides real-time
    risk assessment for musicians as well as a companion iOS app displaying accumulated exposure
    and in-depth post rehearsal analysis for connected devices. 

*/

SYSTEM_THREAD(ENABLED);

#include <math.h>

// Pin IDs for components
const pin_t LEDRED = D4;
const pin_t LEDGREEN = D3;
const pin_t LEDBLUE = D2;
const pin_t MICROPHONE = A0;
const pin_t SESSION_BUTTON = D6;
const pin_t POWER_BUTTON = D8;

// Bluetooth addresses
const BleUuid bandBuddyServiceUUID("b78caada-e170-11ec-8fea-0242ac120002");
const BleUuid soundServiceUUID("0f48bdd6-e0a9-11ec-9d64-0242ac120002");
const BleUuid decibelCharUUID("0f48c056-e0a9-11ec-9d64-0242ac120002");
const BleUuid sampleTimeCharUUID("66a1d1b0-e173-11ec-8fea-0242ac120002");
const BleUuid doseServiceUUID("35371e98-e0a9-11ec-9d64-0242ac120002");
const BleUuid archivedDoseCharUUID("3537210e-e0a9-11ec-9d64-0242ac120002");
const BleUuid currentExposureCharUUID("35372230-e0a9-11ec-9d64-0242ac120002");
const BleUuid batteryServiceUUID(0x180F);
const BleUuid batteryCharUUID(0x2A19);

// Microphone calibration stats
const double ADC_REF = 4095; // ADC output at DB ref
const double DB_REF = 110; // Actual Db measurement from SPL
const int   SAMPLE_SIZE = 1000; // The sample size of the audio measurement window in ms

// Dosage thresholds in db for daily noise exposure based on an 8 hour time weight average
const int UPPER_LIMIT = 85;
const int LOWER_LIMIT = 80;

// Bluetooth notification interval
const int BLE_INTERVAL = 1000; // How often to send data

// Battery settings
const float MAX_BATTERY = 4.1; // Battery level configuration
const float MIN_BATTERY = 3.1;
const int IDLE_THRESHOLD = 60000; // Currently 60 secs of inactivity

// Variables for ISR
volatile int sessionButtonState = HIGH;
volatile int powerButtonState = HIGH;
volatile int powerState = HIGH;
volatile system_tick_t sessionButtonTime = 0;
volatile system_tick_t powerButtonTime = 0;
volatile system_tick_t buttonPressedNow;
volatile bool sessionRecording = false;

// Global variables 
retained double totalExposure = 0; // Accumulated sound exposure
double archivedDose = 0; // Resets every day - written from phone 
retained double totalDose = 0; // Sum of noise doses from readings
int decibels = 0; // Stores sound measurment
long sampleTime = 0; // Tracks sampling of sound
SystemSleepConfiguration config; // Stores the configuration settings for low power mode
system_tick_t bleTimer; // Tracks time since last ble communication
system_tick_t idleTimer; // Tracks idle time of the system

// Bluetooth characteristics
BleCharacteristic batteryLevelCharacteristic("battery", BleCharacteristicProperty::NOTIFY, batteryCharUUID, batteryServiceUUID); 
BleCharacteristic decibelCharacteristic("decibel", BleCharacteristicProperty::NOTIFY, decibelCharUUID, soundServiceUUID);
BleCharacteristic sampleTimeCharacteristic("sampleTime", BleCharacteristicProperty::NOTIFY, sampleTimeCharUUID, soundServiceUUID);
BleCharacteristic archivedDoseCharacteristic("archivedDose", BleCharacteristicProperty::WRITE_WO_RSP, archivedDoseCharUUID, doseServiceUUID, onDataReceived);
BleCharacteristic currentExposureCharacteristic("currentExposure", BleCharacteristicProperty::NOTIFY, currentExposureCharUUID, doseServiceUUID);


void setup() {
    
    // Setup SRAM for critical data values to ensure integrity of system in power outage
    System.enableFeature(FEATURE_RETAINED_MEMORY);

    // Set-up pins
    pinMode(LEDRED, OUTPUT);
    pinMode(LEDGREEN, OUTPUT);
    pinMode(LEDBLUE, OUTPUT);
    pinMode(MICROPHONE, INPUT);
    pinMode(SESSION_BUTTON, INPUT);
    pinMode(POWER_BUTTON, INPUT);

    // Interrupts for buttons
    attachInterrupt(SESSION_BUTTON, triggerSession, CHANGE, 2);
    attachInterrupt(POWER_BUTTON, togglePower, CHANGE, 3);
    
    // Set configuration for low power mode triggered by the power button
    config.mode(SystemSleepMode:: ULTRA_LOW_POWER).gpio(D8, CHANGE);
    idleTimer = millis();
    
    // Setup bluetooth
    BLE.on();
    configureBLE();
    totalDose = archivedDose;
    bleTimer = millis();

    // All leds off when device turns on (Set to high as we have an RGB LED with a common anode)
    digitalWrite(LEDRED, HIGH);
    digitalWrite(LEDBLUE, HIGH);
    digitalWrite(LEDGREEN, HIGH);

    // Serial monitoring
    Serial.begin(9600);
    Serial.println("Band buddy ready...");
    RGBSignal(0, 0, 0); // Idle LED signal
}


void loop() {
    
    // Monitor battery level
    float battery = batteryLevel();
    
    if (sessionRecording == true)
    {
        idleTimer = millis(); // Reset idle timer
        
        // Action exposure level to LED visual indicator
        dosageLight(totalExposure); 
        
        // Measure sound level
        decibels = soundSample();
        sampleTime = Time.now();
    
        // Calculate noise dose
        double dose = calculateDose(decibels);
        totalDose += dose;
        
        // Calculate time weighted noise exposure
        totalExposure = calculateExposure();

        // Output to serial monitor
        Serial.print(Time.format(sampleTime, "%F %T"));
        Serial.print(" Decibels: ");
        Serial.print(decibels);
        Serial.print(" Dose: ");
        Serial.print(dose, 6);
        Serial.print(" Total Exposure: ");
        Serial.print(totalExposure, 6);
        Serial.print(" Battery: ");
        Serial.println(battery);
        
        // Send data to phone via BLE
        if(BLE.connected())
        {
            bleCommunication();
        }
        
        // If battery is running critically low whilst recording end session 
        if(battery < 2.0)
        {
            sessionRecording = false;
        }
        
    } else if(powerState == LOW || battery < 5.0 || systemIsIdle()) {
        // If system is idle (not recording) and either the power button has been triggered, battery is low or prolonged idle time
        Serial.println("Powering Off");
        System.sleep(config); // Trigger system power down to conserve battery life
        
        // When device wakes continue execution from here
        Serial.println("Powering On"); 
        idleTimer = millis(); // Reset idle timer
        BLE.on();
    }
}


// Precondition: System is starting up and bluetooth is on but not yet configured
// Postcondition: Bluetooth characteristics are configured and advertising is begun
void configureBLE()
{
    // Create characteristics for services
    BLE.addCharacteristic(sampleTimeCharacteristic);
    BLE.addCharacteristic(decibelCharacteristic);
    BLE.addCharacteristic(batteryLevelCharacteristic);
    BLE.addCharacteristic(archivedDoseCharacteristic);
    BLE.addCharacteristic(currentExposureCharacteristic);
    
    // Make advertising data
    BleAdvertisingData advData;
    
    // Advertise private service
    advData.appendServiceUUID(bandBuddyServiceUUID);
    
    // Begin advertising
    BLE.advertise(&advData); 
}


// Precondition: Bluetooth is on and is connected to central device, the time since the last ble communication >= ble communication interval
// Postcondition: Battery level, decibels, sample time and exposure values are published/sent to central device
void bleCommunication()
{
    long now = millis();
    
    // Handle overflow
    if (now < bleTimer)
    {
        bleTimer = now;
    }
    
    // Compare the time now with the time since the event was last triggered
    if( now - bleTimer >= BLE_INTERVAL) // Only trigger if interval time has elapsed
    {
        // Publish to characteristic
        sampleTimeCharacteristic.setValue(Time.format(sampleTime, "%F %T"));
        decibelCharacteristic.setValue(decibels);
        currentExposureCharacteristic.setValue((String) totalExposure);
        batteryLevelCharacteristic.setValue((uint8_t)batteryLevel());
        bleTimer = now;
    }
}


// Precondition: Bluetooth is on and connected to the central device, data has been received from the central device
// Postcondition: Dose value is updated from data written by the central device
// Handles BLE callbacks
static void onDataReceived(const uint8_t* data, size_t len, const BlePeerDevice& peer, void* context) 
{
    // Error checking - we only want to recieve 1 byte
    if( len != 1 )
    {
        return;
    }
    
    // Write data 
    totalDose = data[0]; 
    Serial.println("Accumulated dose updated via iPhone");
}


// Precondition: System is on but not recording a session
// Postcondition: Returns a bool representing whether elapsed idle time fufils threshold for power saving mode
bool systemIsIdle()
{
    long now = millis();
    
    // Handle overflow
    if (now < idleTimer)
    {
        idleTimer = now;
    }
    
    // Check if idle time exceeds threshold
    if( now - idleTimer >= IDLE_THRESHOLD) 
    {
        idleTimer = now;
        return true;
    }
    return false;
}


// Precondition: System is powered on and connected to a power source
// Postcondition: Returns a float value representing the percentage of battery charge remaining  
float batteryLevel()
{
    float voltage = analogRead(BATT) * 0.0011224; // Read battery voltage off device
    float level = (voltage - MIN_BATTERY)/(MAX_BATTERY - MIN_BATTERY) * 100;
        
        // Handle edge cases
        if (level > 100)
        {
            level = 100;
        }
        else if (level < 0)
        {
            level = 0;
        }
        
    return level;
}


// Precondition: The session button is pressed by the user and the bounce time has elapsed
// Postcondition: Session recording either begins or ends depending on sessionRecording state
void triggerSession()
{
    buttonPressedNow = millis(); // Track time
    
    if (buttonPressedNow - sessionButtonTime > 250) // Prevent bouncing
    {
        sessionButtonState = !sessionButtonState; // Reset state
        
        if (sessionButtonState == LOW)
        {
            Serial.println("Session started"); // Reset sound measurements data
            sessionRecording = true;
        }
        else
        {
            Serial.println("Ending Session");
            sessionRecording = false;
            RGBSignal(0, 0, 0); // Idle LED signal
        }
        
        sessionButtonTime = buttonPressedNow; // Track button time
    }
}


// Precondition: The power button is pressed by the user and bounce time has elapsed
// Postcondition: The system either turns on or off from low power mode based on current power state
void togglePower()
{
    buttonPressedNow = millis(); // Track time
    
    if (buttonPressedNow - powerButtonTime > 250) // Prevent bouncing
    {
        powerButtonState = !powerButtonState; // Reset state
        Serial.println("Attempting to power off ");
        powerButtonTime = buttonPressedNow; // Track button time
        powerState = !powerState; // Change power state
    }
    
    RGBSignal(0, 0, 0); // LED indication that we have moved to Idle mode
}


// Precondition: An integer value reprenting decibels measurmented from the microphone is supplied
// Postcondition: Returns a float value reresenting noise dosage based on sample size and exposure threshold
float calculateDose(int db)
{
    // Calculate dose size - correlates with the sample size
    double doseSize = (double)SAMPLE_SIZE / 60000; 

    // Find exposure threshold for sound level
    double exposureThreshold = 480 / (std::pow(2 ,((db - 85)/3)));

    // Calculate dose
    double dose = doseSize / exposureThreshold;

    return dose;
}


// Precondition: A dosage representing accumulating sound exposure has been stored in a global variable
// Postcondition: Returns float value representing the 8 hour time weighted average noise exposure  according to OSHA standards
float calculateExposure()
{
    // Calculate weighted average exposure 
    return 10 * log10(totalDose) + 85;
}


// Precondition: A integer value representing dosage is supplied measured in decibels
// Postcondition: The LED colour is lit according to specified dosage limits
void dosageLight(int db)
{
    if(db >= UPPER_LIMIT)
    {
        RGBSignal(0, 255, 255); // Red
    }
    else if(db >= LOWER_LIMIT && db < UPPER_LIMIT)
    {
        RGBSignal(255, 255, 0); // Blue
    }
    else // Under 80
    {
        RGBSignal(255, 0, 255); // Green
    }
}


// Precondition: System is setup and session is recording
// Postcondition: An anlogue reading is taken from the microphone using a sampling technique and returned in decibel units
int soundSample()
{
    int signalMax = 0;
    int signalMin = 4095; // 12 bit ADC outputs values 0-4095
    unsigned long startMillis = millis(); // Start of sample window
    unsigned int sample;
    unsigned int peakToPeak; 

    while (millis() - startMillis < SAMPLE_SIZE)
    {
        sample = analogRead(MICROPHONE); // Read sample from the microphone

        if (sample <= 4095) // Loop collects all readings
        {
          if (sample > signalMax)
          {
            signalMax = sample; // Save max signal level
          }
          else if (sample < signalMin)
          {
            signalMin = sample; // Save min signal level
          }
        }
    }

    peakToPeak = signalMax - signalMin; // Calculate peak to peak amplitude of the signal

    int decibels = 20 * log2(peakToPeak/ADC_REF) + DB_REF; // Convert signal to decibels

    return decibels;
}


// Precondition: 3 x parameters 0-255 are given representing red, green and blue values for RGB LED to output
// Postcondition: LED is lit using PWM to achieve specified RGB colour combination
void RGBSignal(int red, int green, int blue)
{
    analogWrite(LEDRED, red);
    analogWrite(LEDGREEN, green);
    analogWrite(LEDBLUE, blue);
}





