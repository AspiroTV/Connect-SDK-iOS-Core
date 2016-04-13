//
//  HACastContentDetails.h
//  HybridApp
//
//  Created by a_zhabort on 2/12/15.
//  Copyright (c) 2015 Norigin Media. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HACastContentDetails : NSObject

@property (nonatomic, copy, readonly) NSString *contentId;
@property (nonatomic, copy, readonly) NSString *contentTitle;
@property (nonatomic, copy, readonly) NSString *contentDescription;
@property (nonatomic, copy, readonly) NSString *contentImage;

@property (nonatomic, copy, readonly) NSString *uuid;
@property (nonatomic, copy, readonly) NSString *friendlyName;
@property (nonatomic, copy, readonly) NSString *sessionId;
@property (nonatomic, copy, readonly) NSString *encryptedUsername;
@property (nonatomic, copy, readonly) NSString *encryptedPassword;

@property (nonatomic, copy, readonly) NSString *config;

@property (nonatomic, copy) NSString *selectedAudio;
@property (nonatomic, copy) NSString *selectedSubtitle;

- (instancetype)initWithId:(NSString *)contentId
					 title:(NSString *)contentTitle
			   description:(NSString *)contentDescription
					 image:(NSString *)contentImage
					  uuid:(NSString *)uuid
			  friendlyName:(NSString *)friendlyName
				 sessionId:(NSString *)sessionId
				  username:(NSString *)encryptedUsername
				  password:(NSString *)encryptedPassword
					config:(NSString *)config;

@end
