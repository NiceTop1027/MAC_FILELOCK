#import "Vault.h"
#import "Crypto.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>

static const uint8_t kLockMagicV1[]  = { 'F', 'L', 'K', '1' };
static const uint8_t kLockMagicV2[]  = { 'F', 'L', 'K', '2' };
static const uint8_t kPayloadMagic[] = { 'F', 'L', 'P', '1' };
static const NSUInteger kMagicLen    = 4;
static const NSUInteger kLenLen      = 4;
static NSString * const kAdminRecoveryKey = @"6301d3a376dd1de392d3fdf7cb4da03bce281c6fa530b8e5263158e65b43468f";

static NSError *FLMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:FileLockErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *FLSHA256Hex(NSString *input) {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

BOOL FLAdminPasswordMatches(NSString *password) {
    return [[FLSHA256Hex(password) lowercaseString] isEqualToString:kAdminRecoveryKey];
}

static void FLAppendU32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = {
        (uint8_t)((value >> 24) & 0xff),
        (uint8_t)((value >> 16) & 0xff),
        (uint8_t)((value >> 8)  & 0xff),
        (uint8_t)(value & 0xff),
    };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static uint32_t FLReadU32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) |
           ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8)  |
           (uint32_t)bytes[3];
}

static NSString *FLSafeName(NSString *name) {
    NSString *safe = name.lastPathComponent;
    return safe.length ? safe : nil;
}

static NSString *FLCreateTempDirectory(NSString *suffix, NSError **err) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSUUID.UUID.UUIDString stringByAppendingString:suffix ?: @""]];
    if ([[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:err]) {
        return path;
    }
    return nil;
}

static NSData *FLReadPrefix(NSURL *url, NSUInteger length) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    if (!fh) return nil;
    NSData *data = [fh readDataUpToLength:length error:nil];
    [fh closeFile];
    return data;
}

static NSInteger FLContainerVersion(NSData *container) {
    if (container.length < kMagicLen) return 0;
    if (memcmp(container.bytes, kLockMagicV2, kMagicLen) == 0) return 2;
    if (memcmp(container.bytes, kLockMagicV1, kMagicLen) == 0) return 1;
    return 0;
}

static BOOL FLRunTask(NSString *tool,
                      NSArray<NSString *> *args,
                      NSURL *cwd,
                      NSString *failureMessage,
                      NSError **err) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = args;
    task.currentDirectoryURL = cwd;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (err) *err = launchError ?: FLMakeError(FileLockErrorIO, failureMessage);
        return NO;
    }

    [task waitUntilExit];
    if (task.terminationStatus != 0) {
        if (err) *err = FLMakeError(FileLockErrorIO, failureMessage);
        return NO;
    }
    return YES;
}

static NSData *FLPackPayload(NSData *payload, NSDictionary *meta, NSError **err) {
    NSData *metaData = [NSJSONSerialization dataWithJSONObject:meta options:0 error:err];
    if (!metaData) return nil;
    if (metaData.length > UINT32_MAX) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"파일 메타데이터가 너무 큽니다.");
        return nil;
    }

    NSMutableData *package = [NSMutableData dataWithCapacity:kMagicLen + kLenLen + metaData.length + payload.length];
    [package appendBytes:kPayloadMagic length:kMagicLen];
    FLAppendU32(package, (uint32_t)metaData.length);
    [package appendData:metaData];
    [package appendData:payload];
    return package;
}

static BOOL FLUnpackPayload(NSData *package,
                            NSDictionary **metaOut,
                            NSData **payloadOut,
                            NSError **err) {
    if (package.length < (kMagicLen + kLenLen)) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"잠금 파일 형식이 올바르지 않습니다.");
        return NO;
    }

    const uint8_t *bytes = package.bytes;
    if (memcmp(bytes, kPayloadMagic, kMagicLen) != 0) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"잠금 파일 형식이 올바르지 않습니다.");
        return NO;
    }

    uint32_t metaLen = FLReadU32(bytes + kMagicLen);
    NSUInteger headerLen = kMagicLen + kLenLen;
    NSUInteger totalMetaLen = headerLen + metaLen;
    if (package.length < totalMetaLen) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"잠금 파일이 손상되었습니다.");
        return NO;
    }

    NSData *metaData = [package subdataWithRange:NSMakeRange(headerLen, metaLen)];
    id json = [NSJSONSerialization JSONObjectWithData:metaData options:0 error:err];
    if (![json isKindOfClass:NSDictionary.class]) {
        if (err && !*err) *err = FLMakeError(FileLockErrorIO, @"잠금 파일 메타데이터를 읽을 수 없습니다.");
        return NO;
    }

    NSDictionary *meta = json;
    NSString *name = FLSafeName(meta[@"name"]);
    if (!name || ![meta[@"dir"] isKindOfClass:NSNumber.class] || ![meta[@"exec"] isKindOfClass:NSNumber.class]) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"잠금 파일 메타데이터가 올바르지 않습니다.");
        return NO;
    }

    if (metaOut) *metaOut = meta;
    if (payloadOut) *payloadOut = [package subdataWithRange:NSMakeRange(totalMetaLen, package.length - totalMetaLen)];
    return YES;
}

static BOOL FLExtractDualBlobs(NSData *container,
                               NSData **userBlobOut,
                               NSData **adminBlobOut,
                               NSError **err) {
    if (FLContainerVersion(container) != 2) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"지원하지 않는 잠금 파일 형식입니다.");
        return NO;
    }

    const uint8_t *bytes = container.bytes;
    NSUInteger offset = kMagicLen;
    if (container.length < offset + kLenLen) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"잠금 파일이 손상되었습니다.");
        return NO;
    }

    uint32_t userLen = FLReadU32(bytes + offset);
    offset += kLenLen;
    if (container.length < offset + userLen + kLenLen) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"잠금 파일이 손상되었습니다.");
        return NO;
    }

    NSData *userBlob = [container subdataWithRange:NSMakeRange(offset, userLen)];
    offset += userLen;

    uint32_t adminLen = FLReadU32(bytes + offset);
    offset += kLenLen;
    if (container.length != offset + adminLen) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"잠금 파일이 손상되었습니다.");
        return NO;
    }

    NSData *adminBlob = [container subdataWithRange:NSMakeRange(offset, adminLen)];
    if (userBlobOut) *userBlobOut = userBlob;
    if (adminBlobOut) *adminBlobOut = adminBlob;
    return YES;
}

static BOOL FLDecodeLockedContainerWithBlob(NSData *blob,
                                            NSString *password,
                                            NSDictionary **metaOut,
                                            NSData **payloadOut,
                                            NSError **err) {
    NSData *package = FL_Decrypt(blob, password, err);
    if (!package) return NO;

    return FLUnpackPayload(package, metaOut, payloadOut, err);
}

static BOOL FLDecodeUserLockedContainer(NSData *container,
                                        NSString *password,
                                        NSDictionary **metaOut,
                                        NSData **payloadOut,
                                        NSError **err) {
    NSInteger version = FLContainerVersion(container);
    if (version == 1) {
        NSData *blob = [container subdataWithRange:NSMakeRange(kMagicLen, container.length - kMagicLen)];
        return FLDecodeLockedContainerWithBlob(blob, password, metaOut, payloadOut, err);
    }
    if (version == 2) {
        NSData *userBlob = nil;
        if (!FLExtractDualBlobs(container, &userBlob, nil, err)) return NO;
        return FLDecodeLockedContainerWithBlob(userBlob, password, metaOut, payloadOut, err);
    }

    if (err) *err = FLMakeError(FileLockErrorIO, @"지원하지 않는 잠금 파일입니다.");
    return NO;
}

static BOOL FLDecodeAdminLockedContainer(NSData *container,
                                         NSString *adminPassword,
                                         NSDictionary **metaOut,
                                         NSData **payloadOut,
                                         NSError **err) {
    NSInteger version = FLContainerVersion(container);
    if (version == 1) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"이전 형식의 잠금 파일은 관리자 단독 해제를 지원하지 않습니다. 다시 잠가서 최신 형식으로 바꾸세요.");
        return NO;
    }
    if (version != 2) {
        if (err) *err = FLMakeError(FileLockErrorIO, @"지원하지 않는 잠금 파일입니다.");
        return NO;
    }

    if (!FLAdminPasswordMatches(adminPassword)) {
        if (err) *err = FLMakeError(FileLockErrorWrongPassword, @"관리자 비밀번호가 올바르지 않습니다.");
        return NO;
    }

    NSData *adminBlob = nil;
    if (!FLExtractDualBlobs(container, nil, &adminBlob, err)) return NO;
    return FLDecodeLockedContainerWithBlob(adminBlob, kAdminRecoveryKey, metaOut, payloadOut, err);
}

@implementation Vault {
    NSMutableArray<NSString *> *_tempDirs;
    dispatch_queue_t _q;
}

+ (instancetype)shared {
    static Vault *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [Vault new];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _tempDirs = [NSMutableArray new];
    _q = dispatch_queue_create("com.filelock.service", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)isLockedFileURL:(NSURL *)url {
    if ([url.pathExtension.lowercaseString isEqualToString:@"lock"]) return YES;
    NSData *prefix = FLReadPrefix(url, kMagicLen);
    return FLContainerVersion(prefix) != 0;
}

- (void)lockURL:(NSURL *)url
       password:(NSString *)pw
     completion:(void(^)(NSURL *lockURL, NSError *err))done {
    dispatch_async(_q, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *err = nil;

        if ([self isLockedFileURL:url]) {
            err = FLMakeError(FileLockErrorIO, @"이미 잠긴 .lock 파일입니다.");
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        BOOL isDir = NO;
        if (![fm fileExistsAtPath:url.path isDirectory:&isDir]) {
            err = FLMakeError(FileLockErrorIO, @"원본 파일을 찾을 수 없습니다.");
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        NSURL *lockURL = [[url URLByDeletingLastPathComponent]
                          URLByAppendingPathComponent:[url.lastPathComponent stringByAppendingString:@".lock"]];
        if ([fm fileExistsAtPath:lockURL.path]) {
            err = FLMakeError(FileLockErrorIO, @"같은 위치에 이미 .lock 파일이 있습니다.");
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        struct stat st;
        BOOL isExec = NO;
        if (!isDir && stat(url.fileSystemRepresentation, &st) == 0)
            isExec = ((st.st_mode & S_IXUSR) != 0);

        NSURL *sourceURL = url;
        NSString *tmpZipDir = nil;
        if (isDir) {
            tmpZipDir = FLCreateTempDirectory(@"_flzip", &err);
            if (!tmpZipDir) {
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }

            NSString *zipPath = [tmpZipDir stringByAppendingPathComponent:
                                 [url.lastPathComponent stringByAppendingString:@".zip"]];
            if (!FLRunTask(@"/usr/bin/zip",
                           @[ @"-r", @"-q", zipPath, url.lastPathComponent ],
                           [url URLByDeletingLastPathComponent],
                           @"폴더를 압축하지 못했습니다.",
                           &err)) {
                [fm removeItemAtPath:tmpZipDir error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }

            sourceURL = [NSURL fileURLWithPath:zipPath];
        }

        NSData *raw = [NSData dataWithContentsOfURL:sourceURL options:0 error:&err];
        if (tmpZipDir) [fm removeItemAtPath:tmpZipDir error:nil];
        if (!raw) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        NSDictionary *meta = @{
            @"name": url.lastPathComponent,
            @"dir": @(isDir),
            @"exec": @(isExec),
        };
        NSData *package = FLPackPayload(raw, meta, &err);
        if (!package) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        NSData *userBlob = FL_Encrypt(package, pw, &err);
        if (!userBlob) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        NSData *adminBlob = FL_Encrypt(package, kAdminRecoveryKey, &err);
        if (!adminBlob) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        NSMutableData *container = [NSMutableData dataWithCapacity:kMagicLen + (kLenLen * 2) + userBlob.length + adminBlob.length];
        [container appendBytes:kLockMagicV2 length:kMagicLen];
        FLAppendU32(container, (uint32_t)userBlob.length);
        [container appendData:userBlob];
        FLAppendU32(container, (uint32_t)adminBlob.length);
        [container appendData:adminBlob];
        if (![container writeToURL:lockURL options:NSDataWritingAtomic error:&err]) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }
        chmod(lockURL.fileSystemRepresentation, 0600);
        [lockURL setResourceValue:@YES forKey:NSURLHasHiddenExtensionKey error:nil];
        if (chflags(lockURL.fileSystemRepresentation, UF_IMMUTABLE) != 0) {
            err = FLMakeError(FileLockErrorIO, @"잠금 파일 보호 속성을 설정하지 못했습니다.");
            [fm removeItemAtURL:lockURL error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        if (![fm trashItemAtURL:url resultingItemURL:nil error:&err]) {
            chflags(lockURL.fileSystemRepresentation, 0);
            [fm removeItemAtURL:lockURL error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{ done(lockURL, nil); });
    });
}

- (void)openLockedFileAtURL:(NSURL *)lockURL
                   password:(NSString *)pw
                 completion:(void(^)(NSURL *openedURL, NSError *err))done {
    dispatch_async(_q, ^{
        NSError *err = nil;
        NSData *container = [NSData dataWithContentsOfURL:lockURL options:0 error:&err];
        if (!container) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        NSDictionary *meta = nil;
        NSData *payload = nil;
        if (!FLDecodeUserLockedContainer(container, pw, &meta, &payload, &err)) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        NSString *name = FLSafeName(meta[@"name"]);
        BOOL isDir = [meta[@"dir"] boolValue];
        BOOL isExec = [meta[@"exec"] boolValue];

        NSString *tmpDir = FLCreateTempDirectory(@"_flopen", &err);
        if (!tmpDir) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }
        [self->_tempDirs addObject:tmpDir];

        NSFileManager *fm = NSFileManager.defaultManager;
        NSURL *outURL = nil;
        if (isDir) {
            NSString *zipPath = [tmpDir stringByAppendingPathComponent:[name stringByAppendingString:@".zip"]];
            if (![payload writeToFile:zipPath options:NSDataWritingAtomic error:&err]) {
                [fm removeItemAtPath:tmpDir error:nil];
                [self->_tempDirs removeLastObject];
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }

            if (!FLRunTask(@"/usr/bin/unzip",
                           @[ @"-q", zipPath, @"-d", tmpDir ],
                           nil,
                           @"잠금 파일을 풀지 못했습니다.",
                           &err)) {
                [fm removeItemAtPath:tmpDir error:nil];
                [self->_tempDirs removeLastObject];
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }
            [fm removeItemAtPath:zipPath error:nil];
            outURL = [NSURL fileURLWithPath:[tmpDir stringByAppendingPathComponent:name]];
        } else {
            outURL = [NSURL fileURLWithPath:[tmpDir stringByAppendingPathComponent:name]];
            if (![payload writeToURL:outURL options:NSDataWritingAtomic error:&err]) {
                [fm removeItemAtPath:tmpDir error:nil];
                [self->_tempDirs removeLastObject];
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }
            if (isExec) chmod(outURL.fileSystemRepresentation, 0755);
        }

        if (![fm fileExistsAtPath:outURL.path]) {
            err = FLMakeError(FileLockErrorIO, @"복호화된 파일을 만들지 못했습니다.");
            [fm removeItemAtPath:tmpDir error:nil];
            [self->_tempDirs removeLastObject];
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{ done(outURL, nil); });
    });
}

- (void)permanentlyUnlockLockedFileAtURL:(NSURL *)lockURL
                           adminPassword:(NSString *)adminPassword
                              completion:(void(^)(NSURL *restoredURL, NSError *err))done {
    dispatch_async(_q, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *err = nil;
        NSData *container = [NSData dataWithContentsOfURL:lockURL options:0 error:&err];
        if (!container) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        NSDictionary *meta = nil;
        NSData *payload = nil;
        if (!FLDecodeAdminLockedContainer(container, adminPassword, &meta, &payload, &err)) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        NSString *name = FLSafeName(meta[@"name"]);
        BOOL isDir = [meta[@"dir"] boolValue];
        BOOL isExec = [meta[@"exec"] boolValue];

        NSURL *destURL = [[lockURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:destURL.path]) {
            err = FLMakeError(FileLockErrorIO, @"같은 위치에 복원될 원본 파일이 이미 있습니다.");
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        if (isDir) {
            NSString *tmpDir = FLCreateTempDirectory(@"_flrestore", &err);
            if (!tmpDir) {
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }

            NSString *zipPath = [tmpDir stringByAppendingPathComponent:[name stringByAppendingString:@".zip"]];
            if (![payload writeToFile:zipPath options:NSDataWritingAtomic error:&err]) {
                [fm removeItemAtPath:tmpDir error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }

            if (!FLRunTask(@"/usr/bin/unzip",
                           @[ @"-q", zipPath, @"-d", tmpDir ],
                           nil,
                           @"잠금 파일을 풀지 못했습니다.",
                           &err)) {
                [fm removeItemAtPath:tmpDir error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }

            NSURL *srcURL = [NSURL fileURLWithPath:[tmpDir stringByAppendingPathComponent:name]];
            if (![fm moveItemAtURL:srcURL toURL:destURL error:&err]) {
                [fm removeItemAtPath:tmpDir error:nil];
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }
            [fm removeItemAtPath:tmpDir error:nil];
        } else {
            if (![payload writeToURL:destURL options:NSDataWritingAtomic error:&err]) {
                dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
                return;
            }
            if (isExec) chmod(destURL.fileSystemRepresentation, 0755);
        }

        [destURL setResourceValue:@NO forKey:NSURLHasHiddenExtensionKey error:nil];
        if (chflags(lockURL.fileSystemRepresentation, 0) != 0) {
            [fm removeItemAtURL:destURL error:nil];
            err = FLMakeError(FileLockErrorIO, @"잠금 파일 보호 속성을 해제하지 못했습니다.");
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }
        if (![fm trashItemAtURL:lockURL resultingItemURL:nil error:&err]) {
            [fm removeItemAtURL:destURL error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{ done(destURL, nil); });
    });
}

- (void)cleanup {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *path in _tempDirs)
        [fm removeItemAtPath:path error:nil];
    [_tempDirs removeAllObjects];
}

@end
