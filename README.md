# iOSExternalAccessory
Access the iOS External Accessory API as a Cordova plugin

# Summary
This Cordova plugin is specific to iOS and provides access to the [iOS External Accessory API](https://developer.apple.com/library/ios/documentation/ExternalAccessory/Reference/ExternalAccessoryFrameworkReference/)

## Supported platforms
- iOS

The External Accessory API is specific to iOS.  It was developed to communicate originally with a Bluetooth Classic Temperature Probe (from BlueTherm) which requires External Accessory API.  The plugin was written to be device generic and contains no specific code for the probe.

## Usage

Using standard Cordova plugin, this plugin is accessed through

    var pluginAPI = cordova.plugins.iOSExternalAccessory;

Since Apple Apps that access External Accessory devices (either over USB or BlueTooth classic) must declare the Transport Protocols that the device they will be using the only thing that needs to be set to use this plugin is the **UISupportedExternalAccessoryProtocols** plist entry, this is currently set via the *plugin.xml* of this plugin.

        <config-file target="*-Info.plist" parent="UISupportedExternalAccessoryProtocols">
            <array>
                <string>uk.co.etiltd.bluetherm1</string>
            </array>
        </config-file>


# API

In a similar manner to other Cordova plugins, all methods take 0 or more input parameters followed by **success** and **error** callback functions.  
The **success** function will accept a single object/array with the result of the function.  
The **error** function accepts a single string error message.

## Methods

## getVersion

Return the version of the plugin

    getVersion(success, error);
    
    function success(info)
    function error(msg)

### Description

Get the version of the plugin

### On success

    info: {
        version: "1.0.0"        // Version of the plugin
    }


## listDevices

Return a list of currently connected devices

    listDevices(success, error);
    
    function success(deviceArray)
    function error(msg)

### Description

This maps directly to a call to 

    [[EAAccessoryManager sharedAccessoryManager] connectedAccessories]


## On success
- deviceArray:  Array of objects of type

    ```
    device: {
        name: accessory.name,                               // String
        id: accessory.connectionID,                         // Number
        connected: accessory.connected,                     // Bool
        manufacturer: accessory.manufacturer,               // String
        modelNumber: accessory.modelNumber,                 // String
        serialNumber: accessory.serialNumber,               // String
        firmwareRevision: accessory.firmwareRevision,       // String
        hardwareRevision: accessory.hardwareRevision,       // String
        protocolStrings: accessory.protocolStrings          // String []
    }
    ```
    
## connect

Attempt to connect to a device

    connect(deviceId, protocolString, success, error);
    
    function success(sessionId)
    function error(msg)

### Description

Will attempt to connect to the device with specified `deviceId` and `protocolString`, on success will return a `sessionId` string which represents the session.

### Parameters
- deviceId: Should be the `id` field of `device` object returned by the `listDevices` method.
- protocolString: Should be the Protocol String that is used to create the session.  
- success: Returns `sessionId` string to be used in further Accessory Session calls

### On success
- sessionId: Id of the newly created session


## AccessorySession_write

Write data to a session

    AccessorySession_write(sessionId, data, success, error)
    
    function success()
    function error(msg)

### Description

With a valid `sessionId` the `data` parameter will be converted to a byte array and written to the device.

### Parameters
- sessionId: Should be the return value of the `connect` call, invalid sessionIds will generate errors
- data: Should be the bytes to write to the device.  Will accept an `Array of integer`, a `Uint8Array` or a base64 encoded string.

**Note**  Actual data may be written on a background thread within the plugin.  And the `success` function may be called **before** the actual data is written to the device.

### On success
Nothing


## AccessorySession_subscribeRawData

Subscribe to raw data read from the devices session

    AccessorySession_subscribeRawData(sessionId, success, error)
    
    function success(rawdata)
    function error(msg)

### Description

Each session can have 1 subscribed read event function, once called the `success` function will be called with data buffers as it is read from the device.  The data buffers will be 1 or more bytes of data and should be converted to a usable `Uint8Array` using

    function success(rawdata) {
        var bytes = new Uint8Array(rawdata)
    
        // do something with your data
    }

### Parameters
- sessionId: The session to subscribe to read events to

### On success
- rawdata:  Read data with 1 or more bytes



## AccessorySession_unsubscribeRawData

Unsubscribe from receiving read data

    AccessorySession_unsubscribeRawData(sessionId, success, error)
    
    function success()
    function error(msg)

### Description

Unsubscribe from receive read data

### Parameters
- sessionId: The session to unsubscribe from

### On success
Nothing



## AccessorySession_disconnect

Disconnect the session and close both read and write streams

    AccessorySession_disconnect(sessionId, success, error)
    
    function success()
    function error(msg)

### Description

Disconnect the session with `sessionId` and close the read and write streams

### Parameters
- sessionId: The session to disconnect

### On success
Nothing


## listSessions

List currently connected sessions

    listSessions(success, error)
    
    function success(sessionArray)
    function error(msg)

### Description

Will list all currently connected sessions recorded by the plugin.  Can be useful during development/debugging to find all sessions and perhaps disconnect them all before starting a fresh.

### On success
- sessionArray: An array of objects (similar to listDevices) of type

    ```
    session: {
        sessionId: session ID                               // String

        name: accessory.name,                               // String
        id: accessory.connectionID,                         // Number
        connected: accessory.connected,                     // Bool
        manufacturer: accessory.manufacturer,               // String
        modelNumber: accessory.modelNumber,                 // String
        serialNumber: accessory.serialNumber,               // String
        firmwareRevision: accessory.firmwareRevision,       // String
        hardwareRevision: accessory.hardwareRevision,       // String
        protocolStrings: accessory.protocolStrings          // String []
    }
    ```

## subscribeDeviceChanges

Listen to device Connects and Disconnects

    subscribeDeviceChanges(success, error)

    function success(args)
    function error(msg)

### Description

Will listen to External Accessory device Connects and Disconnects and call the `success` function on each event.

### On success
- args: An object of type

    ```
    args: {
        event: "connected" or "disconnected"        
    
        name: accessory.name,                               // String
        id: accessory.connectionID,                         // Number
        connected: accessory.connected,                     // Bool
        manufacturer: accessory.manufacturer,               // String
        modelNumber: accessory.modelNumber,                 // String
        serialNumber: accessory.serialNumber,               // String
        firmwareRevision: accessory.firmwareRevision,       // String
        hardwareRevision: accessory.hardwareRevision,       // String
        protocolStrings: accessory.protocolStrings          // String []
    }
    ```

## unsubscribeDeviceChanges
 
 Unsubscribe to device Connects and Disconnects

     unsubscribeDeviceChanges(success, error)

     function success()
     function error(msg)

### Description

Will unsubscribe from listening to device Connects and Disconnects

### On success
Nothing


# Notes

## App Pausing and Resuming
When the App is Paused the Plugin will automatically remember which device sessions are currently connected and On Resume will attempt to reconnect them, sessionId's will remain unchanged.

## Testing
The plugin was originally developed to access a BlueTherm Thermometer Probe over BlueTooth (classic), to my amazement I could not find a Cordova plugin which accesses the External Accessory API which I needed to communicate with the probe - so I wrote this one.  There is a (cross platform BlueTooth Low Energy)[https://github.com/don/BluetoothSerial] plugin which was taken as inspiration for the API on this plugin but it does not handle BlueTooth classic devices on iOS.

## AppStore Approval
If you use this plugin and want to put your App on the AppStore you will need to apply for the Apple MFI program, I actually don't know too much about this as I am yet to push my App to the AppStore and I think I will be ok since BlueTherm have their device as MFI compliant and our App will be running under their compliance umbrella.




