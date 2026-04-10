#pragma once
#import <Foundation/Foundation.h>

@interface FLReleaseInfo : NSObject

@property (nonatomic, copy, readonly) NSString *version;
@property (nonatomic, strong, readonly) NSURL *releaseURL;
@property (nonatomic, strong, readonly) NSURL *downloadURL;

- (instancetype)initWithVersion:(NSString *)version
                     releaseURL:(NSURL *)releaseURL
                    downloadURL:(NSURL *)downloadURL;

@end

@interface FLUpdater : NSObject

+ (NSString *)currentAppVersion;
+ (NSComparisonResult)compareVersion:(NSString *)lhs to:(NSString *)rhs;

- (void)checkForUpdatesWithCompletion:(void(^)(FLReleaseInfo *info, BOOL hasUpdate, NSError *err))completion;

@end
