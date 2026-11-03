// RNA-Album v6
// 修复: v4/v5 创建了 UIWindowLevelStatusBar+200 的高层级窗口，抢走 keyWindow
//       导致 UIImagePickerController 无法 present，相机打不开。
// 本版: 完全移除 UIWindow，诊断改走剪贴板 + 文件日志，零 UI 侵入。

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

#define RNA_BTN_TAG   0x52A6
#define RNA_ALBUM_KEY "rna_album_helper_v6"
#define RNA_LOG(fmt, ...) RNALog(fmt, ##__VA_ARGS__)

#pragma mark - 日志

static NSMutableArray<NSString *> *gRNALines = nil;
static NSMutableArray<NSString *> *gRNASeen  = nil;
static NSMutableSet   *gRNACopied = nil;

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

static void RNALog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSLog(@"[RNA-Album] %@", msg);

    @try {
        if (!gRNALines) gRNALines = [NSMutableArray array];
        NSString *line = [NSString stringWithFormat:@"%@ %@", [NSDate date], msg];
        [gRNALines addObject:line];
        if (gRNALines.count > 500) [gRNALines removeObjectAtIndex:0];

        NSString *path = RNALogPath();
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            [fm createFileAtPath:path contents:nil attributes:nil];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 诊断报告

static NSString *RNABuildReport(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"=== RNA-Album v6 诊断 ===\n"];
    [s appendFormat:@"bundle : %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    [s appendFormat:@"iOS    : %@\n", [[UIDevice currentDevice] systemVersion]];
    [s appendFormat:@"日志   : %@\n", RNALogPath()];
    [s appendString:@"\n--- 模块加载 ---\n"];
    [s appendString:@"dylib 已载入 (arm64)\n"];
    [s appendString:@"\n--- 见过的页面类 ---\n"];
    if (gRNASeen.count == 0) {
        [s appendString:@"(无)\n"];
    } else {
        for (NSString *n in gRNASeen) [s appendFormat:@"%@\n", n];
    }
    [s appendString:@"\n--- 日志尾部 ---\n"];
    NSInteger from = MAX(0, (NSInteger)gRNALines.count - 80);
    for (NSInteger i = from; i < (NSInteger)gRNALines.count; i++) {
        [s appendFormat:@"%@\n", gRNALines[i]];
    }
    return s;
}

// 静默复制诊断到剪贴板 —— 不弹任何 UI
static void RNACopyReportIfNeeded(NSString *reason) {
    @try {
        if (!gRNACopied) gRNACopied = [NSMutableSet set];
        if ([gRNACopied containsObject:reason]) return;
        [gRNACopied addObject:reason];

        NSString *rep = RNABuildReport();
        [UIPasteboard generalPasteboard].string = rep;
        RNALog(@"诊断已复制到剪贴板 (触发: %@, %lu 字符)", reason, (unsigned long)rep.length);
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

    if ([host isKindOfClass:[UIImagePickerController class]]) {
        UIImagePickerController *p = (UIImagePickerController *)host;
        NSDictionary *info = @{
            UIImagePickerControllerOriginalImage : img,
            UIImagePickerControllerMediaType     : @"public.image",
        };
        id d = p.delegate;
        SEL sel = @selector(imagePickerController:didFinishPickingMediaWithInfo:);
        RNA_LOG(@"回传(picker) %.0fx%.0f delegate=%@",
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

    id block = nil;
    @try { block = [host valueForKey:@"takePhotoBlock"]; } @catch (__unused NSException *e) {}
    if (block) {
        void (^cb)(UIImage *, UIImage *, NSDictionary *) =
            (void (^)(UIImage *, UIImage *, NSDictionary *))block;
        RNA_LOG(@"回传(block) %.0fx%.0f", img.size.width, img.size.height);
        cb(img, img, @{});
        [host dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    RNA_LOG(@"回传失败 host=%@ 无匹配通道", NSStringFromClass([host class]));
  } @catch (NSException *e) {
    RNA_LOG(@"回传异常: %@", e.reason);
  }
}

@end

#pragma mark - 相册按钮

static BOOL RNALooksLikeCamera(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return NO;
    NSString *n = NSStringFromClass([vc class]);
    if ([n containsString:@"Camera"] || [n containsString:@"Capture"] ||
        [n containsString:@"Take"]   || [n containsString:@"Shot"]) {
        return YES;
    }
    if ([vc isKindOfClass:[UIImagePickerController class]]) {
        return ((UIImagePickerController *)vc).sourceType
                == UIImagePickerControllerSourceTypeCamera;
    }
    return NO;
}

static void RNAInstallAlbumButton(UIViewController *vc) {
  @try {
    if (!RNALooksLikeCamera(vc)) return;
    if ([vc.view viewWithTag:RNA_BTN_TAG]) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = RNA_BTN_TAG;
    [btn setTitle:@"相册" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    btn.layer.cornerRadius = 21.0;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:btn];

    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [btn.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16.0],
        [btn.topAnchor      constraintEqualToAnchor:g.topAnchor      constant:56.0],
        [btn.widthAnchor    constraintEqualToConstant:66.0],
        [btn.heightAnchor   constraintEqualToConstant:42.0],
    ]];
    [btn addTarget:vc action:@selector(rna_tapAlbum:)
          forControlEvents:UIControlEventTouchUpInside];
    RNA_LOG(@"★ 注入相册按钮 -> %@", NSStringFromClass([vc class]));
  } @catch (NSException *e) {
    RNA_LOG(@"注入按钮异常: %@", e.reason);
  }
}

#pragma mark - 加载探针（不创建任何窗口）

%ctor {
    @autoreleasepool {
        RNALog(@"=== dylib 已载入 v6 (arm64, 无窗口) ===");
        RNALog(@"bundle=%@", [[NSBundle mainBundle] bundleIdentifier]);
        RNALog(@"进程=%@", [[NSProcessInfo processInfo] processName]);
        RNALog(@"iOS=%@", [[UIDevice currentDevice] systemVersion]);
        RNALog(@"日志=%@", RNALogPath());
    }
}

#pragma mark - Hook

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        NSString *n = NSStringFromClass([self class]);

        BOOL interesting =
            [n containsString:@"Camera"] || [n containsString:@"Capture"] ||
            [n containsString:@"Photo"]  || [n containsString:@"Take"]    ||
            [n containsString:@"Picker"] || [n containsString:@"Scan"]    ||
            [n containsString:@"MoveCar"];

        if (interesting) {
            if (!gRNASeen) gRNASeen = [NSMutableArray array];
            if (![gRNASeen containsObject:n]) {
                [gRNASeen addObject:n];
                RNA_LOG(@"页面出现: %@", n);
                // 抓到一个疑似相机页 → 自动复制诊断，供直接粘贴
                RNACopyReportIfNeeded([@"页面:" stringByAppendingString:n]);
            }
        }
        RNAInstallAlbumButton(self);
    } @catch (__unused NSException *e) {}
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
        RNA_LOG(@"打开相册 host=%@", NSStringFromClass([self class]));
    }
  } @catch (NSException *e) {
    RNA_LOG(@"打开相册异常: %@", e.reason);
  }
}

%end
