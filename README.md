# RNA-Album

交管 12123「一键挪车」拍照界面 —— 注入相册入口。

[![Build Tweak](https://github.com/gan-jibamao/RNA-Album/actions/workflows/build.yml/badge.svg)](https://github.com/gan-jibamao/RNA-Album/actions/workflows/build.yml)

---

## 这是什么

官方 App 的一键挪车拍照页只有实时快门，没有相册入口。本工程用 Theos tweak
在相机页叠加一个「相册」按钮，选完图后复用 App 自己的 `takePhotoBlock`
回传，**不修改任何上传接口、不改动业务逻辑**。

## 逆向依据

| 证据 | 位置 | 说明 |
|------|------|------|
| `CLFJs.appOperate.takePhoto` + `photoBase64` | 主二进制 @0x35e825f | H5 调原生拍照的桥 |
| 回调签名 `v32@?0@"UIImage"8@"UIImage"16@"NSDictionary"24` | 同上 | 3 参 block：压缩图 / 原图 / 附加字典 |
| `CLFJs.*` 全表 29 个方法 | @0x35e8180~0x35e85b3 | **只有 takePhoto，无任何相册方法** |
| `takePhotoBlock  T@?,C,N,V_takePhotoBlock` | @0x3972767 | 相机控制器的 copy block 属性 |
| `TmriCameraViewController`（32 方法，AVCapturePhotoCaptureDelegate） | class_ro @0x4082500 | 自绘 AVCapture 相机控制器 |
| `UIImagePickerControllerSourceType` 命中 0 次 | 全二进制 | 原版从未实现相册能力 |

结论：相册入口在原版里根本不存在，不是被隐藏。可插入点只有 `takePhotoBlock`。

## 结构

```
.
├── Tweak.xm                    # 主实现
├── Makefile                    # rootless / arm64 + arm64e
├── control                     # com.rna.album12123
├── RNAAlbum.plist              # 只作用于 com.tmri.12123
├── BUILD.md                    # 完整编译手册（六阶段）
└── .github/workflows/build.yml # CI：推送即编译出 deb
```

## 一键获取成品

**方式一：直接下 CI 产物**

推送后去 Actions 页面，最新一次 `Build Tweak` 运行底部
`Artifacts` → `deb-<sha>`，解压即得 `.deb`。

**方式二：打 tag 自动发布 Release**

```bash
git tag v1.0.0
git push origin v1.0.0
```

Release 页面会挂上 `com.rna.album12123_1.0.0_iphoneos-arm64.deb`。

**方式三：本地编译**

见 [BUILD.md](BUILD.md)，含环境准备、报错对照表、真机验收四道门禁。

## 安装

需要 rootless 越狱环境（Dopamine / palera1n rootless）。

```bash
scp packages/com.rna.album12123_*.deb root@DEVICE:/var/mobile/Documents/
ssh root@DEVICE "dpkg -i /var/mobile/Documents/com.rna.album12123_*.deb && killall -9 SpringBoard"
```

卸载回滚：

```bash
ssh root@DEVICE "dpkg -r com.rna.album12123 && killall -9 SpringBoard"
```

## 验收

挂日志：

```bash
idevicesyslog | grep --line-buffered "RNA-Album"
```

四道门禁：

| # | 操作 | 期望 |
|---|------|------|
| 1 | 进拍照页 | `相册按钮已注入 TmriCameraViewController`，屏上出现按钮 |
| 2 | 返回再进 | 仍一条注入日志，按钮不叠加 |
| 3 | 点「相册」 | `打开相册选择器`，弹出系统相册 |
| 4 | 选一张图 | `回传相册图 size=WxH`，App 走原上传流程不闪退 |

## 已知边界

**三参 block 的字典位是盲区。** 签名里那个 `NSDictionary` 需要什么键，
二进制无明文。当前传 `@{}`，若业务层校验来源可能被拦。
真机日志能确认，修法见 BUILD.md 阶段 D4。

**注入必然留痕。** 二进制中存在腾讯 Turing SDK 的检测特征：
`/Applications/Cydia.app`、`/Library/MobileSubstrate/MobileSubstrate.dylib`、
`cydia://`、`sileo://`、`/usr/lib/libsubstrate.dylib`、`frida`、`isJailbroken`。
注入后是否触发风控取决于服务端策略，无法预判，属手段本身的代价。

## License

仅供技术研究与学习交流。
