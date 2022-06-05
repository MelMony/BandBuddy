//
//  BuddyDevice.swift
//  BandBuddyV2
//
//  Created by Melissa Mony on 18/5/22.
//

import UIKit
import CoreBluetooth

class BuddyDevice: NSObject {
    
    // Identifiers for bluetooth services and characteristics
    
    // Connecting service
    public static let bandBuddyServiceUUID = CBUUID.init(string: "b78caada-e170-11ec-8fea-0242ac120002")
    
    // Sound service
    public static let soundServiceUUID = CBUUID.init(string: "0f48bdd6-e0a9-11ec-9d64-0242ac120002")
    public static let decibelCharUUID = CBUUID.init(string: "0f48c056-e0a9-11ec-9d64-0242ac120002")
    public static let sampleTimeCharUUID = CBUUID.init(string: "66a1d1b0-e173-11ec-8fea-0242ac120002")
    
    // Dose service
    public static let doseServiceUUID = CBUUID.init(string: "35371e98-e0a9-11ec-9d64-0242ac120002")
    public static let archivedDoseCharUUID = CBUUID.init(string: "3537210e-e0a9-11ec-9d64-0242ac120002")
    public static let currentExposureCharUUID = CBUUID.init(string: "35372230-e0a9-11ec-9d64-0242ac120002")
    
    // Battery service 
    public static let batteryServiceUUID = CBUUID.init(string: "0x180F")
    public static let batteryCharUUID = CBUUID.init(string: "0x2A19")
}
