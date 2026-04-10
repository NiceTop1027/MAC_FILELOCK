/**
 * make_icon.m — FileLock 앱 아이콘 생성기
 * clang -framework Cocoa -fobjc-arc make_icon.m -o make_icon && ./make_icon
 */
#import <Cocoa/Cocoa.h>

static NSColor *FLColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [NSColor colorWithCalibratedRed:r / 255.0
                                     green:g / 255.0
                                      blue:b / 255.0
                                     alpha:a];
}

static void FLFillRoundedRect(NSRect rect, CGFloat radius, NSArray<NSColor *> *colors, CGFloat angle) {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:colors];
    [gradient drawInBezierPath:path angle:angle];
}

static void renderToFile(CGFloat S, NSString *path) {
    NSBitmapImageRep *bmp = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
        pixelsWide:(NSInteger)S
        pixelsHigh:(NSInteger)S
        bitsPerSample:8
        samplesPerPixel:4
        hasAlpha:YES
        isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0
        bitsPerPixel:0];

    NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:bmp];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];

    NSRect canvas = NSMakeRect(0, 0, S, S);
    CGFloat cx = S * 0.5;

    // Background
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:canvas xRadius:S * 0.23 yRadius:S * 0.23];
    NSGradient *bgGradient = [[NSGradient alloc] initWithColors:@[
        FLColor(16, 28, 60, 1.0),
        FLColor(9, 24, 51, 1.0),
        FLColor(5, 17, 34, 1.0)
    ]];
    [bgGradient drawInBezierPath:bg angle:270];

    // Ambient glow
    NSBezierPath *glow = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(S * 0.18, S * 0.26, S * 0.64, S * 0.56)];
    NSGradient *glowGradient = [[NSGradient alloc] initWithColors:@[
        FLColor(30, 205, 198, 0.38),
        FLColor(30, 205, 198, 0.0)
    ]];
    [glowGradient drawInBezierPath:glow relativeCenterPosition:NSMakePoint(0, 0)];

    // Diagonal sheen
    NSBezierPath *sheen = [NSBezierPath bezierPath];
    [sheen moveToPoint:NSMakePoint(S * 0.08, S * 0.90)];
    [sheen curveToPoint:NSMakePoint(S * 0.92, S * 0.58)
          controlPoint1:NSMakePoint(S * 0.28, S * 1.04)
          controlPoint2:NSMakePoint(S * 0.66, S * 0.78)];
    [sheen lineToPoint:NSMakePoint(S * 0.92, S * 0.44)];
    [sheen curveToPoint:NSMakePoint(S * 0.10, S * 0.78)
          controlPoint1:NSMakePoint(S * 0.68, S * 0.58)
          controlPoint2:NSMakePoint(S * 0.34, S * 0.92)];
    [sheen closePath];
    [[FLColor(255, 255, 255, 0.05) colorWithAlphaComponent:0.05] setFill];
    [sheen fill];

    // File page shadow
    NSRect pageRect = NSMakeRect(S * 0.23, S * 0.18, S * 0.52, S * 0.62);
    [NSGraphicsContext saveGraphicsState];
    NSShadow *pageShadow = [NSShadow new];
    pageShadow.shadowColor = [FLColor(0, 0, 0, 0.30) colorWithAlphaComponent:0.30];
    pageShadow.shadowOffset = NSMakeSize(0, -S * 0.020);
    pageShadow.shadowBlurRadius = S * 0.050;
    [pageShadow set];
    [[[NSBezierPath bezierPathWithRoundedRect:pageRect xRadius:S * 0.065 yRadius:S * 0.065] copy] fill];
    [NSGraphicsContext restoreGraphicsState];

    // File page
    NSBezierPath *page = [NSBezierPath bezierPathWithRoundedRect:pageRect xRadius:S * 0.065 yRadius:S * 0.065];
    NSGradient *pageGradient = [[NSGradient alloc] initWithColors:@[
        FLColor(249, 251, 255, 1.0),
        FLColor(228, 237, 255, 1.0),
        FLColor(211, 223, 247, 1.0)
    ]];
    [pageGradient drawInBezierPath:page angle:270];

    [[FLColor(130, 153, 194, 0.48) colorWithAlphaComponent:0.48] setStroke];
    page.lineWidth = S * 0.006;
    [page stroke];

    // Folded corner
    CGFloat fold = S * 0.125;
    NSBezierPath *foldPath = [NSBezierPath bezierPath];
    NSPoint p1 = NSMakePoint(NSMaxX(pageRect) - fold, NSMaxY(pageRect));
    NSPoint p2 = NSMakePoint(NSMaxX(pageRect), NSMaxY(pageRect));
    NSPoint p3 = NSMakePoint(NSMaxX(pageRect), NSMaxY(pageRect) - fold);
    [foldPath moveToPoint:p1];
    [foldPath lineToPoint:p2];
    [foldPath lineToPoint:p3];
    [foldPath closePath];
    NSGradient *foldGradient = [[NSGradient alloc] initWithColors:@[
        FLColor(255, 255, 255, 0.95),
        FLColor(207, 220, 247, 1.0)
    ]];
    [foldGradient drawInBezierPath:foldPath angle:315];

    [[FLColor(153, 175, 214, 0.70) colorWithAlphaComponent:0.70] setStroke];
    NSBezierPath *foldEdge = [NSBezierPath bezierPath];
    [foldEdge moveToPoint:p1];
    [foldEdge lineToPoint:p3];
    foldEdge.lineWidth = S * 0.006;
    [foldEdge stroke];

    // Accent rail
    NSRect railRect = NSMakeRect(NSMinX(pageRect) + S * 0.045, NSMinY(pageRect) + S * 0.060, S * 0.048, S * 0.46);
    FLFillRoundedRect(railRect, S * 0.024, @[
        FLColor(38, 212, 201, 1.0),
        FLColor(16, 151, 188, 1.0)
    ], 270);

    NSRect chipRect = NSMakeRect(NSMinX(pageRect) + S * 0.135, NSMaxY(pageRect) - S * 0.118, S * 0.22, S * 0.032);
    FLFillRoundedRect(chipRect, S * 0.016, @[
        FLColor(215, 226, 248, 1.0),
        FLColor(196, 211, 239, 1.0)
    ], 270);

    // Lock shackle
    CGFloat shackleRadius = S * 0.092;
    CGFloat shackleThickness = S * 0.050;
    CGFloat shackleCenterY = NSMinY(pageRect) + S * 0.34;
    NSBezierPath *shackle = [NSBezierPath bezierPath];
    [shackle moveToPoint:NSMakePoint(cx + shackleRadius, shackleCenterY - S * 0.070)];
    [shackle appendBezierPathWithArcWithCenter:NSMakePoint(cx, shackleCenterY)
                                        radius:shackleRadius
                                    startAngle:0
                                      endAngle:180
                                     clockwise:NO];
    [shackle lineToPoint:NSMakePoint(cx - shackleRadius, shackleCenterY - S * 0.070)];
    shackle.lineWidth = shackleThickness;
    shackle.lineCapStyle = NSLineCapStyleRound;
    shackle.lineJoinStyle = NSLineJoinStyleRound;

    [NSGraphicsContext saveGraphicsState];
    NSShadow *shackleShadow = [NSShadow new];
    shackleShadow.shadowColor = [FLColor(0, 0, 0, 0.22) colorWithAlphaComponent:0.22];
    shackleShadow.shadowOffset = NSMakeSize(0, -S * 0.008);
    shackleShadow.shadowBlurRadius = S * 0.020;
    [shackleShadow set];
    [[FLColor(189, 252, 244, 1.0) colorWithAlphaComponent:1.0] setStroke];
    [shackle stroke];
    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath *shackleHighlight = [NSBezierPath bezierPath];
    [shackleHighlight appendBezierPathWithArcWithCenter:NSMakePoint(cx, shackleCenterY)
                                                 radius:shackleRadius - shackleThickness * 0.34
                                             startAngle:26
                                               endAngle:154
                                              clockwise:NO];
    shackleHighlight.lineWidth = shackleThickness * 0.26;
    shackleHighlight.lineCapStyle = NSLineCapStyleRound;
    [[FLColor(255, 255, 255, 0.65) colorWithAlphaComponent:0.65] setStroke];
    [shackleHighlight stroke];

    // Lock body
    NSRect bodyRect = NSMakeRect(S * 0.335, S * 0.265, S * 0.31, S * 0.24);
    [NSGraphicsContext saveGraphicsState];
    NSShadow *lockShadow = [NSShadow new];
    lockShadow.shadowColor = [FLColor(0, 0, 0, 0.30) colorWithAlphaComponent:0.30];
    lockShadow.shadowOffset = NSMakeSize(0, -S * 0.014);
    lockShadow.shadowBlurRadius = S * 0.035;
    [lockShadow set];
    [[[NSBezierPath bezierPathWithRoundedRect:bodyRect xRadius:S * 0.060 yRadius:S * 0.060] copy] fill];
    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath *lockBody = [NSBezierPath bezierPathWithRoundedRect:bodyRect xRadius:S * 0.060 yRadius:S * 0.060];
    NSGradient *lockGradient = [[NSGradient alloc] initWithColors:@[
        FLColor(28, 53, 124, 1.0),
        FLColor(12, 28, 78, 1.0)
    ]];
    [lockGradient drawInBezierPath:lockBody angle:270];

    [[FLColor(78, 114, 191, 0.55) colorWithAlphaComponent:0.55] setStroke];
    lockBody.lineWidth = S * 0.006;
    [lockBody stroke];

    NSRect glossRect = NSMakeRect(NSMinX(bodyRect) + S * 0.030, NSMaxY(bodyRect) - S * 0.060, NSWidth(bodyRect) - S * 0.060, S * 0.036);
    FLFillRoundedRect(glossRect, S * 0.018, @[
        FLColor(255, 255, 255, 0.18),
        FLColor(255, 255, 255, 0.02)
    ], 270);

    // Keyhole
    CGFloat holeCX = cx;
    CGFloat holeCY = NSMinY(bodyRect) + NSHeight(bodyRect) * 0.55;
    CGFloat holeR = S * 0.034;
    NSBezierPath *holeCircle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(holeCX - holeR, holeCY - holeR, holeR * 2, holeR * 2)];
    [[FLColor(176, 245, 235, 0.95) colorWithAlphaComponent:0.95] setFill];
    [holeCircle fill];

    NSBezierPath *holeStem = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(holeCX - S * 0.018, holeCY - S * 0.086, S * 0.036, S * 0.084)
                                                             xRadius:S * 0.018
                                                             yRadius:S * 0.018];
    [holeStem fill];

    NSBezierPath *innerDot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(holeCX - S * 0.020, holeCY - S * 0.010, S * 0.040, S * 0.023)];
    [[FLColor(255, 255, 255, 0.35) colorWithAlphaComponent:0.35] setFill];
    [innerDot fill];

    [NSGraphicsContext restoreGraphicsState];

    NSData *png = [bmp representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:path atomically:YES];
    printf("  ✓ %4.0f×%4.0f  →  %s\n", S, S, path.lastPathComponent.UTF8String);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSString *iconset = @"assets/FileLock.iconset";
        [[NSFileManager defaultManager] createDirectoryAtPath:iconset
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        NSArray *specs = @[
            @[@16.0,   @"icon_16x16.png"],
            @[@32.0,   @"icon_16x16@2x.png"],
            @[@32.0,   @"icon_32x32.png"],
            @[@64.0,   @"icon_32x32@2x.png"],
            @[@128.0,  @"icon_128x128.png"],
            @[@256.0,  @"icon_128x128@2x.png"],
            @[@256.0,  @"icon_256x256.png"],
            @[@512.0,  @"icon_256x256@2x.png"],
            @[@512.0,  @"icon_512x512.png"],
            @[@1024.0, @"icon_512x512@2x.png"],
        ];

        printf("아이콘 렌더링 중...\n");
        for (NSArray *spec in specs) {
            NSString *target = [iconset stringByAppendingPathComponent:spec[1]];
            renderToFile([spec[0] floatValue], target);
        }
    }
    return 0;
}
