// RNA-Album v2
// 目标: 交管12123 一键挪车拍照界面 (系统 UIImagePickerController camera 模式)
// 思路: hook 系统类，叠加相册按钮；选图后冒充系统相机回调 App 的 delegate
// 不触碰任何上传/校验逻辑

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

#define RNA_BTN_TAG   0x52A2
#define RNA_ALBUM_KEY "rna_album_helper"

#define RNA_LOG(fmt, ...) NSLog(@"[RNA-Album] " fmt, ##__VA_ARGS__)

#pragma mark - 选图助手

@interface RNAAlbumHelper : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, weak) UIImagePickerController *host;
@end

@implementation RNAAlbumHelper

- (void)picker:(PHPickerViewController *)pk
    didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14)) {
    [pk dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) {
        RNA_LOG(@"用户取消选择");
        return;
    }

    PHPickerResult *r = results.firstObject;
    if (![r.itemProvider canLoadObjectOfClass:[UIImage class]]) {
        RNA_LOG(@"itemProvider 不支持 UIImage");
        return;
    }

    __weak __typeof__(self) weakSelf = self;
    [r.itemProvider loadObjectOfClass:[UIImage class]
                    completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([obj isKindOfClass:[UIImage class]]) {
                [weakSelf deliver:(UIImage *)obj];
            } else {
                RNA_LOG(@"加载图片失败: %@", err.localizedDescription);
            }
        });
    }];
}

// 冒充系统相机，交给 App 自己的 delegate
- (void)deliver:(UIImage *)img {
    UIImagePickerController *p = self.host;
    if (!img || !p) {
        RNA_LOG(@"回传失败 img=%p host=%p", img, p);
        return;
    }

    NSDictionary *info = @{
        UIImagePickerControllerOriginalImage : img,
        UIImagePickerControllerMediaType     : @"public.image",
    };

    id<UIImagePickerControllerDelegate> d = p.delegate;
    SEL sel = @selector(imagePickerController:didFinishPickingMediaWithInfo:);

    RNA_LOG(@"回传相册图 %.0fx%.0f -> delegate=%@",
            img.size.width, img.size.height, NSStringFromClass([d class]));

    if (d && [d respondsToSelector:sel]) {
        [d imagePickerController:p didFinishPickingMediaWithInfo:info];
    } else {
        RNA_LOG(@"delegate 不响应拍照回调，尝试直接关闭");
    }

    // App 若未自行关闭，兜底关掉，避免卡在相机页
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (p.presentingViewController || p.presentedViewController) {
            [p dismissViewControllerAnimated:YES completion:nil];
        }
    });
}

@end

#pragma mark - 按钮

static void RNAInstallAlbumButton(UIImagePickerController *picker) {
    if (!picker || !picker.isViewLoaded) return;
    if (picker.sourceType != UIImagePickerControllerSourceTypeCamera) return;
    if ([picker.view viewWithTag:RNA_BTN_TAG]) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = RNA_BTN_TAG;
    [btn setTitle:@"相册" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    btn.layer.cornerRadius = 21.0;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    btn.translatesAutoresizingMaskIntoConstraints = NO;

    [picker.view addSubview:btn];

    UILayoutGuide *g = picker.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [btn.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16.0],
        [btn.topAnchor      constraintEqualToAnchor:g.topAnchor      constant:14.0],
        [btn.widthAnchor    constraintEqualToConstant:66.0],
        [btn.heightAnchor   constraintEqualToConstant:42.0],
    ]];

    [btn addTarget:picker
            action:@selector(rna_tapAlbum:)
  forControlEvents:UIControlEventTouchUpInside];

    RNA_LOG(@"相册按钮已注入 (sourceType=%ld)", (long)picker.sourceType);
}

#pragma mark - Hook

%hook UIImagePickerController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
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
        RNA_LOG(@"打开系统相册选择器");
    } else {
        RNA_LOG(@"iOS 14 以下不支持 PHPicker");
    }
}

%end
