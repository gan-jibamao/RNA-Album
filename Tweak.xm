// RNA-Album v8
// 策略: 不再猜具体类，覆盖所有可能的相机路径
//   1. UIImagePickerController (系统)
//   2. TZImagePickerController (第三方 SDK)
//   3. 任何类名含 Camera/Capture/Take/Shot/Picker 的 VC
//   4. 任何视图内嵌 AVCaptureVideoPreviewLayer 的 VC
// 全部走同一注入函数，幂等 tag 防重复。

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

#define RNA_BTN_TAG   0x52A8
#define RNA_ALBUM_KEY "rna_album_helper_v8"
#define RNA_LOG(fmt, ...) RNALog(fmt, ##__VA_ARGS__)

#pragma mark - 日志

static NSMutableArray<NSString *> *gRNALines = nil;
static NSMutableArray<NSString *> *gRNASeen  = nil;
static NSMutableSet   *gRNACopied = nil;
static NSMutableSet   *gRNAInjectLog = nil;

static NSString *RNALogPath(void) {
    static NSString *p = nil;
    if (p) return p;
    NSArray *cands = @[
        @"/var/mobile/Documents/rna_album.log",
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:@"rna_album.log"] ?: @"/tmp/rna_album.log",
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *c in cands) {
        NSString *dir = [c stringByDeletingLastPathComponent];
        if ([fm isWritableFileAtPath:dir]) { p = c; return p; }
    }
    p = @"/tmp/rna_album.log";
    return p;
}

static void RNAWriteFile(NSString *path, NSString *content, BOOL append) {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (!append || ![fm fileExistsAtPath:path]) {
            [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        [fh seekToEndOfFile];
        [fh writeData:[content dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (__unused NSException *e) {}
}

static void RNALog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSLog(@"[RNA-Album] %@", msg);

    @try {
        if (!gRNALines) gRNALines = [NSMutableArray array];
        NSString *line = [NSString stringWithFormat:@"%@ %@", [NSDate date], msg];
        [gRNALines addObject:line];
        if (gRNALines.count > 800) [gRNALines removeObjectAtIndex:0];
        RNAWriteFile(RNALogPath(), [line stringByAppendingString:@"\n"], YES);
    } @catch (__unused NSException *e) {}
}

#pragma mark - 诊断

static NSString *RNABuildReport(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"=== RNA-Album v8 诊断 ===\n"];
    [s appendFormat:@"bundle : %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    [s appendFormat:@"iOS    : %@\n", [[UIDevice currentDevice] systemVersion]];
    [s appendFormat:@"日志   : %@\n", RNALogPath()];
    [s appendString:@"\n--- 探测到的类 ---\n"];
    [s appendString:@"TZImagePickerController : "];
    [s appendString:(NSClassFromString(@"TZImagePickerController") ? @"存在" : @"不存在")];
    [s appendString:@"\nTZImagePickerController(相机) : "];
    [s appendString:(NSClassFromString(@"TZImagePickerController") ? @"-" : @"-")];
    [s appendString:@"\n\n--- 见过的页面类 ---\n"];
    if (gRNASeen.count == 0) [s appendString:@"(无)\n"];
    else for (NSString *n in gRNASeen) [s appendFormat:@"%@\n", n];
    [s appendString:@"\n--- 日志尾部 ---\n"];
    NSInteger from = MAX(0, (NSInteger)gRNALines.count - 100);
    for (NSInteger i = from; i < (NSInteger)gRNALines.count; i++)
        [s appendFormat:@"%@\n", gRNALines[i]];
    return s;
}

static void RNACopyReportIfNeeded(NSString *reason) {
    @try {
        if (!gRNACopied) gRNACopied = [NSMutableSet set];
        if ([gRNACopied containsObject:reason]) return;
        [gRNACopied addObject:reason];
        NSString *rep = RNABuildReport();
        [UIPasteboard generalPasteboard].string = rep;
        RNALog(@"诊断已复制到剪贴板 (触发: %@, %lu 字符)",
               reason, (unsigned long)rep.length);
    } @catch (__unused NSException *e) {}
}

#pragma mark - 选图助手

@interface RNAAlbumHelper : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, weak) UIViewController *host;
@end

@implementation RNAAlbumHelper

- (void)picker:(PHPickerViewController *)pk
    didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14)) {
    [pk dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) { RNA_LOG(@"用户取消选择"); return; }
    PHPickerResult *r = results.firstObject;
    if (![r.itemProvider canLoadObjectOfClass:[UIImage class]]) {
        RNA_LOG(@"itemProvider 不支持 UIImage"); return;
    }
    __weak __typeof__(self) weakSelf = self;
    [r.itemProvider loadObjectOfClass:[UIImage class]
                    completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([obj isKindOfClass:[UIImage class]]) [weakSelf deliver:(UIImage *)obj];
            else RNA_LOG(@"加载失败: %@", err.localizedDescription);
        });
    }];
}

- (void)deliver:(UIImage *)img {
  @try {
    UIViewController *host = self.host;
    if (!img || !host) { RNA_LOG(@"回传失败: 参数无效"); return; }

    // A. 系统 picker
    if ([host isKindOfClass:[UIImagePickerController class]]) {
        UIImagePickerController *p = (UIImagePickerController *)host;
        NSDictionary *info = @{
            UIImagePickerControllerOriginalImage : img,
            UIImagePickerControllerMediaType     : @"public.image",
        };
        id d = p.delegate;
        SEL sel = @selector(imagePickerController:didFinishPickingMediaWithInfo:);
        RNA_LOG(@"回传(A:picker) %.0fx%.0f delegate=%@",
                img.size.width, img.size.height, NSStringFromClass([d class]));
        if (d && [d respondsToSelector:sel]) {
            [d imagePickerController:p didFinishPickingMediaWithInfo:info];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [p dismissViewControllerAnimated:YES completion:nil];
        });
        return;
    }

    // B. TZImagePickerController: 有 didFinishPickingPhotosHandle
    SEL tzSel = NSSelectorFromString(@"didFinishPickingPhotosHandle");
    if ([host respondsToSelector:tzSel]) {
        RNA_LOG(@"回传(B:TZImagePicker) %.0fx%.0f", img.size.width, img.size.height);
        id (^handler)(NSArray *, BOOL, NSArray *, BOOL);
        @try {
            handler = [host valueForKey:@"didFinishPickingPhotosHandle"];
        } @catch (__unused NSException *e) {}
        if (handler) {
            handler(@[img], NO, @[], YES);
            [host dismissViewControllerAnimated:YES completion:nil];
            return;
        }
    }

    // C. takePhotoBlock
    id block = nil;
    @try { block = [host valueForKey:@"takePhotoBlock"]; } @catch (__unused NSException *e) {}
    if (block) {
        void (^cb)(UIImage *, UIImage *, NSDictionary *) =
            (void (^)(UIImage *, UIImage *, NSDictionary *))block;
        RNA_LOG(@"回传(C:block) %.0fx%.0f", img.size.width, img.size.height);
        cb(img, img, @{});
        [host dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    // D. 全都不匹配: 把图塞进剪贴板 + 记录类名，便于人工处理
    RNA_LOG(@"回传失败 host=%@，无匹配通道", NSStringFromClass([host class]));
    RNACopyReportIfNeeded(@"回传失败");
  } @catch (NSException *e) {
    RNA_LOG(@"回传异常: %@", e.reason);
  }
}

@end

#pragma mark - 判定与注入

static BOOL RNAHasCapturePreview(UIViewController *vc) {
    @try {
        // 每个 VC 实例只深扫一次，避免每次布局都遍历视图树
        static void *kScannedKey = &kScannedKey;
        if (objc_getAssociatedObject(vc, kScannedKey)) {
            return [objc_getAssociatedObject(vc, kScannedKey) boolValue];
        }
        BOOL result = NO;
        Class pv = NSClassFromString(@"AVCaptureVideoPreviewLayer");
        NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
        int guard = 0;
        while (stack.count && guard++ < 300) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            for (CALayer *l in v.layer.sublayers) {
                if (pv && [l isKindOfClass:pv]) { result = YES; break; }
            }
            if (result) break;
            for (UIView *sub in v.subviews) [stack addObject:sub];
        }
        objc_setAssociatedObject(vc, kScannedKey, @(result), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return result;
    } @catch (__unused NSException *e) {}
    return NO;
}

static BOOL RNALooksLikeCamera(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return NO;

    if ([vc isKindOfClass:[UIImagePickerController class]]) {
        return ((UIImagePickerController *)vc).sourceType
                == UIImagePickerControllerSourceTypeCamera;
    }

    NSString *n = NSStringFromClass([vc class]);
    if ([n containsString:@"TZImagePicker"] || [n containsString:@"Camera"] ||
        [n containsString:@"Capture"]      || [n containsString:@"Take"]   ||
        [n containsString:@"Shot"]         || [n containsString:@"Shoot"]) {
        return YES;
    }
    return RNAHasCapturePreview(vc);
}

static void RNAInstallAlbumButton(UIViewController *vc, const char *from) {
  @try {
    if (!RNALooksLikeCamera(vc)) return;
    if ([vc.view viewWithTag:RNA_BTN_TAG]) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = RNA_BTN_TAG;
    [btn setTitle:@"相册" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.62];
    btn.layer.cornerRadius = 21.0;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:btn];
    [vc.view bringSubviewToFront:btn];

    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [btn.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16.0],
        [btn.topAnchor      constraintEqualToAnchor:g.topAnchor      constant:56.0],
        [btn.widthAnchor    constraintEqualToConstant:66.0],
        [btn.heightAnchor   constraintEqualToConstant:42.0],
    ]];
    [btn addTarget:vc action:@selector(rna_tapAlbum:)
          forControlEvents:UIControlEventTouchUpInside];

    if (!gRNAInjectLog) gRNAInjectLog = [NSMutableSet set];
    NSString *key = [NSString stringWithFormat:@"%s|%@", from, NSStringFromClass([vc class])];
    if (![gRNAInjectLog containsObject:key]) {
        [gRNAInjectLog addObject:key];
        RNA_LOG(@"★ 注入相册按钮 -> %@  (from %s)",
                NSStringFromClass([vc class]), from);
    }
  } @catch (NSException *e) {
    RNA_LOG(@"注入异常(%s): %@", from, e.reason);
  }
}

#pragma mark - 加载探针

%ctor {
    @autoreleasepool {
        RNALog(@"=== dylib 已载入 v8 (arm64) ===");
        RNALog(@"bundle=%@", [[NSBundle mainBundle] bundleIdentifier]);
        RNALog(@"进程=%@", [[NSProcessInfo processInfo] processName]);
        RNALog(@"iOS=%@", [[UIDevice currentDevice] systemVersion]);
        RNALog(@"日志=%@", RNALogPath());
        RNALog(@"TZImagePickerController: %@",
               NSClassFromString(@"TZImagePickerController") ? @"存在" : @"不存在");
        RNALog(@"TmriCameraViewController: %@",
               NSClassFromString(@"TmriCameraViewController") ? @"存在" : @"不存在");

        NSString *mark = [NSString stringWithFormat:@"v8 loaded %@\nbundle=%@\nlog=%@\n",
                          [NSDate date], [[NSBundle mainBundle] bundleIdentifier], RNALogPath()];
        RNAWriteFile(@"/var/mobile/Documents/rna_album_loaded.txt", mark, NO);
    }
}

#pragma mark - Hook: 系统 picker

%hook UIImagePickerController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    RNAInstallAlbumButton(self, "picker.will");
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RNAInstallAlbumButton(self, "picker.did");
    RNACopyReportIfNeeded(@"picker 出现");
}

- (void)viewDidLayoutSubviews {
    %orig;
    RNAInstallAlbumButton(self, "picker.layout");
}

%new
- (void)rna_tapAlbum:(UIButton *)sender {
  @try {
    RNAAlbumHelper *h = [[RNAAlbumHelper alloc] init];
    h.host = self;
    objc_setAssociatedObject(self, RNA_ALBUM_KEY, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
        cfg.filter = PHPickerFilter.imagesFilter;
        cfg.selectionLimit = 1;
        PHPickerViewController *pk = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        pk.delegate = h;
        [self presentViewController:pk animated:YES completion:nil];
        RNA_LOG(@"打开相册(picker) host=%@", NSStringFromClass([self class]));
    }
  } @catch (NSException *e) {
    RNA_LOG(@"打开相册异常: %@", e.reason);
  }
}

%end

#pragma mark - Hook: 通用 VC

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        NSString *n = NSStringFromClass([self class]);
        BOOL interesting = [n containsString:@"Camera"] || [n containsString:@"Capture"] ||
                           [n containsString:@"Take"]   || [n containsString:@"Picker"] ||
                           [n containsString:@"Photo"]  || [n containsString:@"Shot"];
        if (interesting) {
            if (!gRNASeen) gRNASeen = [NSMutableArray array];
            if (![gRNASeen containsObject:n]) {
                [gRNASeen addObject:n];
                RNA_LOG(@"页面出现: %@", n);
                RNACopyReportIfNeeded([@"页面:" stringByAppendingString:n]);
            }
        }
        RNAInstallAlbumButton(self, "vc.did");
    } @catch (__unused NSException *e) {}
}

- (void)viewDidLayoutSubviews {
    %orig;
    // 已有按钮直接返回，避免重复遍历
    if ([self.view viewWithTag:RNA_BTN_TAG]) return;
    RNAInstallAlbumButton(self, "vc.layout");
}

%new
- (void)rna_tapAlbum:(UIButton *)sender {
  @try {
    RNAAlbumHelper *h = [[RNAAlbumHelper alloc] init];
    h.host = self;
    objc_setAssociatedObject(self, RNA_ALBUM_KEY, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
        cfg.filter = PHPickerFilter.imagesFilter;
        cfg.selectionLimit = 1;
        PHPickerViewController *pk = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        pk.delegate = h;
        [self presentViewController:pk animated:YES completion:nil];
        RNA_LOG(@"打开相册(通用) host=%@", NSStringFromClass([self class]));
    }
  } @catch (NSException *e) {
    RNA_LOG(@"打开相册异常: %@", e.reason);
  }
}

%end
