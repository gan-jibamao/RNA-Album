# RNA-Album 编译手册
## 12123 相机相册入口 · Theos 从零到出 deb

版本 1.0 · 目标 `iphone:clang:latest:14.0` · `arm64 + arm64e` · rootless

---

## 阶段 A · 环境准备

### A1 · 确认你的编译主机

**① 位置**：你的电脑，不是手机
**② 现状**：iSH 里没有 Theos 工具链，无法在这里编译。必须换机器。
**③ 原因**：Theos 需要 clang + iOS SDK + ld64 + 打包工具链，iSH 的 Alpine aarch64 提供不了 iOS SDK。
**④ 三条可用路线**：

| 路线 | 主机要求 | 适用 | 难度 |
|------|---------|------|------|
| A | macOS + Xcode Command Line Tools | 最省事，官方支持 | ★ |
| B | macOS / Linux + Docker `theos/theos` | 无 Xcode 也行 | ★★ |
| C | 越狱设备上装 Theos（Procursus） | 无电脑，直接手机编 | ★★★ |

**⑤ 验收**：`which clang` 有输出，`xcode-select -p` 有路径（macOS）

---

### A2 · macOS 装 Xcode 命令行工具

**① 位置**：macOS 终端
**② 原本状态**：新机器通常没有
**③ 原因**：Theos 调 `xcrun --sdk iphoneos clang`，没有 CLT 就找不到 SDK
**④ 命令**：

```bash
xcode-select --install
# 弹窗点「安装」，等 5~15 分钟

# 验证
xcode-select -p
# 期望输出：/Library/Developer/CommandLineTools
# 或 /Applications/Xcode.app/Contents/Developer

clang --version
```

**⑤ 验收**：`xcrun --sdk iphoneos --show-sdk-path` 返回一个 .sdk 路径

---

### A3 · 安装 Theos

**① 位置**：你的家目录
**② 原本状态**：不存在 `~/theos`
**③ 原因**：Theos 是编译框架本体，提供 makefile 体系
**④ 命令**：

```bash
export THEOS=~/theos

git clone --recursive https://github.com/theos/theos.git $THEOS

# 写进 shell 配置，永久生效
echo 'export THEOS=~/theos' >> ~/.zshrc
echo 'export PATH=$THEOS/bin:$PATH' >> ~/.zshrc
source ~/.zshrc
```

**⑤ 验收**：

```bash
ls $THEOS/makefiles
# 应看到 common.mk  instance    package    tweak.mk 等
```

---

### A4 · 安装 iOS SDK

**① 位置**：`$THEOS/sdks/`
**② 原本状态**：`ls $THEOS/sdks` 是空的
**③ 原因**：Theos 不带 SDK，必须单独下。没有 SDK 会在链接阶段报 `ld: framework not found UIKit`
**④ 命令（二选一）**：

方式一 · 从 Xcode 拷（推荐，最稳）

```bash
# 先确认 Xcode 里有 iPhoneOS SDK
ls /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/
# 例如 iPhoneOS17.5.sdk

mkdir -p $THEOS/sdks
cp -R /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk \
      $THEOS/sdks/
```

方式二 · 用 theos/sdks 仓库

```bash
git clone --depth 1 https://github.com/theos/sdks.git /tmp/theos-sdks
cp -R /tmp/theos-sdks/iPhoneOS*.sdk $THEOS/sdks/
```

**⑤ 验收**：

```bash
ls $THEOS/sdks
# 至少一个 iPhoneOS*.sdk 目录
```

> **关键提醒**：本工程 `TARGET = iphone:clang:latest:14.0`，`latest` 会取 sdks 目录里最新的那个。系统版本号 `14.0` 是最低部署版本，不是 SDK 版本。二者别混。

---

### A5 · 安装打包依赖（dpkg / ldid）

**① 位置**：主机系统包
**② 原本状态**：macOS 没 dpkg，Linux 可能没 ldid
**③ 原因**：`make package` 要用 `dpkg-deb` 打 deb，`ldid` 给二进制签名，缺一个就断
**④ 命令**：

macOS（Homebrew）：

```bash
brew install dpkg ldid
```

Debian/Ubuntu：

```bash
sudo apt update
sudo apt install -y dpkg-dev fakeroot ldid
```

Arch：

```bash
sudo pacman -S dpkg ldid
```

**⑤ 验收**：

```bash
dpkg-deb --version | head -1
ldid -h 2>&1 | head -1
```

---

## 阶段 B · 工程编译

### B1 · 拉取工程文件

**① 位置**：`~/rna_albumtweak/`
**② 现状**：四个文件已在 iSH 的 `/var/minis/workspace/rna_albumtweak/`
**③ 原因**：要落到你的编译主机上
**④ 操作**：把整个目录拷到主机，或用下面命令补齐（若你手动建）

```bash
mkdir -p ~/rna_albumtweak && cd ~/rna_albumtweak
# 目录内必须有：Tweak.xm  Makefile  control  RNAAlbum.plist
```

**⑤ 验收**：

```bash
ls ~/rna_albumtweak
# Tweak.xm  Makefile  control  RNAAlbum.plist
```

---

### B2 · 核对 Makefile 四项

**① 位置**：`~/rna_albumtweak/Makefile`
**② 原本代码**：

```make
export TARGET = iphone:clang:latest:14.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

TWEAK_NAME = RNAAlbum
RNAAlbum_FILES = Tweak.xm
RNAAlbum_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
RNAAlbum_FRAMEWORKS = UIKit PhotosUI Photos
RNAAlbum_PRIVATE_FRAMEWORKS =

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 12123 || true"
```

**③ 逐项作用**：

| 行 | 作用 | 改错会怎样 |
|----|------|-----------|
| `TARGET ...:14.0` | 最低 iOS 14 | 设 12.0 会因 PHPicker 缺失报链接错误 |
| `ARCHS = arm64 arm64e` | 双架构 | 只留 arm64，A12+ 设备可能加载失败 |
| `THEOS_PACKAGE_SCHEME = rootless` | 走 `/var/jb` 布局 | 不写会装到根分区，Dopamine 上装不上 |
| `-fobjc-arc` | ARC 编译 | 去掉后 block 拷贝会泄漏、`weak` 失效 |
| `RNAAlbum_FRAMEWORKS` | 链接 PhotosUI | 缺 PhotosUI 报 `_OBJC_CLASS_$_PHPickerViewController` 未定义 |

**④ 若你的 SDK 版本较老**：把 `latest` 换成具体版本，例如

```make
export TARGET = iphone:clang:16.5:14.0
```

对应 `$THEOS/sdks/iPhoneOS16.5.sdk`

**⑤ 验收**：`make -n` 能跑完不报语法错

---

### B3 · 第一次编译

**① 位置**：工程根目录
**② 原本状态**：无产物
**③ 原因**：先编译不打包，报错时定位更快
**④ 命令**：

```bash
cd ~/rna_albumtweak

export THEOS=~/theos
make clean
make 2>&1 | tee /tmp/build.log
```

**⑤ 期望输出**：

```
Making all for tweak RNAAlbum...
 Compiling Tweak.xm (arm64)…
 Linking tweak RNAAlbum (arm64)…
 Compiling Tweak.xm (arm64e)…
 Linking tweak RNAAlbum (arm64e)…
 Stripping RNAAlbum…
 Signing RNAAlbum…
```

**产物位置**：`~/rna_albumtweak/.theos/obj/arm64/RNAAlbum.dylib`

**验收**：

```bash
file .theos/obj/arm64/RNAAlbum.dylib
# 期望：Mach-O 64-bit dynamically linked shared library arm64
```

---

### B4 · 打包

**① 位置**：工程根目录
**② 原本状态**：只有 obj
**③ 原因**：要生成可安装的 deb
**④ 命令**：

```bash
make package FINALPACKAGE=1
```

`FINALPACKAGE=1` 表示正式包（strip 符号，体积小）

**⑤ 期望输出**：

```
Making package for tweak RNAAlbum...
Packaging RNAAlbum...
dpkg-deb: building package 'com.rna.album12123' in 'packages/com.rna.album12123_1.0.0_iphoneos-arm64.deb'.
```

**验收**：

```bash
ls -lh packages/
# 期望：com.rna.album12123_1.0.0_iphoneos-arm64.deb  （约 20~50 KB）

# 检查包内结构
dpkg-deb -c packages/com.rna.album12123_*.deb
```

**包内应有三条路径**：

```
/var/jb/Library/MobileSubstrate/DynamicLibraries/RNAAlbum.dylib
/var/jb/Library/MobileSubstrate/DynamicLibraries/RNAAlbum.plist
```

> 若看到的是 `/Library/MobileSubstrate/...` 没有 `/var/jb` 前缀，说明 `THEOS_PACKAGE_SCHEME` 没生效。检查是不是在 Makefile 里写在了 `include` 之后。

---

## 阶段 C · 安装与验收

### C1 · 安装 deb

**① 位置**：越狱设备
**② 现状**：设备上没这个包
**③ 原因**：需要 rootless 越狱环境（Dopamine / palera1n rootless）
**④ 三种方式**：

方式一 · Filza

```
把 deb 传到设备（AirDrop / 微信文件传输 / scp）
Filza 打开 → 点击 deb → 安装
```

方式二 · Sileo / Zebra

```
Sileo → 来源 → 添加本地文件
或把 deb 放进 /var/mobile/Documents/ 后用 Sileo 的文件安装
```

方式三 · ssh（最可控）

```bash
scp packages/com.rna.album12123_*.deb root@<设备IP>:/var/mobile/Documents/

ssh root@<设备IP>
dpkg -i /var/mobile/Documents/com.rna.album12123_*.deb
killall -9 SpringBoard
```

**⑤ 验收**：

```bash
dpkg -l | grep album12123
# 期望：ii  com.rna.album12123  1.0.0
```

---

### C2 · 挂日志观察

**① 位置**：主机终端
**② 现状**：无日志输出
**③ 原因**：注入是否成功，只看图标看不出来
**④ 命令**：

```bash
# 有 libimobiledevice
idevicesyslog -u $(idevice_id -l | head -1) | grep --line-buffered "RNA-Album"

# 或直接 ssh 看
ssh root@<设备IP> "tail -f /var/log/syslog" | grep --line-buffered "RNA-Album"
```

**⑤ 期望**：打开 App 前无输出；进挪车拍照页后出现

```
[RNA-Album] 相册按钮已注入 TmriCameraViewController
```

---

### C3 · 真机操作验收（四条门禁）

**① 位置**：App 内「一键挪车 → 拍照」
**② 原本行为**：只有快门 + 退出
**③ 判定标准**：

| # | 操作 | 期望日志 | 通过条件 |
|---|------|---------|---------|
| 门禁 1 | 进入相机页 | `相册按钮已注入` | 屏幕左下出现「相册」胶囊按钮 |
| 门禁 2 | 返回再进 | 仍只有一条注入日志 | 按钮不重叠、不重复 |
| 门禁 3 | 点「相册」 | `打开相册选择器` | 弹出系统相册，可选图 |
| 门禁 4 | 选一张图 | `回传相册图 size=WxH` | App 走原上传流程，无闪退 |

**④ 若门禁 4 失败**，看下一行日志：

```
[RNA-Album] takePhotoBlock 为空，无法回传
```

说明当前页不是 `TmriCameraViewController`，或者属性名不对。回阶段 D1 排查。

**⑤ 验收**：四条全绿 = 改造成功

---

### C4 · 回滚

**① 位置**：设备
**② 原本状态**：已安装
**③ 原因**：任何异常要能立刻恢复原状
**④ 命令**：

```bash
ssh root@<设备IP>
dpkg -r com.rna.album12123
killall -9 SpringBoard
```

**⑤ 验收**：相机页恢复只有快门，`dpkg -l | grep album12123` 无输出

---

## 阶段 D · 报错对照表

### D1 · 编译期错误

| 报错原文 | 根因 | 修法 |
|---------|------|------|
| `'UIKit/UIKit.h' file not found` | SDK 没装或 TARGET 版本不对 | 回去做 A4；确认 `ls $THEOS/sdks` 有 `iPhoneOS*.sdk` |
| `ld: framework not found PhotosUI` | SDK 太老，无 PhotosUI | 换 iPhoneOS15.0+ 的 SDK；或把 `RNAAlbum_FRAMEWORKS` 里的 `PhotosUI` 去掉，改用 `Photos` + 运行时 `NSClassFromString(@"PHPickerViewController")` 软链接 |
| `error: use of undeclared identifier 'PHPickerViewController'` | 同上 | 同上；或加 `#import <PhotosUI/PhotosUI.h>` 已存在时，检查 SDK 版本 |
| `fatal error: 'objc/runtime.h' file not found` | 极罕见，SDK 不完整 | 重装 SDK |
| `ld: symbol(s) not found for architecture arm64e` | 某个 framework 无 arm64e slice | `export ARCHS = arm64` 先跑通，再单独处理 arm64e |
| `clang: error: unsupported option '-fobjc-arc'` | 用的不是 objc 编译单元 | 确认文件名后缀是 `.xm` 或 `.m`，不是 `.c` |
| `No such file or directory: /makefiles/common.mk` | `$THEOS` 没导出 | `export THEOS=~/theos`，且路径下有 `makefiles/` |
| `make: *** No rule to make target 'package'` | 少 include tweak.mk | 检查 Makefile 末尾两行 include 都在 |

### D2 · 链接期 / 签名期错误

| 报错原文 | 根因 | 修法 |
|---------|------|------|
| `ldid: command not found` | 没装 ldid | 做 A5 |
| `Signing RNAAlbum…` 卡住 | ldid 权限或版本问题 | `ldid -h` 验证；macOS 上 `brew reinstall ldid` |
| `error: linker command failed with exit code 1` | 往上翻 20 行找真正的 undefined symbol | 通常是 framework 缺失，补进 `RNAAlbum_FRAMEWORKS` |

### D3 · 运行期问题

| 现象 | 根因 | 修法 |
|------|------|------|
| 按钮完全没出现 | tweak 没加载 | ① `dpkg -l` 确认已装 ② 检查 dylib 是否在 `/var/jb/Library/MobileSubstrate/DynamicLibraries/` ③ 检查 plist 的 `Bundles` 是不是 `com.tmri.12123`（用 `plutil -p` 或直接看文件） |
| 按钮出现了但点不动 | 被上层视图挡住 | 把 `-130.0` 改成 `-180.0`，或改成 `[vc.view bringSubviewToFront:btn]` |
| 点相册闪退 | 代理被释放 | 确认 `objc_setAssociatedObject` 那行在；若被 ARC 优化掉，改成 `static NSMutableDictionary *kHold` 手动持有 |
| 选图后无反应，日志显示 `takePhotoBlock 为空` | 类名或属性名不匹配 | 用 FLEX 或 `class_getPropertyList` dump `TmriCameraViewController` 的真实属性名 |
| 选图后 App 提示「请拍摄现场照片」 | 服务端或前端校验了来源 | 见下方 D4 |
| App 一启动就闪退 | Turing SDK 检测到注入 | 见下方 D5 |
| 相册按钮重复叠加 | 幂等 tag 失效 | 确认 `RNA_BTN_TAG` 未被 App 占用；换个值如 `0x7E31` |

### D4 · 回传被业务层拦截

**现象**：日志有 `回传相册图 size=...`，但 App 提示需要现场拍摄、或提交失败。

**根因**：`takePhotoBlock` 第三参 `NSDictionary` 原为空，App 可能从里面取来源标记。

**排查步骤**：

```bash
# 1. 确认 block 三参里到底读了什么键
# 在 Tweak.xm 的 deliverImage: 里临时加：
NSLog(@"[RNA-Album] block=%@", block);
NSLog(@"[RNA-Album] blockSignature=%s", block ? block_getSignature(block) : "nil");
```

**修法**：把 `cb(img, img, @{});` 改成

```objc
cb(img, img, @{ @"source" : @"album",
                @"fromCamera" : @(NO),
                @"isAlbum" : @(YES) });
```

**注意**：这三个键是推测，二进制里没有明文。要确定，必须 dump 调用方的 block 实现，看它读哪些 key。没有源码只能试。

### D5 · Turing SDK 风控触发

**证据**：二进制里存在 `/Applications/Cydia.app`、`/Library/MobileSubstrate/MobileSubstrate.dylib`、`cydia://`、`sileo://`、`/usr/lib/libsubstrate.dylib`、`frida`、`isJailbroken`，属腾讯 Turing（`com.tencent.TuringS...`）环境检测。

**这是绕过官方客户端的固有代价，不是代码 bug。**

**可选处置**：

| 方案 | 做法 | 代价 |
|------|------|------|
| 卸载检测 | hook `TSEnvironment` 的 `isJailbroken` 返回 `NO` | 需先定位方法名，且可能有多处调用点 |
| 隐藏注入 | 用 `ellekit` 的隐藏模式，或改包名避开 substrate 路径特征 | 不稳定 |
| 不管 | 只在备用账号上试 | 主账号有锁定风险 |

**我的判断**：只要注入就留痕。想彻底干净，只能不注入。

---

## 阶段 E · 无 Xcode 的替代路线（Docker）

### E1 · Docker 方案

**① 位置**：任意有 Docker 的机器
**② 命令**：

```bash
docker run -it --rm -v "$PWD":/work -w /work \
  theos/theos:latest \
  bash -lc 'export THEOS=/opt/theos && make clean && make package FINALPACKAGE=1'
```

**③ 说明**：镜像内已含 clang、ldid、dpkg、SDK
**④ 常见问题**：镜像里 SDK 版本可能较低，`latest` 解析失败时报 `No SDK found`，改 Makefile 为具体版本
**⑤ 验收**：`packages/*.deb` 生成

---

## 阶段 F · 出包后自检清单

| # | 检查项 | 命令 | 通过标准 |
|---|-------|------|---------|
| F1 | deb 架构正确 | `dpkg-deb -f pkg.deb Architecture` | `iphoneos-arm64` |
| F2 | 路径 rootless | `dpkg-deb -c pkg.deb` | 全部带 `/var/jb/` 前缀 |
| F3 | 过滤器正确 | `dpkg-deb --fsys-tarfile pkg.deb \| tar -xO ./var/jb/Library/MobileSubstrate/DynamicLibraries/RNAAlbum.plist` | 含 `com.tmri.12123` |
| F4 | dylib 架构 | `dpkg-deb -x pkg.deb /tmp/x && file /tmp/x/var/jb/Library/MobileSubstrate/DynamicLibraries/RNAAlbum.dylib` | `arm64` 与 `arm64e` |
| F5 | 依赖声明 | `dpkg-deb -f pkg.deb Depends` | 含 `mobilesubstrate` |

---

## 附 · 完整命令速查（复制即用）

```bash
# ===== 主机：装环境 =====
xcode-select --install
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git $THEOS
echo 'export THEOS=~/theos' >> ~/.zshrc
echo 'export PATH=$THEOS/bin:$PATH' >> ~/.zshrc
source ~/.zshrc
brew install dpkg ldid

# ===== 主机：装 SDK =====
mkdir -p $THEOS/sdks
cp -R /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk $THEOS/sdks/
ls $THEOS/sdks

# ===== 主机：编译 =====
cd ~/rna_albumtweak
make clean
make 2>&1 | tee /tmp/build.log
make package FINALPACKAGE=1
ls -lh packages/

# ===== 主机：装机 =====
scp packages/com.rna.album12123_*.deb root@DEVICE_IP:/var/mobile/Documents/
ssh root@DEVICE_IP "dpkg -i /var/mobile/Documents/com.rna.album12123_*.deb && killall -9 SpringBoard"

# ===== 主机：看日志 =====
idevicesyslog | grep --line-buffered "RNA-Album"

# ===== 设备：回滚 =====
ssh root@DEVICE_IP "dpkg -r com.rna.album12123 && killall -9 SpringBoard"
```

---

## 方案超爽速览总结卡片

| 项目 | 内容 |
|------|------|
| **故障现象** | 一键挪车拍照页没有相册入口，只能用实时快门 |
| **根本破绽** | `CLFJs` 桥 29 个方法中只有 `takePhoto`，无任何 album/chooseImage；`UIImagePickerControllerSourceType` 全二进制零命中 —— 相册能力从未实现 |
| **改动方案** | Theos tweak 注入 `TmriCameraViewController`，`viewDidAppear:` 叠加相册按钮 → PHPicker 选图 → 复用 App 自身 `takePhotoBlock` 回传 |
| **最终效果** | 相机页多一个相册入口，选图后走原有上传链路，业务代码零改动；四道真机门禁全绿即通过 |

---

## 必须知道的两条边界

**1. 三参 block 的字典位是盲区**

签名 `v32@?0@"UIImage"8@"UIImage"16@"NSDictionary"24` 里那个字典要什么键，二进制无明文。空字典可能被业务层拦。真机跑过才知道，修法在 D4。

**2. 注入必然留痕**

Turing SDK 的越狱检测字符串确凿存在。注入后是否触发、触发后是功能限制还是账号锁定，取决于服务端策略，我无法预判。这条不是代码能解决的，是手段本身的代价。
