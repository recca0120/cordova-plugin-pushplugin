/*
 Copyright 2009-2011 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binaryform must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided withthe distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "PushPlugin.h"

@implementation PushPlugin

@synthesize notificationMessage;
@synthesize isInline;

@synthesize callbackId;
@synthesize notificationCallbackId;
@synthesize callback;


- (void)unregister:(CDVInvokedUrlCommand*)command;
{
	self.callbackId = command.callbackId;
    ready = NO;

    [[UIApplication sharedApplication] unregisterForRemoteNotifications];
    [self successWithMessage:@"unregistered"];
}

- (void)register:(CDVInvokedUrlCommand*)command;
{
	self.callbackId = command.callbackId;

    NSMutableDictionary* options = [command.arguments objectAtIndex:0];

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
		UIUserNotificationType UserNotificationTypes = UIUserNotificationTypeNone;
#endif
    UIRemoteNotificationType notificationTypes = UIRemoteNotificationTypeNone;

    if ([options respondsToSelector:@selector(objectForKey:)]) {
    id badgeArg = [options objectForKey:@"badge"];
    id soundArg = [options objectForKey:@"sound"];
    id alertArg = [options objectForKey:@"alert"];

    if ([badgeArg isKindOfClass:[NSString class]])
    {
        if ([badgeArg isEqualToString:@"true"]) {
            notificationTypes |= UIRemoteNotificationTypeBadge;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
            UserNotificationTypes |= UIUserNotificationTypeBadge;
#endif
        }
    }
    else if ([badgeArg boolValue]) {
        notificationTypes |= UIRemoteNotificationTypeBadge;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
        UserNotificationTypes |= UIUserNotificationTypeBadge;
#endif
    }

    if ([soundArg isKindOfClass:[NSString class]])
    {
        if ([soundArg isEqualToString:@"true"]) {
            notificationTypes |= UIRemoteNotificationTypeSound;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
            UserNotificationTypes |= UIUserNotificationTypeSound;
#endif
    }
    }
    else if ([soundArg boolValue]) {
        notificationTypes |= UIRemoteNotificationTypeSound;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
        UserNotificationTypes |= UIUserNotificationTypeSound;
#endif
    }

    if ([alertArg isKindOfClass:[NSString class]])
    {
        if ([alertArg isEqualToString:@"true"]) {
            notificationTypes |= UIRemoteNotificationTypeAlert;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
            UserNotificationTypes |= UIUserNotificationTypeAlert;
#endif
    }
    }
    else if ([alertArg boolValue]) {
        notificationTypes |= UIRemoteNotificationTypeAlert;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
        UserNotificationTypes |= UIUserNotificationTypeAlert;
#endif
    }

    //notificationTypes |= UIRemoteNotificationTypeNewsstandContentAvailability;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    UserNotificationTypes |= UIUserNotificationActivationModeBackground;
#endif

    self.callback = [options objectForKey:@"ecb"];
    }

    if (notificationTypes == UIRemoteNotificationTypeNone)
        NSLog(@"PushPlugin.register: Push notification type is set to none");

    isInline = NO;

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    if ([[UIApplication sharedApplication]respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UserNotificationTypes categories:nil];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    } else {
    		[[UIApplication sharedApplication] registerForRemoteNotificationTypes:notificationTypes];
    }
#else
		[[UIApplication sharedApplication] registerForRemoteNotificationTypes:notificationTypes];
#endif

	if (notificationMessage)			// if there is a pending startup notification
		[self notificationReceived];	// go ahead and process it
}

/*
- (void)isEnabled:(NSMutableArray *)arguments withDict:(NSMutableDictionary *)options {
    UIRemoteNotificationType type = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];
    NSString *jsStatement = [NSString stringWithFormat:@"navigator.PushPlugin.isEnabled = %d;", type != UIRemoteNotificationTypeNone];
    NSLog(@"JSStatement %@",jsStatement);
}
*/

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {

    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    NSString *token = [[[[deviceToken description] stringByReplacingOccurrencesOfString:@"<"withString:@""]
                        stringByReplacingOccurrencesOfString:@">" withString:@""]
                       stringByReplacingOccurrencesOfString: @" " withString: @""];
    [results setValue:token forKey:@"deviceToken"];

    #if !TARGET_IPHONE_SIMULATOR
        // Get Bundle Info for Remote Registration (handy if you have more than one app)
        [results setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"] forKey:@"appName"];
        [results setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] forKey:@"appVersion"];

        // Check what Notifications the user has turned on.  We registered for all three, but they may have manually disabled some or all of them.
        NSUInteger rntypes;
        if (!SYSTEM_VERSION_LESS_THAN(@"8.0")) {
            rntypes = [[[UIApplication sharedApplication] currentUserNotificationSettings] types];
        } else {
            rntypes = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];
        }

        // Set the defaults to disabled unless we find otherwise...
        NSString *pushBadge = @"disabled";
        NSString *pushAlert = @"disabled";
        NSString *pushSound = @"disabled";

        // Check what Registered Types are turned on. This is a bit tricky since if two are enabled, and one is off, it will return a number 2... not telling you which
        // one is actually disabled. So we are literally checking to see if rnTypes matches what is turned on, instead of by number. The "tricky" part is that the
        // single notification types will only match if they are the ONLY one enabled.  Likewise, when we are checking for a pair of notifications, it will only be
        // true if those two notifications are on.  This is why the code is written this way
        if(rntypes & UIRemoteNotificationTypeBadge){
            pushBadge = @"enabled";
        }
        if(rntypes & UIRemoteNotificationTypeAlert) {
            pushAlert = @"enabled";
        }
        if(rntypes & UIRemoteNotificationTypeSound) {
            pushSound = @"enabled";
        }

        [results setValue:pushBadge forKey:@"pushBadge"];
        [results setValue:pushAlert forKey:@"pushAlert"];
        [results setValue:pushSound forKey:@"pushSound"];

        // Get the users Device Model, Display Name, Token & Version Number
        UIDevice *dev = [UIDevice currentDevice];
        [results setValue:dev.name forKey:@"deviceName"];
        [results setValue:dev.model forKey:@"deviceModel"];
        [results setValue:dev.systemVersion forKey:@"deviceSystemVersion"];

        ready = YES;

        NSMutableString *jsonStr = [NSMutableString stringWithString:@"{"];
        [jsonStr appendFormat:@"\"token\":\"%@\", ", token];
        if (notificationMessage) {
            [jsonStr appendFormat:@"\"notification\":\"%@\"", [self buildNotification:notificationMessage escapeQuotes:YES]];
            notificationMessage = nil;
        } else {
            [jsonStr appendFormat:@"\"notification\":\"%@\"", @""];
        }
        [jsonStr appendString:@"}"];

		[self successWithMessage:jsonStr];
    #endif
}

- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
	[self failWithMessage:@"" withError:error];
}

- (NSMutableString *) buildNotification:(NSDictionary *)notification {
    return [self buildNotification:notification escapeQuotes:NO];
}

- (NSMutableString *) buildNotification:(NSDictionary *)notification escapeQuotes:(BOOL) escapeQuotes {
    NSMutableString *jsonStr = [NSMutableString stringWithString:@"{"];

    [self parseDictionary:notificationMessage intoJSON:jsonStr];

    if (isInline) {
        [jsonStr appendFormat:@"\"foreground\":\"%d\"", 1];
        isInline = NO;
    } else {
        [jsonStr appendFormat:@"\"foreground\":\"%d\"", 0];
    }

    [jsonStr appendString:@"}"];
    if (escapeQuotes) {
        NSMutableString *escapedJsonStr = [[jsonStr stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""] mutableCopy];
        return escapedJsonStr;
    } else {
        return jsonStr;
    }
}

- (void)notificationReceived {
    if (!notificationMessage || !self.callback) {
        return;
    }

    NSMutableString *jsonStr = [self buildNotification:notificationMessage];

    NSLog(@"Msg: %@", jsonStr);

		if (ready) {
		    NSString * jsCallBack = [NSString stringWithFormat:@"%@(%@);", self.callback, jsonStr];
		    [self.webView stringByEvaluatingJavaScriptFromString:jsCallBack];
		} else {
				double delayInSeconds = 2.0;
				dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);

				dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
						NSString * jsCallBack = [NSString stringWithFormat:@"%@(%@);", self.callback, jsonStr];
						[self.webView stringByEvaluatingJavaScriptFromString:jsCallBack];
				});
		}
    self.notificationMessage = nil;
}

// reentrant method to drill down and surface all sub-dictionaries' key/value pairs into the top level json
-(void)parseDictionary:(NSDictionary *)inDictionary intoJSON:(NSMutableString *)jsonString
{
    NSArray         *keys = [inDictionary allKeys];
    NSString        *key;

    for (key in keys)
    {
        id thisObject = [inDictionary objectForKey:key];

        if ([thisObject isKindOfClass:[NSDictionary class]])
            [self parseDictionary:thisObject intoJSON:jsonString];
        else if ([thisObject isKindOfClass:[NSString class]])
             [jsonString appendFormat:@"\"%@\":\"%@\",",
              key,
              [[[[inDictionary objectForKey:key]
                stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                 stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]
                 stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]];
        else {
            [jsonString appendFormat:@"\"%@\":\"%@\",", key, [inDictionary objectForKey:key]];
        }
    }
}

#ifdef __IPHONE_8_0

- (BOOL)checkNotificationType:(UIUserNotificationType)type
{
  UIUserNotificationSettings *currentSettings = [[UIApplication sharedApplication] currentUserNotificationSettings];

  return (currentSettings.types & type);
}

#endif

- (void)setApplicationIconBadgeNumber:(CDVInvokedUrlCommand *)command {

    self.callbackId = command.callbackId;

    NSMutableDictionary* options = [command.arguments objectAtIndex:0];
    int badge = [[options objectForKey:@"badge"] intValue] ?: 0;
    UIApplication *application = [UIApplication sharedApplication];

#ifdef __IPHONE_8_0
    // compile with Xcode 6 or higher (iOS SDK >= 8.0)

    if(SYSTEM_VERSION_LESS_THAN(@"8.0"))
    {
       application.applicationIconBadgeNumber = badge;
    }
    else
    {
       if ([self checkNotificationType:UIUserNotificationTypeBadge])
       {
          NSLog(@"badge number changed to %d", badge);
          application.applicationIconBadgeNumber = badge;
       }
       else
          NSLog(@"access denied for UIUserNotificationTypeBadge");
    }

#else
    // compile with Xcode 5 (iOS SDK < 8.0)
    application.applicationIconBadgeNumber = badgeNumber;

#endif

    [self successWithMessage:[NSString stringWithFormat:@"app badge count set to %d", badge]];
}
-(void)successWithMessage:(NSString *)message
{
    if (self.callbackId != nil)
    {
        CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];
        [self.commandDelegate sendPluginResult:commandResult callbackId:self.callbackId];
    }
}

-(void)failWithMessage:(NSString *)message withError:(NSError *)error
{
    NSString        *errorMessage = (error) ? [NSString stringWithFormat:@"%@ - %@", message, [error localizedDescription]] : message;
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];

    [self.commandDelegate sendPluginResult:commandResult callbackId:self.callbackId];
}

@end
