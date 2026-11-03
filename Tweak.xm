// RNA-Album v3 诊断版
// 目的: 证明 tweak 是否加载 + 抓出真实的相机界面类
// 策略: 全局监听 UIViewController 出现, 记录类名; 对疑似相机界面注入按钮

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

#define RNA_BTN_TAG   0x52A3
#define RNA_ALBUM_KEY "rna_album_helper_v3"
#define RNA_LOG(fmt, ...) NSLog(@"[RNA-Album] " fmt, ##__VA_ARGS__)

#pragma mark - 加载探针
// %ctor 在 dylib 被 dyld 加载时立刻执行，这是 tweak 是否生效的铁证
%ctor {
    RNA_LOG(@"=== dylib 已载入 ===");
    RNA_LOG(@"bundleId = %@", [[NSBundle mainBundle] bundleIdentifier]);
    RNA_LOG(@"process  = %@", [[NSProcessInfo processInfo] processName]);
    RNA_LOG(@"iOS      = %@", [[UIDevice currentDevice] systemVersion]);
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
            if ([obj isKindOfClass:[UIImage class]]) {
                [weakSelf deliver:(UIImage *)obj];
            } else {
                RNA_LOG(@"加载失败: %@", err.localizedDescription);
            }
        });
    }];
}

- (void)deliver:(UIImage *)img {
    UIViewController *host = self.host;
    if (!img || !host) { RNA_LOG(@"回传失败"); return; }

    // 情况一: host 是 UIImagePickerController, 走系统 delegate
    if ([host isKindOfClass:[UIImagePickerController class]]) {
        UIImagePickerController *p = (UIImagePickerController *)host;
        NSDictionary *info = @{
            UIImagePickerControllerOriginalImage : img,
            UIImagePickerControllerMediaType     : @"public.image",
        };
        id<UIImagePickerControllerDelegate> d = p.delegate;
        SEL sel = @selector(imagePickerController:didFinishPickingMediaWithInfo:);
        RNA_LOG(@"回传(系统picker) %.0fx%.0f -> delegate=%@",
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

    // 情况二: 自绘相机, 找 takePhotoBlock
    id block = nil;
    @try { block = [host valueForKey:@"takePhotoBlock"]; } @catch (__unused NSException *e) {}
    if (block) {
        void (^cb)(UIImage *, UIImage *, NSDictionary *) =
            (void (^)(UIImage *, UIImage *, NSDictionary *))block;
        RNA_LOG(@"回传(自绘相机 block) %.0fx%.0f", img.size.width, img.size.height);
        cb(img, img, @{});
        [host dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    RNA_LOG(@"回传失败: host=%@ 既非 picker 也无 takePhotoBlock",
            NSStringFromClass([host class]));
}

@end

#pragma mark - 按钮注入

static BOOL RNALooksLikeCamera(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return NO;
    NSString *n = NSStringFromClass([vc class]);
    if ([n containsString:@"Camera"] || [n containsString:@"Capture"] ||
        [n containsString:@"Photo"]   || [n containsString:@"Take"]) {
        return YES;
    }
    if ([vc isKindOfClass:[UIImagePickerController class]]) {
        return ((UIImagePickerController *)vc).sourceType
                == UIImagePickerControllerSourceTypeCamera;
    }
    // 兜底: 视图里是否有 AVCapture 预览层
    for (CALayer *l in vc.view.layer.sublayers) {
        NSString *ln = NSStringFromClass([l class]);
        if ([ln containsString:@"Capture"] || [ln containsString:@"Preview"]) return YES;
    }
    return NO;
}

static void RNAInstallAlbumButton(UIViewController *vc) {
    if (!RNALooksLikeCamera(vc)) return;
    if ([vc.view viewWithTag:RNA_BTN_TAG]) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = RNA_BTN_TAG;
    [btn setTitle:@"相册" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    btn.layer.cornerRadius = 21.0;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:btn];

    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [btn.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16.0],
        [btn.topAnchor      constraintEqualToAnchor:g.topAnchor      constant:52.0],
        [btn.widthAnchor    constraintEqualToConstant:66.0],
        [btn.heightAnchor   constraintEqualToConstant:42.0],
    ]];
    [btn addTarget:vc action:@selector(rna_tapAlbum:)
  forControlEvents:UIControlEventTouchUpInside];

    RNA_LOG(@"★ 注入按钮 -> %@", NSStringFromClass([vc class]));
}

#pragma mark - 全局监听

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    Class c = [self class];
    NSString *n = NSStringFromClass(c);
    // 只记录疑似相机/图片相关，避免刷屏
    if ([n containsString:@"Camera"] || [n containsString:@"Capture"] ||
        [n containsString:@"Photo"]   || [n containsString:@"Take"]  ||
        [n containsString:@"Picker"]  || [n containsString:@"Scan"]  ||
        [n containsString:@"MoveCar"] || [n containsString:@"moveCar"]) {
        RNA_LOG(@"页面出现: %@", n);
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
        RNA_LOG(@"打开相册 (host=%@)", NSStringFromClass([self class]));
    }
}

%end
