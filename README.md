# Band Buddy

Band Buddy is a discrete sound monitoring solution that provides real-time risk assessment for musicians through both an external device and companion iOS app displaying accumulated exposure and statistical analysis for connected devices. Sound is sensed using a microphone module with a Particle argon which performs a variety of calculations on the collected data to determine noise exposure and acts on this information through the LED indicator. This data is communicated and stored on the iPhone using the Bluetooth Low Energy protocol for further statistical processing and display.

## Peripheral Device

### Hardware
#### Schematic diagram of the hardware prototype

<img width="700" alt="image" src="https://github.com/MelMony/BandBuddy/assets/31891015/e0968974-b9ba-4c87-a210-74d3850b7717">

#### Draft peripheral device

<img width="350" alt="image" src="https://github.com/MelMony/BandBuddy/assets/31891015/031f3582-1de9-491d-9e43-e462d46f95a7">

#### Final peripheral device shown in use

![image](https://github.com/MelMony/BandBuddy/assets/31891015/29a1dbe5-5620-4f02-a5d2-639f5eb21475)

#### Final peripheral device inside view

<img width="450" alt="image" src="https://github.com/MelMony/BandBuddy/assets/31891015/eaa302d6-f199-433c-b790-12ade79dcc26">


### Firmware

#### Measuring sound
To calculate the sound pressure level using the microphone the following formula is used to convert the analogue reading into a decibel meeasurmenet. It is important to note that within this formula A & R values must be calculated for each individual microphone using a known reference through a microphone calibration process in order to ensure accuracy of measurement values. A sound sampling procedure ensures accuracy and mitigates false readings for the microphone sensor. Rather than just reading a value from the sensor every x seconds which could result in unexpected readings, we take many readings over the course of a sample window, and then base our measurement on the peak-to-peak amplitude of the sound wave rather than an arbitrary point in the signal. 

<img width="180" alt="image" src="https://github.com/MelMony/BandBuddy/assets/31891015/81e0743c-18d8-4a6c-8daf-f6bdcb769bbf">

#### Measuring Noise Exposure 
Band Buddy uses uses a series of decibel measurements to calculate noise exposure dosage using a time weighted average as regulated by various government bodies such as WorkSafe and NIOSH as shown in the formula below. Essentially, we first calculate the maximum exposure time permissible at the specified decibel level (e.g. 15 minutes for 100 decibels) before such a time that hearing damage will occur. We use this to calculate a dosage value, which is the amount of time spent at the decibel level divided by the maximum exposure threshold. We sum all the dosages in the series of measurements perform the log calculation shown in Figure 8, which outputs a noise exposure for the user providing a good indication of the amount and severity of sound they have been exposed to over the course of the day and whether this level is dangerous for their hearing health. 

![image](https://github.com/MelMony/BandBuddy/assets/31891015/61fc30b0-5274-4562-babe-525d83c21c05)

#### Communication protocol
Band Buddy uses BLE operating over the 2.4Ghz frequency to transfer data and settings between the Particle Argon and iPhone. The central device is the iPhone and the Argon is the peripheral. Data is transferred at a minimum of 2210 bytes/sec and is pre-encoded as unsigned 8 bit integers to facilitate transfer in discrete blocks.  

#### Architecture 
The state diagram below visualises the interactions of user input, environmental monitoring, response from the system, and communication of data involved in the firmware of the peripheral argon device. 

<img width="850" alt="image" src="https://github.com/MelMony/BandBuddy/assets/31891015/41fc49b2-7da7-4094-b706-93c9a32c56b5">


## iOS Application 

#### Architecture

<img width="850" alt="image" src="https://github.com/MelMony/BandBuddy/assets/31891015/94bd2994-ba78-4836-9204-c2f712c17ff7">


#### App screenshot 

<img width="300" alt="image" src="https://github.com/MelMony/BandBuddy/assets/31891015/c2744f97-6bea-452f-b18b-324800595af1">


