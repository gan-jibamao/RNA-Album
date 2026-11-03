// RNA-Album v4 诊断版
// 核心: 悬浮 RNA 按钮, 点一下把诊断信息复制到剪贴板, 直接粘贴即可

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

#define RNA_BTN_TAG   0x52A4
#define RNA_ALBUM_KEY "rna_album_helper_v4"
#define RNA_LOG(fmt, ...) RNALog(fmt, ##__VA_ARGS__)

#pragma mark - 日志与文件

static NSMutableArray<NSString *> *gRNALines = nil;
static NSMutableArray<NSString *> *gRNASeen  = nil;
static UIWindow *gRNAWindow = nil;

static NSString *RNALogPath(void) {
    static NSString *p = nil;
    if (p) return p;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *cands = [NSMutableArray array];
    [cands addObject:@"/var/mobile/Documents/rna_album.log"];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs) [cands addObject:[docs stringByAppendingPathComponent:@"rna_album.log"]];
    [cands addObject:[NSTemporaryDirectory() stringByAppendingPathComponent:@"rna_album.log"]];
    for (NSString *c in cands) {
        NSString *dir = [c stringByDeletingLastPathComponent];
        if ([fm isWritableFileAtPath:dir]) { p = c; break; }
    }
    if (!p) p = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rna_album.log"];
    return p;
}

static void RNALog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSLog(@"[RNA-Album] %@", msg);
    if (!gRNALines) gRNALines = [NSMutableArray array];
    NSString *line = [NSString stringWithFormat:@"%@ %@", [NSDate date], msg];
    [gRNALines addObject:line];
    if (gRNALines.count > 400) [gRNALines removeObjectAtIndex:0];

    @try {
        NSString *path = RNALogPath();
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        [fh seekToEndOfFile];
        [fh writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
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
    UIViewController *host = self.host;
    if (!img || !host) { RNA_LOG(@"回传失败"); return; }

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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
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
}

@end

#pragma mark - 诊断报告

static NSString *RNABuildReport(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"=== RNA-Album v4 诊断 ===\n"];
    [s appendFormat:@"bundle  : %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    [s appendFormat:@"iOS     : %@\n", [[UIDevice currentDevice] systemVersion]];
    [s appendFormat:@"日志文件: %@\n", RNALogPath()];
    [s appendString:@"\n--- 见过的页面类 ---\n"];
    if (gRNASeen.count == 0) [s appendString:@"(无)\n"];
    for (NSString *n in gRNASeen) [s appendFormat:@"%@\n", n];
    [s appendString:@"\n--- 日志尾部 ---\n"];
    NSInteger from = MAX(0, (NSInteger)gRNALines.count - 60);
    for (NSInteger i = from; i < (NSInteger)gRNALines.count; i++) {
        [s appendFormat:@"%@\n", gRNALines[i]];
    }
    return s;
}

static void RNAShowAlert(NSString *title, NSString *msg) {
    UIViewController *vc = gRNAWindow.rootViewController;
    if (!vc) return;
    if (vc.presentedViewController) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

#pragma mark - 悬浮窗

static void RNAShowFloatingButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gRNAWindow) { gRNAWindow.hidden = NO; return; }

        UIWindow *w = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
                if (![sc isKindOfClass:[UIWindowScene class]]) continue;
                w = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)sc];
                break;
            }
        }
        if (!w) w = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        w.frame = CGRectMake(0, 0, 64, 40);
        w.windowLevel = UIWindowLevelStatusBar + 200;
        w.backgroundColor = [UIColor clearColor];
        w.rootViewController = [[UIViewController alloc] init];
        w.rootViewController.view.backgroundColor = [UIColor clearColor];
        w.hidden = NO;

        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(0, 0, 64, 40);
        [b setTitle:@"RNA" forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.backgroundColor = [UIColor colorWithRed:0.85 green:0.15 blue:0.15 alpha:0.85];
        b.layer.cornerRadius = 12.0;
        [b addTarget:w.rootViewController
              action:@selector(rna_tap)
    forControlEvents:UIControlEventTouchUpInside];
        [w.rootViewController.view addSubview:b];

        gRNAWindow = w;
        RNA_LOG(@"悬浮按钮已创建");
    });
}

// 通过关联方法处理点击
@interface UIViewController (RNADiagV4)
- (void)rna_tap;
@end

@implementation UIViewController (RNADiagV4)
- (void)rna_tap {
    NSString *rep = RNABuildReport();
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    [pb setString:rep];
    RNA_LOG(@"诊断已复制到剪贴板, 长度=%lu", (unsigned long)rep.length);
    RNAShowAlert(@"已复制到剪贴板",
                 [NSString stringWithFormat:@"打开聊天框长按粘贴发给我。\n\n共 %lu 字符\n日志: %@",
                  (unsigned long)rep.length, RNALogPath()]);
}
@end

#pragma mark - 相册按钮

static void RNAInstallAlbumButton(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return;
    if ([vc.view viewWithTag:RNA_BTN_TAG]) return;

    NSString *n = NSStringFromClass([vc class]);
    BOOL named = [n containsString:@"Camera"] || [n containsString:@"Capture"] ||
                 [n containsString:@"Take"]   || [n containsString:@"Photo"];
    BOOL isPicker = [vc isKindOfClass:[UIImagePickerController class]] &&
        ((UIImagePickerController *)vc).sourceType == UIImagePickerControllerSourceTypeCamera;
    if (!named && !isPicker) return;

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
    RNA_LOG(@"★ 注入相册按钮 -> %@", n);
}

#pragma mark - 加载探针

%ctor {
    RNALog(@"=== dylib 已载入 v4 ===");
    RNALog(@"bundle=%@", [[NSBundle mainBundle] bundleIdentifier]);
    RNALog(@"进程=%@", [[NSProcessInfo processInfo] processName]);
    RNALog(@"iOS=%@", [[UIDevice currentDevice] systemVersion]);
    RNALog(@"日志路径=%@", RNALogPath());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        RNAShowFloatingButton();
    });
}

#pragma mark - Hook

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *n = NSStringFromClass([self class]);

    if ([n containsString:@"Camera"] || [n containsString:@"Capture"] ||
        [n containsString:@"Photo"]  || [n containsString:@"Take"]    ||
        [n containsString:@"Picker"] || [n containsString:@"Scan"]    ||
        [n containsString:@"Web"]    || [n containsString:@"MoveCar"] ||
        [n containsString:@"moveCar"]) {
        if (!gRNASeen) gRNASeen = [NSMutableArray array];
        if (![gRNASeen containsObject:n]) {
            [gRNASeen addObject:n];
            RNA_LOG(@"页面出现: %@", n);
        }
    }
    RNAInstallAlbumButton(self);
}

%new
- (void)rna_tapAlbum:(UIButton *)sender {
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
}

%end

#pragma mark - 应用启动后建悬浮窗

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    RNAShowFloatingButton();
}
%end
