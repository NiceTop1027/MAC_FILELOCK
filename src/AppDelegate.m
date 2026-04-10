#import "Vault.h"
#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate {
    NSWindow *_win;
    NSTextField *_statusLabel;
    NSMutableArray<NSURL *> *_pendingOpenURLs;
    BOOL _didFinishLaunching;
    NSString *_currentAdminPassword;
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    if (!_pendingOpenURLs) _pendingOpenURLs = [NSMutableArray new];
    _didFinishLaunching = YES;

    [self buildMenu];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSImage *appIcon = [NSImage imageNamed:@"FileLock"];
    if (!appIcon) appIcon = [NSImage imageNamed:@"FileLock-mark"];
    if (appIcon) [NSApp setApplicationIconImage:appIcon];

    if (_pendingOpenURLs.count == 0) {
        [self showMainWindow];
        [NSApp activateIgnoringOtherApps:YES];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
        [self flushPendingOpenURLs];
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag {
    [self showMainWindow];
    [NSApp activateIgnoringOtherApps:YES];
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    [[Vault shared] cleanup];
    return NSTerminateNow;
}

- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename {
    [self handleIncomingURLs:@[[NSURL fileURLWithPath:filename]]];
    return YES;
}

- (void)application:(NSApplication *)app openFiles:(NSArray<NSString *> *)filenames {
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:filenames.count];
    for (NSString *name in filenames)
        [urls addObject:[NSURL fileURLWithPath:name]];
    [self handleIncomingURLs:urls];
    [app replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)buildMenu {
    NSMenu *bar = [NSMenu new];

    NSMenuItem *appItem = [bar addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"FileLock"];
    [appMenu addItemWithTitle:@"FileLock 정보"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"FileLock 종료"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *fileItem = [bar addItemWithTitle:@"파일" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"파일"];
    [fileMenu addItemWithTitle:@"파일 잠그기…"
                        action:@selector(lockFiles:)
                 keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"잠긴 파일 열기…"
                        action:@selector(openLockedFiles:)
                 keyEquivalent:@"l"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"관리자 완전 해제…"
                        action:@selector(adminUnlockFiles:)
                 keyEquivalent:@""];
    fileItem.submenu = fileMenu;

    NSApp.mainMenu = bar;
}

- (void)showMainWindow {
    if (!_win) [self buildWindow];
    [_win center];
    [_win makeKeyAndOrderFront:nil];
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 700, 400);
    _win = [[NSWindow alloc] initWithContentRect:frame
                                       styleMask:NSWindowStyleMaskTitled |
                                                 NSWindowStyleMaskClosable |
                                                 NSWindowStyleMaskMiniaturizable
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
    _win.title = @"FileLock";
    _win.titlebarAppearsTransparent = YES;
    _win.movableByWindowBackground = YES;

    NSVisualEffectView *vev = [[NSVisualEffectView alloc] initWithFrame:_win.contentView.bounds];
    vev.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vev.material = NSVisualEffectMaterialSidebar;
    vev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vev.state = NSVisualEffectStateActive;
    [_win.contentView addSubview:vev];

    CGFloat W = frame.size.width;
    CGFloat H = frame.size.height;

    NSImage *brandImage = [NSImage imageNamed:@"FileLock-mark"];
    if (brandImage) {
        NSImageView *logo = [[NSImageView alloc] initWithFrame:NSMakeRect(40, H - 130, 72, 72)];
        logo.image = brandImage;
        logo.imageScaling = NSImageScaleProportionallyUpOrDown;
        [vev addSubview:logo];
    }

    NSTextField *title = [NSTextField labelWithString:@"FileLock"];
    title.font = [NSFont boldSystemFontOfSize:28];
    title.frame = NSMakeRect(128, H - 82, 220, 34);
    [vev addSubview:title];

    NSTextField *subtitle = [NSTextField labelWithString:@"Finder에서 바로 여는 .lock 보호 파일"];
    subtitle.font = [NSFont systemFontOfSize:14];
    subtitle.textColor = NSColor.secondaryLabelColor;
    subtitle.frame = NSMakeRect(128, H - 110, 360, 20);
    [vev addSubview:subtitle];

    NSTextField *body = [NSTextField labelWithString:
                         @"파일을 잠그면 원본은 휴지통으로 이동되고, 같은 자리에 보호 파일이 생성됩니다.\nFinder에서는 확장자가 숨겨져 원래 이름처럼 보이며, 이름 변경이나 삭제도 막아둡니다."];
    body.font = [NSFont systemFontOfSize:13];
    body.textColor = NSColor.secondaryLabelColor;
    body.frame = NSMakeRect(128, H - 188, W - 168, 52);
    body.lineBreakMode = NSLineBreakByWordWrapping;
    [vev addSubview:body];

    NSButton *lockBtn = [NSButton buttonWithTitle:@"파일 잠그기…"
                                           target:self
                                           action:@selector(lockFiles:)];
    lockBtn.bezelStyle = NSBezelStyleRounded;
    lockBtn.frame = NSMakeRect(40, 112, 180, 40);
    [vev addSubview:lockBtn];

    NSButton *openBtn = [NSButton buttonWithTitle:@"잠긴 파일 열기…"
                                           target:self
                                           action:@selector(openLockedFiles:)];
    openBtn.bezelStyle = NSBezelStyleRounded;
    openBtn.frame = NSMakeRect(232, 112, 180, 40);
    [vev addSubview:openBtn];

    NSButton *adminBtn = [NSButton buttonWithTitle:@"관리자 완전 해제…"
                                            target:self
                                            action:@selector(adminUnlockFiles:)];
    adminBtn.bezelStyle = NSBezelStyleRounded;
    adminBtn.frame = NSMakeRect(424, 112, 190, 40);
    [vev addSubview:adminBtn];

    NSTextField *tip = [NSTextField labelWithString:
                        @"일반 txt/png/mp4 자체의 모든 접근을 macOS 일반 앱이 가로채는 것은 불가능합니다. 대신 잠긴 파일을 열 때는 항상 비밀번호가 뜨고, 영구 복원은 관리자 인증 뒤에만 가능합니다."];
    tip.font = [NSFont systemFontOfSize:12];
    tip.textColor = NSColor.tertiaryLabelColor;
    tip.frame = NSMakeRect(40, 62, W - 80, 34);
    tip.lineBreakMode = NSLineBreakByWordWrapping;
    [vev addSubview:tip];

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.font = [NSFont systemFontOfSize:12];
    _statusLabel.textColor = NSColor.secondaryLabelColor;
    _statusLabel.frame = NSMakeRect(40, 24, W - 80, 20);
    [vev addSubview:_statusLabel];
}

- (void)setStatusText:(NSString *)text {
    [_statusLabel setStringValue:(text ?: @"")];
}

- (void)flushPendingOpenURLs {
    if (_pendingOpenURLs.count == 0) return;
    NSArray<NSURL *> *urls = [_pendingOpenURLs copy];
    [_pendingOpenURLs removeAllObjects];
    [self processURLs:urls];
}

- (void)handleIncomingURLs:(NSArray<NSURL *> *)urls {
    if (!_pendingOpenURLs) _pendingOpenURLs = [NSMutableArray new];
    if (!_didFinishLaunching) {
        [_pendingOpenURLs addObjectsFromArray:urls];
        return;
    }
    [self processURLs:urls];
}

- (void)processURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return;

    NSMutableArray<NSURL *> *locked = [NSMutableArray new];
    NSMutableArray<NSURL *> *plain = [NSMutableArray new];

    for (NSURL *url in urls) {
        if ([[Vault shared] isLockedFileURL:url]) {
            [locked addObject:url];
        } else {
            [plain addObject:url];
        }
    }

    [NSApp activateIgnoringOtherApps:YES];

    if (plain.count > 0) [self lockURLs:plain];
    for (NSURL *url in locked) [self promptAndOpenLockedURL:url];
}

- (IBAction)lockFiles:(id)sender {
    [self showMainWindow];

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    panel.message = @"잠글 파일이나 폴더를 선택하세요. 원본은 휴지통으로 이동되고 같은 위치에 잠금 파일이 생성됩니다.";
    if ([panel runModal] != NSModalResponseOK || panel.URLs.count == 0) return;

    [self lockURLs:panel.URLs];
}

- (IBAction)openLockedFiles:(id)sender {
    [self showMainWindow];

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.message = @"열 잠금 파일을 선택하세요.";
    if ([panel runModal] != NSModalResponseOK || panel.URLs.count == 0) return;

    for (NSURL *url in panel.URLs) {
        if (![[Vault shared] isLockedFileURL:url]) {
            [self showError:[NSError errorWithDomain:@"com.filelock.ui"
                                                code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"선택한 항목 중 잠금 파일이 아닌 것이 있습니다."}]];
            return;
        }
    }

    for (NSURL *url in panel.URLs) [self promptAndOpenLockedURL:url];
}

- (IBAction)adminUnlockFiles:(id)sender {
    [self showMainWindow];

    if (![self authenticateAdmin]) return;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.message = @"완전히 복원할 잠금 파일을 선택하세요.";
    if ([panel runModal] != NSModalResponseOK || panel.URLs.count == 0) return;

    NSURL *lockURL = panel.URLs.firstObject;
    if (![[Vault shared] isLockedFileURL:lockURL]) {
        [self showError:[NSError errorWithDomain:@"com.filelock.ui"
                                            code:3
                                        userInfo:@{NSLocalizedDescriptionKey: @"선택한 항목은 잠금 파일이 아닙니다."}]];
        return;
    }

    [self setStatusText:[NSString stringWithFormat:@"'%@' 완전 복원 중…", lockURL.lastPathComponent]];
    [[Vault shared] permanentlyUnlockLockedFileAtURL:lockURL adminPassword:_currentAdminPassword completion:^(NSURL *restoredURL, NSError *err) {
        if (err) {
            [self showError:err];
            [self setStatusText:@""];
            return;
        }

        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[restoredURL]];
        [self setStatusText:[NSString stringWithFormat:@"'%@' 완전 복원 완료", restoredURL.lastPathComponent]];
    }];
}

- (void)lockURLs:(NSArray<NSURL *> *)urls {
    NSMutableArray<NSURL *> *targets = [NSMutableArray new];
    for (NSURL *url in urls) {
        if (![[Vault shared] isLockedFileURL:url]) [targets addObject:url];
    }

    if (targets.count == 0) {
        [self showError:[NSError errorWithDomain:@"com.filelock.ui"
                                            code:2
                                        userInfo:@{NSLocalizedDescriptionKey: @"잠글 수 있는 일반 파일이 없습니다."}]];
        return;
    }

    NSString *pw = [self askPassword:@"비밀번호 설정"
                             message:[NSString stringWithFormat:@"%lu개 항목을 잠급니다.\n원본은 휴지통으로 이동되고, 같은 위치에 잠금 파일이 생성됩니다.", targets.count]
                             confirm:YES];
    if (!pw) return;

    [self setStatusText:@"잠금 파일 생성 중…"];

    __block NSUInteger completed = 0;
    __block NSUInteger failed = 0;
    NSMutableArray<NSURL *> *created = [NSMutableArray new];

    for (NSURL *url in targets) {
        [[Vault shared] lockURL:url password:pw completion:^(NSURL *lockURL, NSError *err) {
            completed++;
            if (lockURL) [created addObject:lockURL];
            if (err) failed++;

            if (completed == targets.count) {
                if (created.count > 0)
                    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:created];

                if (failed > 0) {
                    [self setStatusText:[NSString stringWithFormat:@"%lu개 잠금 완료, %lu개 실패", created.count, failed]];
                } else {
                    [self setStatusText:[NSString stringWithFormat:@"%lu개 잠금 완료", created.count]];
                }
            }

            if (err) [self showError:err];
        }];
    }
}

- (void)promptAndOpenLockedURL:(NSURL *)lockURL {
    NSString *displayName = [[lockURL.path lastPathComponent] stringByDeletingPathExtension];
    NSString *pw = [self askPassword:@"잠긴 파일 열기"
                             message:[NSString stringWithFormat:@"'%@'\n비밀번호를 입력하세요.", displayName.length ? displayName : lockURL.lastPathComponent]
                             confirm:NO];
    if (!pw) return;

    [self setStatusText:[NSString stringWithFormat:@"'%@' 복호화 중…", displayName.length ? displayName : lockURL.lastPathComponent]];
    [[Vault shared] openLockedFileAtURL:lockURL password:pw completion:^(NSURL *openedURL, NSError *err) {
        if (err) {
            [self showError:err];
            [self setStatusText:@""];
            return;
        }

        [[NSWorkspace sharedWorkspace] openURL:openedURL];
        [self setStatusText:[NSString stringWithFormat:@"'%@' 열림", openedURL.lastPathComponent]];
    }];
}

- (BOOL)authenticateAdmin {
    if (_currentAdminPassword.length > 0 && FLAdminPasswordMatches(_currentAdminPassword))
        return YES;

    NSString *pw = [self askPassword:@"관리자 인증"
                             message:@"관리자 전용 완전 해제 기능입니다.\n관리자 비밀번호를 입력하세요."
                             confirm:NO];
    if (!pw) return NO;

    if (!FLAdminPasswordMatches(pw)) {
        [self showError:[NSError errorWithDomain:@"com.filelock.admin"
                                            code:1
                                        userInfo:@{NSLocalizedDescriptionKey: @"관리자 비밀번호가 올바르지 않습니다."}]];
        return NO;
    }
    _currentAdminPassword = [pw copy];
    return YES;
}

- (NSString *)askPassword:(NSString *)title message:(NSString *)msg confirm:(BOOL)confirm {
    while (YES) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = title;
        alert.informativeText = msg;
        [alert addButtonWithTitle:@"확인"];
        [alert addButtonWithTitle:@"취소"];
        alert.alertStyle = NSAlertStyleInformational;

        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, confirm ? 56 : 28)];

        NSSecureTextField *pw1 = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, confirm ? 30 : 0, 280, 24)];
        pw1.placeholderString = @"비밀번호";
        [box addSubview:pw1];

        NSSecureTextField *pw2 = nil;
        if (confirm) {
            pw2 = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
            pw2.placeholderString = @"비밀번호 확인";
            [box addSubview:pw2];
        }

        alert.accessoryView = box;
        [alert layout];
        [alert.window makeFirstResponder:pw1];

        if ([alert runModal] != NSAlertFirstButtonReturn) return nil;

        NSString *password = pw1.stringValue;
        if (password.length < 1) continue;
        if (confirm && ![password isEqualToString:pw2.stringValue]) {
            NSAlert *error = [NSAlert new];
            error.messageText = @"비밀번호가 일치하지 않습니다.";
            [error runModal];
            continue;
        }
        return password;
    }
}

- (void)showError:(NSError *)err {
    [[NSAlert alertWithError:err] runModal];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
