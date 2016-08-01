/********* iOSExternalAccessory.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import <ExternalAccessory/ExternalAccessory.h>

#define PLUGIN_VERSION @"1.0.0"

NSMutableDictionary* getAccessoryInfo(EAAccessory* accessory)
{
	NSMutableDictionary* device = [[NSMutableDictionary alloc] init];

    [device setObject: [accessory name] forKey: @"name"];
    [device setObject: [NSNumber numberWithUnsignedInteger: accessory.connectionID] forKey:@"id"];
    [device setObject: [NSNumber numberWithBool: accessory.connected] forKey: @"connected"];
    [device setObject: [accessory manufacturer] forKey: @"manufacturer"];
    [device setObject: [accessory modelNumber] forKey: @"modelNumber"];
    [device setObject: [accessory serialNumber] forKey: @"serialNumber"];
    [device setObject: [accessory firmwareRevision] forKey: @"firmwareRevision"];
    [device setObject: [accessory hardwareRevision] forKey: @"hardwareRevision"];
    [device setObject: [[accessory protocolStrings] copy] forKey: @"protocolStrings"];

    return device;
}

NSString* streamEventName(NSStreamEvent event)
{
	switch(event) {
		case NSStreamEventNone:
			return @"None";

    	case NSStreamEventOpenCompleted:
    		return @"Open Completed";

	    case NSStreamEventHasBytesAvailable:
	    	return @"Bytes Available";

	    case NSStreamEventHasSpaceAvailable:
	    	return @"Space Available";

	    case NSStreamEventErrorOccurred:
	    	return @"Error";

	    case NSStreamEventEndEncountered:
	    	return @"End";
	}
	return @"Unknown";
}

@interface iOSExternalAccessory : CDVPlugin {
}

@property (nonatomic, retain) NSMutableDictionary* accessories;
@property (nonatomic, retain) NSMutableDictionary* sessions;
@property (nonatomic, retain) NSString* deviceChangeCallbackId;
@property (nonatomic, retain) NSArray* pausedSessions;

- (void)accessoryDidConnect:(EAAccessory*)accessory;
- (void)accessoryDidDisconnect:(EAAccessory*)accessory;

- (void)pluginInitialize;
- (void)dispose;

- (void)getVersion:(CDVInvokedUrlCommand*) command;
- (void)listDevices:(CDVInvokedUrlCommand*) command;
- (void)connect:(CDVInvokedUrlCommand*) command;
- (void)listSessions:(CDVInvokedUrlCommand*) command;

- (void)AccessorySession_write:(CDVInvokedUrlCommand*)command;
- (void)AccessorySession_subscribeRawData:(CDVInvokedUrlCommand*)command;
- (void)AccessorySession_unsubscribeRawData:(CDVInvokedUrlCommand*)command;
- (void)AccessorySession_disconnect:(CDVInvokedUrlCommand*)command;

- (void)receiveData:(NSData*)data callbackId:(NSString*)callbackId;

- (void)subscribeDeviceChanges:(CDVInvokedUrlCommand*)command;
- (void)unsubscribeDeviceChanges:(CDVInvokedUrlCommand*)command;

@end

@interface CommsHandler : NSObject<NSStreamDelegate> {
}

@property (nonatomic, readonly) NSString* sessionId;
@property (nonatomic, retain) iOSExternalAccessory* plugin;
@property (nonatomic, retain) NSString* callbackId;
@property (nonatomic, retain) EASession* session;
@property (nonatomic, retain) NSMutableData* writeBuffer;
@property (nonatomic, retain) NSInputStream* inputStream;
@property (nonatomic, retain) NSOutputStream* outputStream;

-(id) initWithPlugin:(iOSExternalAccessory*)thePlugin session:(EASession*)theSession callbackId:(NSString*)theCallbackId;
-(id) initWithPlugin:(iOSExternalAccessory*)thePlugin fromPaused:(NSDictionary*)paused;
-(void) writeData;
-(NSMutableDictionary*) info;
-(NSDictionary*) makePaused;

@end

@implementation CommsHandler

@synthesize sessionId, plugin, callbackId, session, writeBuffer, inputStream, outputStream;

-(void)openSession:(EASession*)theSession
{
	self.session = theSession;
	self.inputStream = session.inputStream;
	[session.inputStream setDelegate:self];
	[session.inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[session.inputStream open];

	self.outputStream = session.outputStream;
	[session.outputStream setDelegate:self];
	[session.outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[session.outputStream open];
}

- (id)initWithPlugin:(iOSExternalAccessory*)thePlugin session:(EASession*)theSession callbackId:(NSString*)theCallbackId
{
	if (self = [super init]) {
		sessionId = [NSString stringWithFormat: @"%lu:%@", (unsigned long)theSession.accessory.connectionID, theSession.protocolString];
		self.plugin = thePlugin;
		self.callbackId = theCallbackId;		
		self.writeBuffer = [[NSMutableData alloc] init];

		[self openSession: theSession];
	}	
	return self;
}

- (id)initWithPlugin:(iOSExternalAccessory*)thePlugin fromPaused:(NSDictionary*)paused
{
	if (self = [super init]) {
		EAAccessory* theAccessory = [paused objectForKey:@ "accessory"];
		NSString* theProtocolString = [paused objectForKey: @"protocolString"];
		NSString* theCallbackId = [paused objectForKey: @"callbackId"];

		EASession* theSession = [[EASession alloc] initWithAccessory: theAccessory forProtocol: theProtocolString];

		self = [self initWithPlugin: thePlugin session: theSession callbackId: theCallbackId];
	}
	return self;
}

-(void)dispose
{
	sessionId = nil;

	[inputStream setDelegate: nil];
	[inputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[inputStream close];
	self.inputStream = nil;

	[outputStream setDelegate: nil];
	[outputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	[outputStream close];
	self.outputStream = nil;
}

-(void)dealloc
{
	self.plugin = nil;
	self.session = nil;
	self.callbackId = nil;
	self.writeBuffer = nil;
	self.inputStream = nil;
	self.outputStream = nil;
}

-(NSMutableDictionary*)info
{
	NSMutableDictionary* result = getAccessoryInfo(session.accessory);
	[result setObject: sessionId forKey: @"sessionId"];
	return result;
}

- (void)stream:(NSStream *)theStream
   handleEvent:(NSStreamEvent)streamEvent
{
	NSLog(@"event %@ for %@ %@", streamEventName(streamEvent), sessionId, theStream == inputStream ? @"INPUT" :@"OUTPUT");

	if (streamEvent == NSStreamEventHasBytesAvailable) {
		NSMutableData* data = [[NSMutableData alloc] init];
		uint8_t buf[1024];
		NSInteger read = [inputStream read:buf maxLength: sizeof(buf)];
		while(read > 0) {
			[data appendBytes: buf length: read];
			read = [inputStream read:buf maxLength: sizeof(buf)];
		}

		if (callbackId != nil) {
			[plugin receiveData:data callbackId: callbackId];
		}
	} else if (streamEvent == NSStreamEventHasSpaceAvailable) {
		[self writeData];
	}
}

- (void) writeData
{
	if (outputStream.hasSpaceAvailable && writeBuffer.length > 0) {
		NSInteger written = [outputStream write:writeBuffer.bytes maxLength: writeBuffer.length];
		if (written == -1) {
			NSError* error = [outputStream streamError];
			NSLog(@"writeData error %i: %@", [error code], [error localizedDescription]);

			// Attempt to close and reopen this Session
			EAAccessory* accessory = self.session.accessory;
			NSString* protocol = self.session.protocolString;
			
			[self dispose];

			EASession* theSession = [[EASession alloc] initWithAccessory: accessory forProtocol: protocol];

			[self openSession: theSession];
		} else {
			[writeBuffer replaceBytesInRange:NSMakeRange(0, written) withBytes:NULL length:0];
		}
	}
}

- (NSDictionary*) makePaused 
{
	NSMutableDictionary* paused = [[NSMutableDictionary alloc] init];
	[paused setObject: callbackId forKey: @"callbackId"];
	[paused setObject: session.accessory forKey: @"accessory"];
	[paused setObject: session.protocolString forKey: @"protocolString"];
	return paused;
}
@end


@implementation iOSExternalAccessory

@synthesize accessories, sessions, deviceChangeCallbackId, pausedSessions;

-(void)pluginInitialize
{
	NSLog(@"pluginInitialize");
	[super pluginInitialize];
	self.sessions = [[NSMutableDictionary alloc] init];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onPause) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResume) name:UIApplicationWillEnterForegroundNotification object:nil];

	// Listen for Device Connects/Disconnects
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accessoryDidConnect:) name:EAAccessoryDidConnectNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accessoryDidDisconnect:) name:EAAccessoryDidDisconnectNotification object:nil];
    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
}

-(void)dispose
{
	NSLog(@"dispose");
	self.accessories = nil;
	self.sessions = nil;
	self.pausedSessions = nil;
	[super dispose];
}


-(void)receiveData:(NSData*)data callbackId:(NSString*)callbackId 
{
	NSLog(@"receiveData %u", [data length]);

	CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsArrayBuffer: data];
	[pluginResult setKeepCallbackAsBool:TRUE];
	[self.commandDelegate sendPluginResult: pluginResult callbackId: callbackId];
}

-(NSMutableArray*)getDevices
{
    NSArray* accessoryList = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    NSMutableArray* result = [[NSMutableArray alloc] init];
    
    self.accessories = [[NSMutableDictionary alloc] init];

    for(EAAccessory* accessory in accessoryList)
    {
    	NSDictionary* device = getAccessoryInfo(accessory);
        [result addObject: device];
        [accessories setObject: accessory forKey: [NSNumber numberWithUnsignedInteger: accessory.connectionID]];

        NSLog(@"Found device %@, %lu", [accessory name], (unsigned long)accessory.connectionID);
    }
    return result;
}

- (void)getVersion:(CDVInvokedUrlCommand*) command
{
	NSLog(@"getVersion:");
    NSMutableDictionary* result = [[NSMutableDictionary alloc] init];
    [result setObject: PLUGIN_VERSION forKey:@"version"];
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: result];
	    
    [self.commandDelegate sendPluginResult: pluginResult callbackId: command.callbackId];
}

- (void)listDevices:(CDVInvokedUrlCommand*) command
{
	NSLog(@"listDevices:");
	[self.commandDelegate runInBackground: ^{
	    NSMutableArray* result = [self getDevices];

	    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsArray: result];
	    
	    [self.commandDelegate sendPluginResult: pluginResult callbackId: command.callbackId];
	}];
}

- (void)onPause
{
	NSLog(@"onPause");
	
	// About to Pause, remember all sessions and disconnect them all, we will reconnect onResume
	NSMutableArray* paused = [[NSMutableArray alloc] init];

	for(NSString* sessionId in [sessions allKeys]) {
		CommsHandler* handler = [sessions objectForKey: sessionId];
		[paused addObject: [handler makePaused]];
		[handler dispose];
	}

	[sessions removeAllObjects];

	self.pausedSessions = paused;
}

- (void)onResume
{
	NSLog(@"onResume");
	
	// Reconnect accessories 
	for(NSDictionary* paused in pausedSessions) {
		CommsHandler* handler = [[CommsHandler alloc] initWithPlugin: self fromPaused: paused];
		[sessions setObject: handler forKey: handler.sessionId];
	}

	self.pausedSessions = nil;
}

- (void)accessoryDidConnect:(NSNotification *)notification
{
	EAAccessory* accessory = [notification.userInfo objectForKey: EAAccessoryKey];
	NSLog(@"accessoryDidConnect: %@", accessory.name);

	// For some reason we can get DidConnect with a partially filled Accessory, ignore these there should be another shortly
	if ([accessory.protocolStrings count] > 0) {
		// Update our list of Accessories if we can 
		if (accessories != nil) {
			[accessories setObject: accessory forKey: [NSNumber numberWithUnsignedInteger: accessory.connectionID]];
		}

		if (deviceChangeCallbackId != nil) {
			NSDictionary* info = getAccessoryInfo(accessory);
			NSMutableDictionary* args = [[NSMutableDictionary alloc] init];
			[args setObject: info forKey: @"accessory"];
			[args setObject: @"connected" forKey: @"event"];

			CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: args];
			[pluginResult setKeepCallbackAsBool:TRUE];
			[self.commandDelegate sendPluginResult: pluginResult callbackId: deviceChangeCallbackId];
		}
	}
}

- (void)accessoryDidDisconnect:(NSNotification *)notification
{
	EAAccessory* accessory = [notification.userInfo objectForKey: EAAccessoryKey];
	NSLog(@"accessoryDidDisconnect: %@", accessory.name);
	// For some reason we can get DidConnect with a partially filled Accessory, ignore these there should be another shortly
	if ([accessory.protocolStrings count] > 0) {
		// Have to kill any sessions attached to this Accessory
		for(NSString* sessionId in [sessions allKeys]) {
			CommsHandler* handler = [sessions objectForKey: sessionId];
			if (handler.session.accessory == accessory) {
				[sessions removeObjectForKey: sessionId];

				[handler dispose];
			}
		}

		if (deviceChangeCallbackId != nil) {
			NSDictionary* info = getAccessoryInfo(accessory);
			NSMutableDictionary* args = [[NSMutableDictionary alloc] init];
			[args setObject: info forKey: @"accessory"];
			[args setObject: @"disconnected" forKey: @"event"];

			CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: args];
			[pluginResult setKeepCallbackAsBool:TRUE];
			[self.commandDelegate sendPluginResult: pluginResult callbackId: deviceChangeCallbackId];
		}
	}
}

-(void)connect:(CDVInvokedUrlCommand*) command
{
	[self.commandDelegate runInBackground: ^{
		CDVPluginResult* pluginResult = nil;
		NSNumber* accessoryId = nil;
		NSString* protocol = nil;

		if (command.arguments.count >= 1) {
			accessoryId = [command.arguments objectAtIndex: 0];
		}

		if (command.arguments.count >= 2) {
			protocol = [[command.arguments objectAtIndex: 1] copy];
		}

		if (accessoryId == nil) {
			pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Missing argument 'accessoryId'"];
		}

		if (protocol == nil) {
			pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Missing argument 'protocol'"];
		} 

		if (accessoryId != nil && protocol != nil) {
			NSLog(@"connect: %@:%@", accessoryId, protocol);

			if (accessories == nil) {
				[self getDevices];
			}

			EAAccessory* accessory = [accessories objectForKey: accessoryId];
			if (accessory == nil) {
				pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Accessory not found"];
			} else {
				EASession* session = [[EASession alloc] initWithAccessory: accessory forProtocol: protocol];
				if (session == nil) {
					pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Session error"];
				} else {
					// We dont need this below since we are observing Notifications for DidConnect & DidDisconnect
//					[accessory setDelegate: self];
					
					CommsHandler* handler = [[CommsHandler alloc] initWithPlugin: self session: session callbackId: command.callbackId];
					[sessions setObject: handler forKey: handler.sessionId];

					NSLog(@"connect session = %@", handler.sessionId);

					pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: [handler info]];
				}
			}
		}

		[self.commandDelegate sendPluginResult: pluginResult callbackId: command.callbackId];
	}];
}

- (void)listSessions:(CDVInvokedUrlCommand*) command
{
	NSMutableArray* result = [[NSMutableArray alloc] init];
	for(NSString* sessionId in [sessions allKeys]) {
		CommsHandler* handler = [sessions objectForKey: sessionId];
		[result addObject: [handler info]];
		NSLog(@"listSessions found %@", handler.sessionId);
	}
	CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsArray: result];
	[self.commandDelegate sendPluginResult: pluginResult callbackId: command.callbackId];
}

- (void)AccessorySession_disconnect:(CDVInvokedUrlCommand*)command
{
	[self.commandDelegate runInBackground: ^{
		CDVPluginResult* pluginResult = nil;
		NSString* sessionId = nil;

		if (command.arguments.count >= 1) {
			sessionId = [command.arguments objectAtIndex: 0];
		}	

		if (sessionId == nil) {
			pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Missing argument 'sessionId'"];
		}

		if (sessionId != nil) {

			CommsHandler* handler = [sessions objectForKey: sessionId];
			if (handler == nil) {
				NSLog(@"disconnect: %@ - NOT FOUND", sessionId);
				pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Session not found"];
			} else {
				NSLog(@"disconnect: %@", sessionId);
				[sessions removeObjectForKey: sessionId];

				[handler dispose];

				pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK];
			}
		}

		if (pluginResult != nil) {
			[self.commandDelegate sendPluginResult: pluginResult callbackId: command.callbackId];
		}
	}];
}

- (void)AccessorySession_write:(CDVInvokedUrlCommand*)command
{
	CDVPluginResult* pluginResult = nil;
	NSString* sessionId = nil;
	NSData* data = nil;

	if (command.arguments.count >= 1) {
		sessionId = [command.arguments objectAtIndex: 0];
	}	

	if (command.arguments.count >= 2) {
		data = [command.arguments objectAtIndex: 1];
	}

	if (sessionId == nil) {
		pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Missing argument 'sessionId'"];
	}

	if (data == nil) {
		pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Missing argument 'data'"];
	}

	if (sessionId != nil && data != nil) {
		CommsHandler* handler = [sessions objectForKey: sessionId];
		if (handler == nil) {
			pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Session not found"];
		} else {
			NSLog(@"write %@", sessionId);

			[handler.writeBuffer appendData: data];
			[handler writeData];
			pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK];
		}
	}

	if (pluginResult != nil) {
		[self.commandDelegate sendPluginResult: pluginResult callbackId: command.callbackId];
	}
}

- (void)AccessorySession_subscribeRawData:(CDVInvokedUrlCommand*)command
{
	CDVPluginResult* pluginResult = nil;
	NSString* sessionId = nil;

	if (command.arguments.count >= 1) {
		sessionId = [command.arguments objectAtIndex: 0];
	}	

	if (sessionId == nil) {
		pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Missing argument 'sessionId'"];
	}

	if (sessionId != nil) {
		CommsHandler* handler = [sessions objectForKey: sessionId];
		if (handler == nil) {
			pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Session not found"];
		} else {
			NSLog(@"subscribeRawData: %@", sessionId);
			handler.callbackId = command.callbackId;
		}
	}

	if (pluginResult != nil) {
		[self.commandDelegate sendPluginResult: pluginResult callbackId: command.callbackId];
	}
}

- (void)AccessorySession_unsubscribeRawData:(CDVInvokedUrlCommand*)command
{
	CDVPluginResult* pluginResult = nil;
	NSString* sessionId = nil;

	if (command.arguments.count >= 1) {
		sessionId = [command.arguments objectAtIndex: 0];
	}	

	if (sessionId == nil) {
		pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Missing argument 'sessionId'"];
	}

	if (sessionId != nil) {
		CommsHandler* handler = [sessions objectForKey: sessionId];
		if (handler == nil) {
			pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: @"Session not found"];
		} else {
			NSLog(@"unsubscribeRawData: %@", sessionId);

			handler.callbackId = nil;
			pluginResult = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK];
		}
	}

	if (pluginResult != nil) {
		[self.commandDelegate sendPluginResult: pluginResult callbackId: command.callbackId];
	}
}

- (void)subscribeDeviceChanges:(CDVInvokedUrlCommand*)command
{
	self.deviceChangeCallbackId = [command.callbackId copy];
}

- (void)unsubscribeDeviceChanges:(CDVInvokedUrlCommand*)command
{
	self.deviceChangeCallbackId = nil;
}


@end
