// RNA-Album v7
// v6 修复了相机打不开(移除 UIWindow)，但存在 hook 覆盖漏洞:
//   UIImagePickerController 自己实现了 viewDidAppear:，hook 父类 UIViewController 拦不到。
// v7: 直接 hook UIImagePickerController 的 viewWillAppear/viewDidAppear/viewDidLayoutSubviews
//     并保留 UIViewController 兜底；同时在 %ctor 落一个标记文件，便于确认加载。

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

#define RNA_BTN_TAG   0x52A7
#define RNA_ALBUM_KEY "rna_album_helper_v7"
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

static NSString *RNAMarkerPath(void) {
    return @"/var/mobile/Documents/rna_album_loaded.txt";
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
        if (gRNALines.count > 600) [gRNALines removeObjectAtIndex:0];

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

#pragma mark - 诊断

static NSString *RNABuildReport(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"=== RNA-Album v7 诊断 ===\n"];
    [s appendFormat:@"bundle : %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    [s appendFormat:@"iOS    : %@\n", [[UIDevice currentDevice] systemVersion]];
    [s appendFormat:@"日志   : %@\n", RNALogPath()];
    [s appendString:@"\n--- 见过的页面类 ---\n"];
    if (gRNASeen.count == 0) [s appendString:@"(无)\n"];
    else for (NSString *n in gRNASeen) [s appendFormat:@"%@\n", n];
    [s appendString:@"\n--- 日志尾部 ---\n"];
    NSInteger from = MAX(0, (NSInteger)gRNALines.count - 80);
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
    RNA_LOG(@"回传失败 host=%@", NSStringFromClass([host class]));
  } @catch (NSException *e) {
    RNA_LOG(@"回传异常: %@", e.reason);
  }
}

@end

#pragma mark - 按钮

static void RNAInstallAlbumButton(UIViewController *vc, const char *from) {
  @try {
    if (!vc || !vc.isViewLoaded) return;
    if ([vc.view viewWithTag:RNA_BTN_TAG]) return;

    // 仅对相机界面注入
    BOOL isCamera = [vc isKindOfClass:[UIImagePickerController class]] &&
        ((UIImagePickerController *)vc).sourceType == UIImagePickerControllerSourceTypeCamera;
    if (!isCamera) {
        NSString *n = NSStringFromClass([vc class]);
        if (!([n containsString:@"Camera"] || [n containsString:@"Capture"])) return;
    }

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

    RNA_LOG(@"★ 注入相册按钮 -> %@ (from %s)", NSStringFromClass([vc class]), from);
  } @catch (NSException *e) {
    RNA_LOG(@"注入异常: %@", e.reason);
  }
}

#pragma mark - 加载探针

%ctor {
    @autoreleasepool {
        RNALog(@"=== dylib 已载入 v7 (arm64) ===");
        RNALog(@"bundle=%@", [[NSBundle mainBundle] bundleIdentifier]);
        RNALog(@"进程=%@", [[NSProcessInfo processInfo] processName]);
        RNALog(@"iOS=%@", [[UIDevice currentDevice] systemVersion]);
        RNALog(@"日志=%@", RNALogPath());
        @try {
            NSString *m = [NSString stringWithFormat:@"v7 loaded at %@\n", [NSDate date]];
            [m writeToFile:RNAMarkerPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } @catch (__unused NSException *e) {}
    }
}

#pragma mark - Hook: UIImagePickerController 本体（关键）

%hook UIImagePickerController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    RNAInstallAlbumButton(self, "picker.viewWillAppear");
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RNAInstallAlbumButton(self, "picker.viewDidAppear");
    RNACopyReportIfNeeded(@"picker 出现");
}

- (void)viewDidLayoutSubviews {
    %orig;
    RNAInstallAlbumButton(self, "picker.viewDidLayoutSubviews");
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

#pragma mark - Hook: UIViewController 兜底

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        NSString *n = NSStringFromClass([self class]);
        if ([n containsString:@"Camera"] || [n containsString:@"Capture"] ||
            [n containsString:@"Take"]   || [n containsString:@"Picker"]) {
            if (!gRNASeen) gRNASeen = [NSMutableArray array];
            if (![gRNASeen containsObject:n]) {
                [gRNASeen addObject:n];
                RNA_LOG(@"页面出现: %@", n);
                RNACopyReportIfNeeded([@"页面:" stringByAppendingString:n]);
            }
        }
        RNAInstallAlbumButton(self, "vc.viewDidAppear");
    } @catch (__unused NSException *e) {}
}

%end
