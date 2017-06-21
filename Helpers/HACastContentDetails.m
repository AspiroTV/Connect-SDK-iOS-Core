//
//  HACastContentDetails.m
//  HybridApp
//
//  Created by a_zhabort on 2/12/15.
//  Copyright (c) 2015 Norigin Media. All rights reserved.
//

#import "HACastContentDetails.h"

@interface HACastContentDetails()

@property (nonatomic, copy, readwrite) NSString *contentId;
@property (nonatomic, copy, readwrite) NSString *contentTitle;
@property (nonatomic, copy, readwrite) NSString *contentDescription;
@property (nonatomic, copy, readwrite) NSString *contentImage;

@property (nonatomic, copy, readwrite) NSString *uuid;
@property (nonatomic, copy, readwrite) NSString *friendlyName;
@property (nonatomic, copy, readwrite) NSString *sessionId;
@property (nonatomic, copy, readwrite) NSString *encryptedUsername;
@property (nonatomic, copy, readwrite) NSString *encryptedPassword;

@property (nonatomic, copy, readwrite) NSString *config;

@property (nonatomic, copy, readwrite) NSString *channelAlias;
@property (nonatomic, copy, readwrite) NSString *channelPrograms;

@end

@implementation HACastContentDetails

- (instancetype)initWithId:(NSString *)contentId
					 title:(NSString *)contentTitle
			   description:(NSString *)contentDescription
					 image:(NSString *)contentImage
					  uuid:(NSString *)uuid
			  friendlyName:(NSString *)friendlyName
				 sessionId:(NSString *)sessionId
				  username:(NSString *)encryptedUsername
				  password:(NSString *)encryptedPassword
					config:(NSString *)config
              channelAlias:(NSString *)channelAlias
           channelPrograms:(NSString *)channelPrograms {
	self = [super init];
	if (self) {
		_contentId = contentId;
		_contentTitle = contentTitle;
		_contentDescription = contentDescription;
		_contentImage = contentImage;
		_uuid = uuid;
		_friendlyName = friendlyName;
		_sessionId = sessionId;
		_encryptedUsername = encryptedUsername;
		_encryptedPassword = encryptedPassword;
		_config = config;
        _channelAlias = channelAlias;
        _channelPrograms = channelPrograms;
	}
	return self;
}

@end
