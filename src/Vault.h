#pragma once
#import <Foundation/Foundation.h>

BOOL FLAdminPasswordMatches(NSString *password);

@interface Vault : NSObject

+ (instancetype)shared;

- (BOOL)isLockedFileURL:(NSURL *)url;

- (void)lockURL:(NSURL *)url
       password:(NSString *)pw
     completion:(void(^)(NSURL *lockURL, NSError *err))done;

- (void)openLockedFileAtURL:(NSURL *)lockURL
                   password:(NSString *)pw
                 completion:(void(^)(NSURL *openedURL, NSError *err))done;

- (void)permanentlyUnlockLockedFileAtURL:(NSURL *)lockURL
                           adminPassword:(NSString *)adminPassword
                              completion:(void(^)(NSURL *restoredURL, NSError *err))done;

- (void)cleanup;

@end
