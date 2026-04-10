#pragma once
#import <Foundation/Foundation.h>

extern NSErrorDomain const FileLockErrorDomain;

typedef NS_ENUM(NSInteger, FileLockError) {
    FileLockErrorWrongPassword = 1,
    FileLockErrorIO            = 2,
};

// AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC)
// PBKDF2-HMAC-SHA256, 200,000 iterations
// 포맷: salt(32) | IV(16) | HMAC(32) | ciphertext
NSData *FL_Encrypt(NSData *plain, NSString *password, NSError **err);
NSData *FL_Decrypt(NSData *blob,  NSString *password, NSError **err);
