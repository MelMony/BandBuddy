//
//  ViewController.swift
//  BandBuddyV2
//
//  As this is a prototype and I was doing very rushed development I have not implemented
//  the MVC design pattern and everything is more or less in one file which I am painfully aware is
//  one of the biggest code smells one can create in iOS development :)
//
//  Created by Melissa Mony on 18/5/22.
//

import UIKit
import CoreBluetooth

class ViewController: UIViewController, CBPeripheralDelegate, CBCentralManagerDelegate {
    
    // Bluetooth properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral!
    
    // Bluetooth Characteristics
    private var batteryChar: CBCharacteristic?
    private var decibelChar: CBCharacteristic?
    private var sampleTimeChar: CBCharacteristic?
    private var currentExposureChar: CBCharacteristic?
    private var archivedDoseChar: CBCharacteristic?
    
    // Data points
    var sampleTime = ""
    var decibels = 0
    var exposure = 0.0
    var dose = 0
    var battery = 100
    
    // Label outlets
    @IBOutlet weak var decibel: UILabel!
    @IBOutlet weak var batteryLevel: UILabel!
    @IBOutlet weak var currentExposure: UILabel!
    @IBOutlet weak var averageSPL: UILabel!
    @IBOutlet weak var range: UILabel!
    @IBOutlet weak var archivedExposure: UILabel!
    @IBOutlet weak var disconnected: UILabel!
    
    // View outlets
    @IBOutlet weak var sessionView: UIView!
    
    // Button outlets

    @IBOutlet weak var datePicker: UIDatePicker!
    
    @IBAction func datePickerUpdate(_ sender: UIDatePicker) {
    }
    
    @IBAction func datePicker(_ sender: UIDatePicker) {
        // Average SPL
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let datePicked = dateFormatter.string(from: sender.date)
        let rounded_averageSPL = round((sessionArchive[datePicked]!.avgDb) * 100)/100.0
        averageSPL.text = "\(rounded_averageSPL) dB"

        // Decibel range
        range.text = "\(sessionArchive[datePicked]!.minDb) - \(sessionArchive[datePicked]!.maxDb) dB"

        // Exposure
        let temp = sessionArchive[datePicked]!.exposure
        archivedExposure.textColor = findExposureColour(db: Int(temp))
        archivedExposure.text = "\(temp) dB"
    }
    @IBAction func resetButton(_ sender: UIButton) {
        writeExposureReset(withCharacteristic: archivedDoseChar!, withValue: Data([0]))
    }
    @IBOutlet weak var resetButton: UIButton!
    
    // Settings
    let UPPER_LIMIT = 85 // Exposure thresholds
    let LOWER_LIMIT = 80
    
    // Data structure for storing data collected from Band Buddy
    struct sessionStorage {
        
        var db: [Int] = [] // All decibel measurments recieved from Band Buddy for the day
        
        var dbCount: Int {
            get {
                return db.count
            }
        }
        
        var exposure = 0.0 // Cummulative noise exposure recieved from band buddy for day
        
        // Mean of decibels recorded for day
        var avgDb: Double {
            get {
                let sum = db.reduce(0,+)
                if dbCount == 0 {
                    return 0
                }
                return Double(sum) / Double(dbCount)
            }
        }
        
        // Minimum decibel recorded per day
        var minDb: Int {
            get {
                return db.min() ?? 0
            }
        }
        
        // Maximum decibel recorded per day
        var maxDb: Int {
            get {
                return db.max() ?? 0
            }
        }
    }
    
    // Dummy date to backfill the archive history for demo
    let dummyDate1 = "2022-05-31"
    let dummyDate2 = "2022-06-01"
    let dummyDate3 = "2022-06-02"
    let dummySession1 = sessionStorage(db: [55,60,90,88,100,55,56,55,67], exposure: 80.2)
    let dummySession2 = sessionStorage(db: [34, 55, 33, 22, 56, 56, 56, 110], exposure: 85.98)
    let dummySession3 = sessionStorage(db: [76, 59, 38, 45, 58, 58, 78, 99], exposure: 67.54)
    
    // Storage archive for buddy device data
    var sessionArchive = [String:sessionStorage]()
    var today = "" // Track day
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // Create storage for band buddy data & dummmy archive data
        sessionArchive = [dummyDate1: dummySession1, dummyDate2: dummySession2, dummyDate3: dummySession3]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        today = dateFormatter.string(from: Date())
        let nokeyExists = sessionArchive[today] == nil
        if nokeyExists {
            sessionArchive[today] = sessionStorage()
        }
        
        // Start settings
        resetButton.isEnabled = false
        sessionView.alpha = 0.3
        disconnected.isHidden = false
        datePicker.date = dateFormatter.date(from: "2022-05-31")!
        datePicker.minimumDate = dateFormatter.date(from: "2022-05-31")
        datePicker.maximumDate = Date()
        //datePicker.addTarget(self, action: Selector(("datePickerChanged:")), for: .valueChanged)
        
        // Setup bluetooth
        centralManager = CBCentralManager(delegate:self, queue:nil)
    }
    
    
    // Start bluetooth scanning for a Band Buddy device
    // Updates when bluetooth peripheral device is switched on/off
    // Indicates the bluetooth state, starts the scanning process
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central state update:")
        if central.state != .poweredOn {
            print("Central device bluetooth is not powered on")
        } else {
            print("Central scanning for...", BuddyDevice.bandBuddyServiceUUID);
            centralManager.scanForPeripherals(withServices: [BuddyDevice.bandBuddyServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
    
    
    // Handles the result of the scan, tells us when the device has been discovered
    // Starts a connection
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        self.centralManager.stopScan() // Device found so stop scannning
        self.peripheral = peripheral
        self.peripheral.delegate = self // Copy peripheral instance
        self.centralManager.connect(self.peripheral, options: nil) // Connect to the device
    }
    
    
    // Checks that we have the correct device via UUID once connected
    // Starts device discovery - what services and characteristics are avaliable?
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral == self.peripheral {
            print("Connected to your band buddy!")
            disconnected.isHidden = true // show session stats
            sessionView.alpha = 1
            // Find services associated with the device
            peripheral.discoverServices([BuddyDevice.soundServiceUUID,  BuddyDevice.doseServiceUUID, BuddyDevice.batteryServiceUUID])
        }
    }
    
    
    // Starts characteristic discovery
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                if service.uuid == BuddyDevice.soundServiceUUID {
                    print("Sound service found")
                    // Go discover characteristics
                    peripheral.discoverCharacteristics([BuddyDevice.decibelCharUUID, BuddyDevice.sampleTimeCharUUID], for: service)
                }
                if service.uuid == BuddyDevice.doseServiceUUID {
                    print("Dose service found")
                    peripheral.discoverCharacteristics([BuddyDevice.archivedDoseCharUUID, BuddyDevice.currentExposureCharUUID], for: service)
                }
                if service.uuid == BuddyDevice.batteryServiceUUID {
                    print("Battery service found")
                    peripheral.discoverCharacteristics([BuddyDevice.batteryCharUUID], for: service)
                }
            }
        }
    }
    
    
    // Handles discovery of characteristics
    // Event provides all characteristics from the specified UUID
    // Occurs only once during connection phase
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == BuddyDevice.sampleTimeCharUUID {
                    print("Sample time characteristic found")
                    sampleTimeChar = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == BuddyDevice.decibelCharUUID {
                    print("Decibel characteristic found")
                    decibelChar = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == BuddyDevice.archivedDoseCharUUID {
                    print("Archived dose characteristic found")
                    archivedDoseChar = characteristic
                    resetButton.isEnabled = true // Enable button to write to reset device
                } else if characteristic.uuid == BuddyDevice.currentExposureCharUUID {
                    print("Current exposure characteristic found")
                    currentExposureChar = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == BuddyDevice.batteryCharUUID {
                    print("Battery characteristic found")
                    batteryChar = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
    
    
    // Handles bluetooth disconnects from the device
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral == self.peripheral {
            print("Band Buddy Disconnected")
            
            // Update session states to idle state
            currentExposure.textColor = UIColor(red: 0.3176470588, green: 0.3843137254, blue: 0.4274509803, alpha: 1)
            batteryLevel.text = " ? %"
            decibel.text = " ? dB"
            currentExposure.text = " ? dB"
            sessionView.alpha = 0.3
            disconnected.isHidden = false
            resetButton.isEnabled = false // Prevent reset when disconnected
            
        }
        // Reset and prevent writing to disconnected device
        self.peripheral = nil
        
        // Start rescanning process
        print("Central scanning for ", BuddyDevice.soundServiceUUID);
        centralManager.scanForPeripherals(withServices: [BuddyDevice.bandBuddyServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic == sampleTimeChar {
            
            // Convert uint8 value array into string from ascii characters
            sampleTime = ""
            for i in 0...characteristic.value!.count - 1 {
                let c = String(UnicodeScalar(characteristic.value![i]))
                sampleTime += c
            }
            print("Sample Time:", sampleTime, terminator: "")
        }
        if characteristic == decibelChar {
            decibels = Int(characteristic.value![0])
            sessionArchive[today]?.db.append(decibels) // Store in archive
            print("  Decibels:", decibels, terminator: "")
            decibel.text = "\(decibels) dB"
            
        }
        if characteristic == currentExposureChar {
            var temp = ""
            for i in 0...characteristic.value!.count - 1 {
                let c = String(UnicodeScalar(characteristic.value![i]))
                temp += c
            }
            exposure = Double(temp)!
            let rounded_exposure = round(exposure * 100)/100.0
            if rounded_exposure > sessionArchive[today]!.exposure {
                sessionArchive[today]!.exposure = rounded_exposure // Store in archive
            }
            print("  Exposure: ", rounded_exposure, terminator: "")
            currentExposure.textColor = findExposureColour(db: Int(rounded_exposure))
            currentExposure.text = "\(rounded_exposure) dB"
        }
        if characteristic == batteryChar {
            battery = Int(characteristic.value![0])
            print("  Battery:", battery)
            batteryLevel.text = "\(battery) %"
        }
    }
    
    
    // Checks for errors in updating values from the peripheral device
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        print("Enable notification ", characteristic.uuid)
        if error != nil {
            print("Error enabling notify")
        }
    }
    
    
    // Write new value to the Band Buddy peripheral device for the archived dose characteristic with no response
    private func writeExposureReset(withCharacteristic characteristic: CBCharacteristic, withValue value: Data){
        
        if characteristic.properties.contains(.writeWithoutResponse) && peripheral != nil {
            peripheral.writeValue(value, for: characteristic, type: .withoutResponse)
        }
    }
    
    // Returns colour of label based on exposure level
    func findExposureColour(db: Int) -> UIColor
    {
        var colour = UIColor(red: 81, green: 98, blue: 109, alpha: 1)
        if db >= UPPER_LIMIT {
            colour = UIColor.red
        } else if db >= LOWER_LIMIT && db < UPPER_LIMIT {
            colour = UIColor.blue
        } else {
            colour = UIColor.green
        }
        return colour
    }

    // Update values for display archive statistics
    func datePickerChanged(_ sender: UIDatePicker)
    {
        // Average SPL
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let datePicked = dateFormatter.string(from: sender.date)
        let rounded_averageSPL = round((sessionArchive[datePicked]!.avgDb) * 100)/100.0
        averageSPL.text = "\(rounded_averageSPL) Db"
        
        // Decibel range
        range.text = "\(sessionArchive[datePicked]!.minDb) - \(sessionArchive[datePicked]!.maxDb) dB"
        
        // Exposure
        let temp = sessionArchive[datePicked]!.exposure
        archivedExposure.textColor = findExposureColour(db: Int(temp))
        archivedExposure.text = "\(temp) dB"
    }
}

