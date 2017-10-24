//
//  DiscoveryManager.m
//  Connect SDK
//
//  Created by Jeremy White on 12/2/13.
//  Copyright (c) 2014 LG Electronics.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "DiscoveryManager_Private.h"

#import "DiscoveryProviderDelegate.h"
#import "DiscoveryProvider.h"

#import "ConnectSDKDefaultPlatforms.h"

#if defined(CHROMECAST)
#import "CastDiscoveryProvider.h"
#endif
#import "SSDPDiscoveryProvider.h"
#import "ZeroConfDiscoveryProvider.h"
#if defined(ORANGECAST)
#import "OrangeCastDiscoveryProvider.h"
#endif

#if defined(CHROMECAST)
#import "CastService.h"
#endif
#import "AirPlayService.h"
#import "RokuService.h"
#import "WebOSTVService.h"
#import "DLNAService.h"
#import "NetcastTVService.h"
#if defined(ORANGECAST)
#import "OrangeCastService.h"
#endif

#import "ConnectableDevice.h"
#import "DefaultConnectableDeviceStore.h"
#import "ServiceDescription.h"
#import "ServiceConfig.h"
#import "ServiceConfigDelegate.h"
#import "CapabilityFilter.h"

#import "AppStateChangeNotifier.h"

#import <SystemConfiguration/CaptiveNetwork.h>

@interface DiscoveryManager() <DiscoveryProviderDelegate, ServiceConfigDelegate>

@end

@implementation DiscoveryManager
{
    NSMutableDictionary *_allDevices;
    NSMutableDictionary *_compatibleDevices;

    BOOL _shouldResumeSearch;
    BOOL _searching;
    
    DevicePicker *_currentPicker;

    NSTimer *_ssidTimer;
    NSString *_currentSSID;
}

@synthesize pairingLevel = _pairingLevel;
@synthesize useDeviceStore = _useDeviceStore;

+ (DiscoveryManager *) _sharedManager
{
    static dispatch_once_t predicate = 0;
    __strong static id _sharedManager = nil;

    dispatch_once(&predicate, ^{
        _sharedManager = [[self alloc] init];
    });

    return _sharedManager;
}

+ (DiscoveryManager *) sharedManager
{
    DiscoveryManager *manager = [self _sharedManager];

    if (!manager.deviceStore && manager.useDeviceStore)
        [manager setDeviceStore:[DefaultConnectableDeviceStore new]];

    return manager;
}

+ (DiscoveryManager *) sharedManagerWithDeviceStore:(id <ConnectableDeviceStore>)deviceStore
{
    DiscoveryManager *manager = [self _sharedManager];

    if (deviceStore == nil || manager.deviceStore != deviceStore)
        [manager setDeviceStore:deviceStore];

    return manager;
}

- (void) setDeviceStore:(id <ConnectableDeviceStore>)deviceStore
{
    _deviceStore = deviceStore;
    _useDeviceStore = (_deviceStore != nil);
}

- (instancetype)init {
    return [self initWithAppStateChangeNotifier:nil];
}

#pragma mark - Private Init

- (instancetype) initWithAppStateChangeNotifier:(nullable AppStateChangeNotifier *)stateNotifier
{
    self = [super init];
    
    if (self)
    {
        _shouldResumeSearch = NO;
        _searching = NO;
        _useDeviceStore = YES;
        
        _discoveryProviders = [[NSMutableArray alloc] init];
        _deviceClasses = [[NSMutableDictionary alloc] init];

        _allDevices = [[NSMutableDictionary alloc] init];
        _compatibleDevices = [[NSMutableDictionary alloc] init];

        _appStateChangeNotifier = stateNotifier ?: [AppStateChangeNotifier new];
        __weak typeof(self) wself = self;
        _appStateChangeNotifier.didBackgroundBlock = ^{
            typeof(self) sself = wself;
            [sself pauseDiscovery];
        };
        _appStateChangeNotifier.didForegroundBlock = ^{
            typeof(self) sself = wself;
            [sself resumeDiscovery];
        };

        [self startSSIDTimer];
    }
    
    return self;
}

#pragma mark - Setup & Registration

- (void) registerDefaultServices
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *filter = [defaults objectForKey:@"casting"];
    if (filter) {
#if defined(CHROMECAST)
        if ([[defaults valueForKeyPath:@"casting.chromecast"] boolValue]) {
            [self registerDeviceService:[CastService class] withDiscovery:[CastDiscoveryProvider class]];
        }
#endif
#if defined(ORANGECAST)
		if ([[defaults valueForKeyPath:@"casting.orangecast"] boolValue]) {
			[self registerDeviceService:[OrangeCastService class] withDiscovery:[OrangeCastDiscoveryProvider class]];
		}
#endif
        if ([[defaults valueForKeyPath:@"casting.airties"] boolValue]) {
//            [self registerDeviceService:[AirTiesService class] withDiscovery:[SSDPDiscoveryProvider class]];
        }
        if ([[defaults valueForKeyPath:@"casting.airplay"] boolValue]) {
            [self registerDeviceService:[AirPlayService class] withDiscovery:[ZeroConfDiscoveryProvider class]];
        }
        if ([[defaults valueForKeyPath:@"casting.dial"] boolValue]) {
            [self registerDeviceService:[DIALService class] withDiscovery:[SSDPDiscoveryProvider class]];
        }
        if ([[defaults valueForKeyPath:@"casting.roku"] boolValue]) {
            [self registerDeviceService:[RokuService class] withDiscovery:[SSDPDiscoveryProvider  class]];
        }
        if ([[defaults valueForKeyPath:@"casting.dlna"] boolValue]) {
            [self registerDeviceService:[DLNAService class] withDiscovery:[SSDPDiscoveryProvider class]];
        }
        if ([[defaults valueForKeyPath:@"casting.netcasttv"] boolValue]) {
            [self registerDeviceService:[NetcastTVService class] withDiscovery:[SSDPDiscoveryProvider class]];
        }
        if ([[defaults valueForKeyPath:@"casting.webostv"] boolValue]) {
            [self registerDeviceService:[WebOSTVService class] withDiscovery:[SSDPDiscoveryProvider class]];
        }
    } else {
		NSDictionary *defaultPlatforms = kConnectSDKDefaultPlatforms;
		
		[defaultPlatforms enumerateKeysAndObjectsUsingBlock:^(NSString *platformClassName, NSString *discoveryProviderClassName, BOOL *stop) {
			Class platformClass = NSClassFromString(platformClassName);
			Class discoveryProviderClass = NSClassFromString(discoveryProviderClassName);
			
			[self registerDeviceService:platformClass withDiscovery:discoveryProviderClass];
		}];
    }
}

- (void) registerDeviceService:(Class)deviceClass withDiscovery:(Class)discoveryClass
{
    if (![discoveryClass isSubclassOfClass:[DiscoveryProvider class]])
        return;

    [self registerDeviceService:deviceClass
   withDiscoveryProviderFactory:^DiscoveryProvider *{
       return [discoveryClass new];
   }];
}

- (void)registerDeviceService:(Class)deviceClass
 withDiscoveryProviderFactory:(DiscoveryProvider *(^)(void))providerFactory
{
    if (![deviceClass isSubclassOfClass:[DeviceService class]])
        return;
    
    __block DiscoveryProvider *discoveryProvider;
    // FIXME don't create new provider unless necessary
    DiscoveryProvider *newDiscoveryProvider = providerFactory();
    
    [_discoveryProviders enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([[obj class] isSubclassOfClass:[newDiscoveryProvider class]])
        {
            discoveryProvider = obj;
            *stop = YES;
        }
    }];
    
    if (discoveryProvider == nil)
    {
        discoveryProvider = newDiscoveryProvider;
        discoveryProvider.delegate = self;
        _discoveryProviders = [_discoveryProviders arrayByAddingObject:discoveryProvider];
    }
    
    NSDictionary *discoveryParameters = [deviceClass discoveryParameters];
    
    NSString *serviceId = [discoveryParameters objectForKey:@"serviceId"];

    NSMutableDictionary *mutableClasses = [NSMutableDictionary dictionaryWithDictionary:_deviceClasses];
    [mutableClasses setObject:deviceClass forKey:serviceId];
    _deviceClasses = [NSDictionary dictionaryWithDictionary:mutableClasses];
    
    [discoveryProvider addDeviceFilter:discoveryParameters];
}

- (void) unregisterDeviceService:(Class)deviceClass withDiscovery:(Class)discoveryClass
{
    if (![discoveryClass isSubclassOfClass:[DiscoveryProvider class]])
        return;
    
    if (![deviceClass isSubclassOfClass:[DeviceService class]])
        return;
    
    __block DiscoveryProvider *discoveryProvider;
    
    [_discoveryProviders enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([[obj class] isSubclassOfClass:discoveryClass])
        {
            discoveryProvider = obj;
            *stop = YES;
        }
    }];
    
    if (discoveryProvider == nil)
        return;
    
    NSDictionary *discoveryParameters = [discoveryClass discoveryParameters];
    
    NSString *serviceId = [discoveryParameters objectForKey:@"serviceId"];

    NSMutableDictionary *mutableClasses = [NSMutableDictionary dictionaryWithDictionary:_deviceClasses];
    [mutableClasses removeObjectForKey:serviceId];
    _deviceClasses = [NSDictionary dictionaryWithDictionary:mutableClasses];
    
    [discoveryProvider removeDeviceFilter:discoveryParameters];
    
    if ([discoveryProvider isEmpty])
    {
        [discoveryProvider stopDiscovery];
        discoveryProvider.delegate = nil;

        NSMutableArray *mutableProviders = [NSMutableArray arrayWithArray:_discoveryProviders];
        [mutableProviders removeObject:discoveryProvider];
        _discoveryProviders = [NSArray arrayWithArray:mutableProviders];
    }
}

#pragma mark - Wireless SSID Change Detection

- (void) startSSIDTimer
{
    if (_ssidTimer) {
        [_ssidTimer invalidate];
        _ssidTimer = nil;
    }
    _ssidTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(detectSSIDChange) userInfo:nil repeats:YES];
    [_ssidTimer fire];
}

- (void) stopSSIDTimer
{
    [_ssidTimer invalidate];
    _ssidTimer = nil;
}

- (void) detectSSIDChange
{
    NSArray *interfaces = (__bridge_transfer id) CNCopySupportedInterfaces();

    __block NSString *ssidName;

    [interfaces enumerateObjectsUsingBlock:^(NSString *interface, NSUInteger idx, BOOL *stop)
    {
        if ([interface caseInsensitiveCompare:@"en0"] != NSOrderedSame)
            return;

        NSDictionary *info = (__bridge_transfer id) CNCopyCurrentNetworkInfo ((__bridge CFStringRef) interface);

        if (info && [info objectForKey:@"SSID"])
        {
            ssidName = [info objectForKey:@"SSID"];
            *stop = YES;
        }
    }];

    if (ssidName == nil)
        ssidName = @"";

    if ([ssidName caseInsensitiveCompare:_currentSSID] != NSOrderedSame)
    {
        if (_currentSSID != nil)
        {
            [self purgeDeviceList];

            [[NSNotificationCenter defaultCenter] postNotificationName:kConnectSDKWirelessSSIDChanged object:nil];
        }

        _currentSSID = ssidName;
    }
}

- (void) purgeDeviceList
{
    [self.compatibleDevices enumerateKeysAndObjectsUsingBlock:^(id key, ConnectableDevice *device, BOOL *stop)
    {
		if (![device.serviceDescription.serviceId isEqualToString:@"kUsersDeviceServiceId"]) { //no need to delete users device from list
			[device disconnect];
			
			if (self.delegate)
				[self.delegate discoveryManager:self didLoseDevice:device];
			
			if (self.devicePicker)
				[self.devicePicker discoveryManager:self didLoseDevice:device];
		}
    }];
    
    [_discoveryProviders enumerateObjectsUsingBlock:^(DiscoveryProvider *provider, NSUInteger idx, BOOL *stop) {
        if ([provider isKindOfClass:NSClassFromString(@"CastDiscoveryProvider")]
            || [provider isKindOfClass:NSClassFromString(@"OrangeCastDiscoveryProvider")]
            ) {
            //no need to restart discovery for chromecast and orangecast
        } else {
            [provider stopDiscovery];
            [provider startDiscovery];
        }
    }];

//    _allDevices = [NSMutableDictionary new]; //there is an issue when you are disabling wifi and after it
//    _compatibleDevices = [NSMutableDictionary new]; //delegate doesnt known that cc device is went offline
}

#pragma mark - Capability Filtering

- (void)setCapabilityFilters:(NSArray *)capabilityFilters
{
    _capabilityFilters = capabilityFilters;

    @synchronized (_compatibleDevices)
    {
        [_compatibleDevices enumerateKeysAndObjectsUsingBlock:^(NSString *address, ConnectableDevice *device, BOOL *stop)
        {
            if (self.delegate)
                [self.delegate discoveryManager:self didLoseDevice:device];
        }];
    }

    _compatibleDevices = [[NSMutableDictionary alloc] init];
	
    NSArray *allDevices;

    @synchronized (_allDevices) { allDevices = [_allDevices allValues]; }

    [allDevices enumerateObjectsUsingBlock:^(ConnectableDevice *device, NSUInteger idx, BOOL *stop)
    {
        if ([self deviceIsCompatible:device])
        {
            @synchronized (_compatibleDevices) { [_compatibleDevices setValue:device forKey:device.address]; }

            if (self.delegate)
                [self.delegate discoveryManager:self didFindDevice:device];
        }
    }];
}

- (BOOL) descriptionIsNetcastTV:(ServiceDescription *)description
{
    BOOL isNetcast = NO;

    if ([description.modelName.uppercaseString isEqualToString:@"LG TV"])
    {
        if ([description.modelDescription.uppercaseString rangeOfString:@"WEBOS"].location == NSNotFound)
        {
            isNetcast = [description.serviceId isEqualToString:kConnectSDKNetcastTVServiceId];
        }
    }

    return isNetcast;
}

#pragma mark - Device lists

- (NSDictionary *) allDevices
{
    return [NSDictionary dictionaryWithDictionary:_allDevices];
}

- (NSDictionary *)compatibleDevices
{
    return [NSDictionary dictionaryWithDictionary:_compatibleDevices];
}

- (BOOL) deviceIsCompatible:(ConnectableDevice *)device
{
    if (!_capabilityFilters || _capabilityFilters.count == 0)
        return YES;

    __block BOOL isCompatible = NO;

    [self.capabilityFilters enumerateObjectsUsingBlock:^(CapabilityFilter *filter, NSUInteger idx, BOOL *stop)
    {
        if ([device hasCapabilities:filter.capabilities])
        {
            isCompatible = YES;
            *stop = YES;
        }
    }];

    return isCompatible;
}

- (void) handleDeviceAdd:(ConnectableDevice *)device
{
    if (![self deviceIsCompatible:device])
        return;

    @synchronized (_compatibleDevices) { [_compatibleDevices setValue:device forKey:device.address]; }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kCastDeviceAvailabilityChanged" object:nil];

    if (self.delegate)
        [self.delegate discoveryManager:self didFindDevice:device];

    if (_currentPicker)
        [_currentPicker discoveryManager:self didFindDevice:device];
}

- (void) handleDeviceUpdate:(ConnectableDevice *)device
{
    [self.deviceStore updateDevice:device];

    if ([self deviceIsCompatible:device])
    {
        @synchronized (_compatibleDevices) {
            if ([_compatibleDevices objectForKey:device.address])
            {
                [[NSNotificationCenter defaultCenter] postNotificationName:@"kCastDeviceAvailabilityChanged" object:nil];
                
                if (self.delegate)
                    [self.delegate discoveryManager:self didUpdateDevice:device];

                if (_currentPicker)
                    [_currentPicker discoveryManager:self didUpdateDevice:device];
            } else
            {
                [self handleDeviceAdd:device];
            }
        }
    } else
    {
        @synchronized (_compatibleDevices) { [_compatibleDevices removeObjectForKey:device.address]; }

        [self handleDeviceLoss:device];
    }
}

- (void) handleDeviceLoss:(ConnectableDevice *)device
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kCastDeviceAvailabilityChanged" object:nil];
    
    if (self.delegate)
        [self.delegate discoveryManager:self didLoseDevice:device];

    if (_currentPicker)
        [_currentPicker discoveryManager:self didLoseDevice:device];
}

- (void)setPairingLevel:(DeviceServicePairingLevel)pairingLevel
{
    NSAssert(!_searching, @"Cannot change pairing level while DiscoveryManager is running.");

    _pairingLevel = pairingLevel;
}

#pragma mark - Control

- (void) startDiscovery
{
    if (_searching)
        return;

    if (_deviceClasses.count == 0)
        [self registerDefaultServices];

    _searching = YES;
    
    [_discoveryProviders enumerateObjectsUsingBlock:^(DiscoveryProvider *service, NSUInteger idx, BOOL *stop) {
        [service startDiscovery];
    }];

    [self.appStateChangeNotifier startListening];
}

- (void) stopDiscovery
{
    if (!_searching)
        return;

    _searching = NO;
    
    [_discoveryProviders enumerateObjectsUsingBlock:^(DiscoveryProvider *service, NSUInteger idx, BOOL *stop) {
        [service stopDiscovery];
    }];
    
    if (!_shouldResumeSearch)
    {
        [self.appStateChangeNotifier stopListening];
    }
}

/// Pauses all discovery providers and the SSID change timer.
- (void)pauseDiscovery {
    // moved from -hAppDidEnterBackground:
    [self stopSSIDTimer];

    if (_searching)
    {
        _searching = NO;
        _shouldResumeSearch = YES;

        [self.discoveryProviders enumerateObjectsUsingBlock:^(DiscoveryProvider *provider, NSUInteger idx, BOOL *stop) {
            if ([provider isKindOfClass:NSClassFromString(@"CastDiscoveryProvider")]
                || [provider isKindOfClass:NSClassFromString(@"OrangeCastDiscoveryProvider")]
                ) {
                //no need to pause discovery for chromecast and orangecast
            } else {
                [provider pauseDiscovery];
            }
        }];
        
    }
}

/// Resumes all discovery providers and the SSID change timer.
- (void)resumeDiscovery {
    // moved from -hAppDidBecomeActive:
    [self startSSIDTimer];

    if (_shouldResumeSearch)
    {
        _searching = YES;
        _shouldResumeSearch = NO;

        [self.discoveryProviders makeObjectsPerformSelector:@selector(resumeDiscovery)];
    }
}

#pragma mark - DiscoveryProviderDelegate methods

- (void)discoveryProvider:(DiscoveryProvider *)provider didFindService:(ServiceDescription *)description
{
    DLog(@"%@ (%@)", description.friendlyName, description.serviceId);

    BOOL deviceIsNew = [_allDevices objectForKey:description.address] == nil;
    ConnectableDevice *device;

    if (deviceIsNew)
    {
        if (self.useDeviceStore)
        {
            device = [self.deviceStore deviceForId:description.UUID];

            if (device)
                @synchronized (_allDevices) { [_allDevices setObject:device forKey:description.address]; }
        }
    } else
    {
        @synchronized (_allDevices) { device = [_allDevices objectForKey:description.address]; }
    }

    if (!device)
    {
        device = [ConnectableDevice connectableDeviceWithDescription:description];
        @synchronized (_allDevices) { [_allDevices setObject:device forKey:description.address]; }
        deviceIsNew = YES;
    }

    device.lastDetection = [[NSDate date] timeIntervalSince1970];
    device.lastKnownIPAddress = description.address;
    device.lastSeenOnWifi = _currentSSID;

    [self addServiceDescription:description toDevice:device];

    if (device.services.count == 0)
    {
        // we get here when a non-LG DLNA TV is found

        [_allDevices removeObjectForKey:description.address];
        device = nil;

        return;
    }

    if (deviceIsNew)
        [self handleDeviceAdd:device];
    else
        [self handleDeviceUpdate:device];
}

- (void)discoveryProvider:(DiscoveryProvider *)provider didLoseService:(ServiceDescription *)description
{
    DLog(@"%@ (%@)", description.friendlyName, description.serviceId);
    
    ConnectableDevice *device;

    @synchronized (_allDevices) { device = [_allDevices objectForKey:description.address]; }
    
    if (device)
    {
        [device removeServiceWithId:description.serviceId];

        DLog(@"Removed service from device at address %@. Device has %lu services left",
             description.address, (unsigned long)device.services.count);

        if (![device hasServices])
        {
            DLog(@"Device at address %@ has been orphaned (has no services)", description.address);

            @synchronized (_allDevices) { [_allDevices removeObjectForKey:description.address]; }
            @synchronized (_compatibleDevices) { [_compatibleDevices removeObjectForKey:description.address]; }

            [self handleDeviceLoss:device];
        } else
        {
            [self handleDeviceUpdate:device];
        }
    }
}

- (void)discoveryProvider:(DiscoveryProvider *)provider didFailWithError:(NSError *)error
{
    DLog(@"%@", error.localizedDescription);
}

#pragma mark - Helper methods

- (void) addServiceDescription:(ServiceDescription *)description toDevice:(ConnectableDevice *)device
{
    Class deviceServiceClass = [_deviceClasses objectForKey:description.serviceId];

    // TODO: move this logic into DeviceService subclass init methods
    if (deviceServiceClass == [DLNAService class])
    {
        if (!description.locationXML)
            return;
    } else if (deviceServiceClass == [NetcastTVService class])
    {
        if (![self descriptionIsNetcastTV:description])
            return;
    }

    ServiceConfig *serviceConfig;

    if (self.useDeviceStore)
        serviceConfig = [self.deviceStore serviceConfigForUUID:description.UUID];

    if (!serviceConfig)
        serviceConfig = [[ServiceConfig alloc] initWithServiceDescription:description];

    serviceConfig.delegate = self;

    __block BOOL deviceAlreadyHasServiceType = NO;
    __block BOOL deviceAlreadyHasService = NO;

    [device.services enumerateObjectsUsingBlock:^(DeviceService *obj, NSUInteger idx, BOOL *stop) {
        if ([obj.serviceDescription.serviceId isEqualToString:description.serviceId])
        {
            deviceAlreadyHasServiceType = YES;

            if ([obj.serviceDescription.UUID isEqualToString:description.UUID])
                deviceAlreadyHasService = YES;

            *stop = YES;
        }
    }];

    if (deviceAlreadyHasServiceType)
    {
        if (deviceAlreadyHasService)
        {
            device.serviceDescription = description;
            
            DeviceService *alreadyAddedService = [device serviceWithName:description.serviceId];
            
            if (alreadyAddedService)
                alreadyAddedService.serviceDescription = description;
            
            return;
        }

        [device removeServiceWithId:description.serviceId];
    }

    DeviceService *deviceService = [DeviceService deviceServiceWithClass:deviceServiceClass serviceConfig:serviceConfig];
    [deviceService setServiceDescription:description];
    [device addService:deviceService];
}

#pragma mark - ConnectableDeviceDelegate methods

- (void) connectableDevice:(ConnectableDevice *)device capabilitiesAdded:(NSArray *)added removed:(NSArray *)removed
{
    [self handleDeviceUpdate:device];
}

- (void)connectableDeviceReady:(ConnectableDevice *)device { }

- (void)connectableDeviceReady:(ConnectableDevice *)device mediaControl:(id<MediaControl>)mediaControl { }

- (void)connectableDeviceDisconnected:(ConnectableDevice *)device withError:(NSError *)error { }

#pragma mark - Device Store

- (ConnectableDevice *) lookupMatchingDeviceForDeviceStore:(ServiceConfig *)serviceConfig
{
    __block ConnectableDevice *foundDevice;

    @synchronized (_allDevices) {
        [_allDevices enumerateKeysAndObjectsUsingBlock:^(id key, ConnectableDevice *device, BOOL *deviceStop)
        {
            [device.services enumerateObjectsUsingBlock:^(DeviceService *service, NSUInteger serviceIdx, BOOL *serviceStop)
            {
                if ([service.serviceConfig.UUID isEqualToString:serviceConfig.UUID])
                {
                    foundDevice = device;

                    *serviceStop = YES;
                    *deviceStop = YES;
                }
            }];
        }];
    }

    return foundDevice;
}

#pragma mark - Device Picker creation

- (DevicePicker *) devicePicker
{
    return _currentPicker;
}

- (void)setDevicePicker:(DevicePicker *)devicePicker {
	_currentPicker = devicePicker;
	[self.compatibleDevices enumerateKeysAndObjectsUsingBlock:^(NSString *address, ConnectableDevice *device, BOOL *stop)
	 {
		 [_currentPicker discoveryManager:self didFindDevice:device];
	 }];
}

- (void)removeDevicePicker {
    if (_currentPicker != nil) {
        _currentPicker = nil;
    }
}

#pragma mark - ServiceConfigDelegate

- (void)serviceConfigUpdate:(ServiceConfig *)serviceConfig
{
    if (_useDeviceStore && self.deviceStore)
    {
        ConnectableDevice *device = [self lookupMatchingDeviceForDeviceStore:serviceConfig];

        if (device)
            [self.deviceStore updateDevice:device];
    }
}

@end
