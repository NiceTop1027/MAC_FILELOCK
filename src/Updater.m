#import "Updater.h"

static NSString * const FLGitHubLatestReleaseAPIURL = @"https://api.github.com/repos/NiceTop1027/MAC_FILELOCK/releases/latest";

@implementation FLReleaseInfo

- (instancetype)initWithVersion:(NSString *)version
                     releaseURL:(NSURL *)releaseURL
                    downloadURL:(NSURL *)downloadURL {
    self = [super init];
    if (!self) return nil;

    _version = [version copy];
    _releaseURL = releaseURL;
    _downloadURL = downloadURL;
    return self;
}

@end

@implementation FLUpdater

+ (NSString *)normalizedVersion:(NSString *)version {
    NSString *value = [version stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([value hasPrefix:@"v"] || [value hasPrefix:@"V"])
        value = [value substringFromIndex:1];
    return value.length ? value : @"0";
}

+ (NSString *)currentAppVersion {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *version = info[@"CFBundleShortVersionString"];
    if (!version.length) version = info[@"CFBundleVersion"];
    return [self normalizedVersion:version ?: @"0"];
}

+ (NSComparisonResult)compareVersion:(NSString *)lhs to:(NSString *)rhs {
    NSString *left = [self normalizedVersion:lhs];
    NSString *right = [self normalizedVersion:rhs];
    return [left compare:right options:NSNumericSearch];
}

- (void)checkForUpdatesWithCompletion:(void(^)(FLReleaseInfo *info, BOOL hasUpdate, NSError *err))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:FLGitHubLatestReleaseAPIURL]];
    request.timeoutInterval = 15.0;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"FileLockApp/1.0.3" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        void (^finish)(FLReleaseInfo *, BOOL, NSError *) = ^(FLReleaseInfo *info, BOOL hasUpdate, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(info, hasUpdate, err);
            });
        };

        if (error) {
            finish(nil, NO, error);
            return;
        }

        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (![http isKindOfClass:NSHTTPURLResponse.class] || http.statusCode < 200 || http.statusCode >= 300) {
            NSError *statusError = [NSError errorWithDomain:@"com.filelock.update"
                                                       code:http.statusCode ?: -1
                                                   userInfo:@{NSLocalizedDescriptionKey: @"업데이트 서버 응답이 올바르지 않습니다."}];
            finish(nil, NO, statusError);
            return;
        }

        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (![json isKindOfClass:NSDictionary.class]) {
            NSError *parseError = jsonError ?: [NSError errorWithDomain:@"com.filelock.update"
                                                                   code:1
                                                               userInfo:@{NSLocalizedDescriptionKey: @"업데이트 정보를 해석하지 못했습니다."}];
            finish(nil, NO, parseError);
            return;
        }

        NSDictionary *release = json;
        NSString *tag = release[@"tag_name"];
        NSString *version = [FLUpdater normalizedVersion:tag ?: release[@"name"]];
        NSString *releaseURLString = release[@"html_url"];

        if (!version.length || !releaseURLString.length) {
            NSError *metaError = [NSError errorWithDomain:@"com.filelock.update"
                                                     code:2
                                                 userInfo:@{NSLocalizedDescriptionKey: @"업데이트 정보가 불완전합니다."}];
            finish(nil, NO, metaError);
            return;
        }

        NSURL *releaseURL = [NSURL URLWithString:releaseURLString];
        NSURL *downloadURL = nil;
        for (NSDictionary *asset in release[@"assets"]) {
            NSString *name = asset[@"name"];
            NSString *browserURL = asset[@"browser_download_url"];
            if ([name.pathExtension.lowercaseString isEqualToString:@"dmg"] && browserURL.length) {
                downloadURL = [NSURL URLWithString:browserURL];
                break;
            }
        }
        if (!downloadURL) downloadURL = releaseURL;

        FLReleaseInfo *info = [[FLReleaseInfo alloc] initWithVersion:version
                                                          releaseURL:releaseURL
                                                         downloadURL:downloadURL];
        BOOL hasUpdate = ([FLUpdater compareVersion:version to:[FLUpdater currentAppVersion]] == NSOrderedDescending);
        finish(info, hasUpdate, nil);
    }];

    [task resume];
}

@end
