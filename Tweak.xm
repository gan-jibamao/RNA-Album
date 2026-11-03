// RNA-Album : 12123 相机界面注入「相册」入口
// 作用域: com.tmri.12123  /  TmriCameraViewController
// 复用 App 自己的 takePhotoBlock 回传，不触碰任何上传/校验逻辑

#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

#define RNA_BTN_TAG   0x52A1
#define RNA_LOG(fmt, ...) NSLog(@"[RNA-Album] " fmt, ##__VA_ARGS__)

static void *kRNAPickerKey = &kRNAPickerKey;

#pragma mark - 原类声明（属性来自二进制字符串表）

@interface TmriCameraViewController : UIViewController
// T@?,C,N,V_takePhotoBlock  —— copy block
@property (nonatomic, copy) id takePhotoBlock;
@end

#pragma mark - 相册选择代理

@interface RNAAlbumPicker : NSObject
    <PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, weak) UIViewController *host;
@end

@implementation RNAAlbumPicker

// 唯一的回传出口：对齐 v32@?0@"UIImage"8@"UIImage"16@"NSDictionary"24
- (void)deliverImage:(UIImage *)img {
    UIViewController *host = self.host;
    if (!img || !host) {
        RNA_LOG(@"deliver 失败: img=%p host=%p", img, host);
        return;
    }

    id block = nil;
    @try {
        block = [host valueForKey:@"takePhotoBlock"];
    } @catch (__unused NSException *e) {
        RNA_LOG(@"takePhotoBlock 取值异常: %@", e.reason);
    }

    if (!block) {
        RNA_LOG(@"takePhotoBlock 为空，无法回传（该页可能不是 TmriCamera）");
        return;
    }

    void (^cb)(UIImage *, UIImage *, NSDictionary *) =
        (void (^)(UIImage *, UIImage *, NSDictionary *))block;

    RNA_LOG(@"回传相册图 size=%.0fx%.0f", img.size.width, img.size.height);
    cb(img, img, @{});
}

#pragma mark PHPicker (iOS 14+)

- (void)picker:(PHPickerViewController *)picker
    didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    PHPickerResult *r = results.firstObject;
    if (![r.itemProvider canLoadObjectOfClass:[UIImage class]]) {
        RNA_LOG(@"itemProvider 不支持 UIImage");
        return;
    }

    __weak typeof(self) weakSelf = self;
    [r.itemProvider loadObjectOfClass:[UIImage class]
                    completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([obj isKindOfClass:[UIImage class]]) {
                [weakSelf deliverImage:(UIImage *)obj];
            } else {
                RNA_LOG(@"load 失败: %@", err.localizedDescription);
            }
        });
    }];
}

#pragma mark UIImagePicker (iOS 13 及以下)

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];
    [self deliverImage:img];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - 按钮注入

static void RNAInstallAlbumButton(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded) return;
    if ([vc.view viewWithTag:RNA_BTN_TAG]) return;   // 幂等

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.tag = RNA_BTN_TAG;
    [btn setTitle:@"相册" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    btn.layer.cornerRadius = 22.0;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    btn.translatesAutoresizingMaskIntoConstraints = NO;

    [vc.view addSubview:btn];

    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [btn.leadingAnchor  constraintEqualToAnchor:g.leadingAnchor constant:20.0],
        [btn.bottomAnchor   constraintEqualToAnchor:g.bottomAnchor  constant:-130.0],
        [btn.widthAnchor    constraintEqualToConstant:64.0],
        [btn.heightAnchor   constraintEqualToConstant:44.0],
    ]];

    [btn addTarget:vc action:@selector(rna_openAlbum:) forControlEvents:UIControlEventTouchUpInside];
    RNA_LOG(@"相册按钮已注入 %@", NSStringFromClass([vc class]));
}

#pragma mark - Hook

%hook TmriCameraViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    RNAInstallAlbumButton(self);
}

%new
- (void)rna_openAlbum:(UIButton *)sender {
    RNAAlbumPicker *p = [RNAAlbumPicker new];
    p.host = self;
    // 选择器代理必须强持有，否则 present 后立刻释放
    objc_setAssociatedObject(self, kRNAPickerKey, p, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
        cfg.filter = PHPickerFilter.imagesFilter;
        cfg.selectionLimit = 1;
        PHPickerViewController *pk = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        pk.delegate = p;
        [self presentViewController:pk animated:YES completion:nil];
    } else {
        UIImagePickerController *ip = [UIImagePickerController new];
        ip.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        ip.delegate = p;
        [self presentViewController:ip animated:YES completion:nil];
    }
    RNA_LOG(@"打开相册选择器");
}

%end
