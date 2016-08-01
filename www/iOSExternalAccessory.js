var exec = require('cordova/exec');

var _module = "iOSExternalAccessory";

exports.getVersion = function(success, error) {
    exec(success, error, _module, "getVersion");
}

exports.listDevices = function(success, error) {
	exec(success, error, _module, "listDevices");
}

exports.connect = function(deviceId, protocol, success, error) {
	exec(success, error, _module, "connect", [deviceId, protocol]);
}

exports.listSessions = function(success, error) { 
	exec(success, error, _module, "listSessions");
}

exports.AccessorySession_write = function(sessionId, data, success, error) {
    // convert to ArrayBuffer
    if (typeof data === 'string') {
        data = stringToArrayBuffer(data);
    } else if (data instanceof Array) {
        // assuming array of integer
        data = new Uint8Array(data).buffer;
    } else if (data instanceof Uint8Array) {
        data = data.buffer;
    }

	exec(success, error, _module, "AccessorySession_write", [sessionId, data]);
}

exports.AccessorySession_subscribeRawData = function(sessionId, success, error) {
	exec(success, error, _module, "AccessorySession_subscribeRawData", [sessionId]);
}

exports.AccessorySession_unsubscribeRawData = function(sessionId, success, error) {
	exec(success, error, _module, "AccessorySession_unsubscribeRawData", [sessionId]);
}

exports.AccessorySession_disconnect = function(sessionId, success, error) {
	exec(success, error, _module, "AccessorySession_disconnect", [sessionId]);
}

exports.subscribeDeviceChanges = function(success, error) {
	exec(success, error, _module, "subscribeDeviceChanges");
}

exports.unsubscribeDeviceChanges = function(success, error) {
	exec(success, error, _module, "unsubscribeDeviceChanges");
}

