# AsusControl 迁移说明

> 版本 **1.12.2** · 导出日期 2026-10-27 · Bundle ID `dev.asuscontrol.mac`
> 这份文档面向「把工程搬到新机器 / 新环境继续开发」，重点是**怎么跑起来**和**哪些坑不能重踩**。

---

## 一、项目概览

G-Helper（`seerge/g-helper`）的 **macOS 原生重写版**。G-Helper 本身是 Windows 独占的 .NET 应用（依赖 WMI / NVAPI / WASAPI），不能直接移植，所以这边用 Swift 重写了同一套能力。

- **实测机型**：ASUS ROG Zephyrus G15（Ryzen 9 6900HX + RTX 3060，macOS 15.8 黑苹果）
- **目标设备**：USB HID `0x0B05:0x19B6`（N-KEY Device），2021+ ROG 机型
- **规模**：30 个 Swift 文件、**7960 行 Swift**，另有 `SMCBridge.c/.h` 做 C 桥接
- **技术栈**：SwiftUI + AppKit + IOKit(HID) + Combine
- **构建方式**：**不需要 Xcode**，只用 Xcode Command Line Tools（`clang` + `swiftc` + `lipo` + `codesign` + `hdiutil`）
- **部署目标**：macOS **13.0** 起；构建产物为 **x86_64 + arm64 通用二进制**

---

## 二、目录结构

```
AsusControl/
├── Sources/                  # 全部源码
│   ├── App.swift             # App 入口、菜单栏常驻、AppDelegate（含自检截图）
│   ├── main.swift            # 进程入口（ASUS_SELFTEST 环境变量支持）
│   ├── Views.swift           # 主界面 + 8 个页面路由 + 侧栏
│   ├── UIComponents.swift    # 设计系统：Palette 配色 / Card 玻璃面板 / 各类控件
│   ├── Theme.swift           # 深浅色主题（ThemeMode + ThemeManager + 自适应颜色）
│   ├── HIDBacklight.swift    # 键盘背光「亮度」控制（0x5A 通道）+ 输入监控权限判定
│   ├── AuraEffects.swift     # Aura RGB 灯效协议（0x5D 通道，17 字节报文）
│   ├── AuraPanel.swift       # RGB 灯效面板 UI（12 模式 / 主辅色 / 速度 / 方向）
│   ├── SensorStore.swift     # 传感器采样中枢（后台队列 + 统一快照）
│   ├── SMC.swift / SMCBridge.{c,h}  # AppleSMC 读取的 C 桥接
│   ├── Capabilities.swift    # 能力矩阵（哪些功能在本机可用）
│   ├── Privileged.swift      # Control 层：统一背光/权限/模式判定（带 60s 缓存）
│   ├── Sampling.swift        # 采样频率 1/2/3/5 秒可选
│   ├── NvidiaUpdate.swift    # NullMoth 驱动更新检测（拦 302 取 tag）
│   ├── NvidiaView.swift / AboutView.swift / MonitorView.swift / LoadViews.swift
│   ├── CLI.swift             # 命令行全部子命令
│   ├── Prefs.swift           # UserDefaults suite 封装（GUI 与 CLI 共用一份）
│   └── AppInfo.swift / SystemInfo.swift / ModelCatalog.swift / Recording.swift …
├── Resources/                # AppIcon.icns、Info.plist、ROGLogo.png（白）、ROGLogoRed.png（红）
├── Tools/
│   ├── make_signing_cert.sh  # 生成本地自签代码签名证书（重要）
│   ├── make_dmg.sh           # 打 dmg 安装包
│   ├── make_icon.swift       # 生成 icns
│   └── trim_logo.swift       # logo 去透明留白
├── docs/screenshots/         # 各页截图（27 MB，本源码包未含，见 README）
├── build.sh                  # 编译 + 签名
├── README.md                 # 完整设计文档（含 G-Helper 协议分析）
└── MIGRATION.md              # 本文件
```

---

## 三、新机器上跑起来（三步）

```bash
# 0) 前置：Command Line Tools
xcode-select --install      # 已装可跳过

# 1) 生成稳定的本地签名证书（强烈建议，见第四节「坑 1」）
./Tools/make_signing_cert.sh

# 2) 编译通用二进制 → build/AsusControl.app，并生成 build/asuscontrol CLI
./build.sh

# 3) 打安装包（可选）
./Tools/make_dmg.sh          # 产出 dist/AsusControl-<版本>.dmg

# 或者一条命令搞定：编译完直接打包
./build.sh --dmg
```

> 构建成功时会打印最终签名信息，形如 `designated => identifier "dev.asuscontrol.mac" and certificate leaf = H"86512d…"`，
> 这就说明用的是固定证书。**务必确认打印了这一行**，而不是「签名失败，退回 ad-hoc」。

### 签名钥匙串的密码

`make_signing_cert.sh` 把证书放在一个独立钥匙串里，**密码是写死在脚本里的**，不需要你去想：

```bash
KEYCHAIN_PASS="asuscontrol-signing"     # Tools/make_signing_cert.sh
```

钥匙串被锁住时 `codesign` 拿不到私钥，构建会悄悄退回 ad-hoc（这就是刚才踩到的坑）。先解锁再构建：

```bash
security unlock-keychain -p asuscontrol-signing \
  ~/Library/Keychains/asuscontrol-signing.keychain-db
./build.sh
```

> ⚠ 退回 ad-hoc 的后果：TCC 改用 **cdhash** 认应用，下一次重新编译授权立刻失效，界面会开始报「没有权限」。
> 如果发现已经在报权限，就重新勾一次输入监控并重启 App。

自检截图（无需屏幕录制权限也能验证界面是否真的画出来）：

```bash
ASUS_SELFTEST=1 build/AsusControl.app/Contents/MacOS/AsusControl   # → /tmp/live_window.png
ASUS_PAGE=keyboard ASUS_THEME=light ...                            # 指定页面 / 主题
```

常用 CLI：`build/asuscontrol status|doctor|sensors|kbd <0-3>|aura|hid-permission|nvidia|rate|bench|record|top|load|about`

---

## 四、两个绕不开的坑

### 坑 1：「输入监控」授权 / TCC

macOS 把键盘类 HID 设备锁了，`IOHIDDeviceOpen` 会返回 `kIOReturnNotPermitted (0xE00002E2)`。

1. 需要 **系统设置 → 隐私与安全性 → 输入监控** 勾选本 App。
2. **TCC 只在进程启动时读取一次**：勾选授权时 App 正在跑的话，这个进程永远拿不到新授权，**必须重启 App**（代码里 `HIDBacklight.relaunch()` / `resetPermission()` 就是干这个）。
3. **必须用本地证书签名**：ad-hoc 签名时 TCC 按 **cdhash** 认应用，每重新编译一次 cdhash 就变，系统里那个勾选立刻对不上 → 表现为「明明勾了还说没权限」。
   `make_signing_cert.sh` 会在 `~/Library/Keychains/asuscontrol-signing.keychain-db` 生成 `ASUS Control Local Signing`，`build.sh` 会自动用它（**按证书 SHA-1 指纹指定身份**，避免同名证书命中错误）。
4. 诊断：`build/asuscontrol hid-permission`；重置：`... hid-permission reset`（走 `tccutil`）。
5. 本地自签未公证 → Gatekeeper 首次判 rejected，**右键 → 打开** 放行一次即可。

### 坑 2：HID 背光协议（返回成功但灯不变的根因）

设备 `0x0B05:0x19B6`（N-KEY），feature/output report 均 64 字节。两条通道**不能混**：

| 通道 | Report ID | 用途 |
|---|---|---|
| INPUT | `0x5A` | 亮度 / 握手 |
| AURA | `0x5D` | 灯效 |

**亮度帧**（最容易写错）：

```
buf = [0x5A, 0xBA, 0xC5, 0xC4, level] + 补零到 64 字节
IOHIDDeviceSetReport(dev, feature, reportID = 0x5A, buf, 64)
```

> ⚠ **缓冲区首字节必须是报告 ID 本身**，且 `reportID` 参数传同一个值。
> 少了这个首字节 → `IOHIDDeviceSetReport` 照样返回 `kIOReturnSuccess`，但设备识别不到命令，就是经典的「灯没变」。
> 发送顺序：`feature 0x5A` → `feature 0x5D` → `output 0x5D`，任一成功即止（`HIDBacklight.frames(level:)`）。

**灯效三步走**，缺一不生效（`AuraEffects.swift`）：

```
效果  5D B3 <Zone> <Mode> <R> <G> <B> <Speed> <Dir> <Flag> <R2> <G2> <B2>   (17 字节，不补零)
提交  5D B5 00 00 00
应用  5D B4
```

- 速度枚举：`0xE1` 慢 / `0xEB` 中 / `0xF5` 快（不是 0/1/2）
- Flag：普通 `0x00`、呼吸 `0x01`、全黑（随机色）`0xFF`
- 打开设备后先发 Aura 唤醒序列：`5D B9` / `5D "ASUS Tech.Inc."` / `5D 05 20 31 00 20`
- **不要按「有 feature report」过滤设备接口** —— 0x19B6 可能只走 output 通道，过滤会直接错失真正能控灯的那个接口；现在的实现会优先挑产品名含 `N-KEY` 的设备

---

## 五、主要子系统

- **传感器采样**：`SensorStore` 统一调度，全部采样在串行后台队列（`DispatchSourceTimer`），主线程只做赋值；`SMCBridge.c` 走 AppleSMC 读温度/风扇/电压。采样频率 `SamplingRate` 1/2/3/5 秒可选，持久化在 `dev.asuscontrol.mac.prefs` 的 `sample.interval`。
- **键盘背光**：`HIDBacklight`（亮度 0–3 档，含权限四态判定）+ `AuraEffects`/`AuraPanel`（RGB 12 种模式、主辅色、速度、方向、报文预览）。键盘页同时挂载两块。
- **NVIDIA 驱动更新**：读 `/Library/NullMoth/driver-version`，最新版本**不走 GitHub API**（匿名配额常被限流），而是请求 releases/latest 并 `willPerformHTTPRedirection` 拦截 302 从 Location 取 tag —— 0 字节正文。结果缓存 6 小时。
- **深浅色主题**（本版新增）：`Theme.swift` 的 `ThemeManager` 支持 深色 / 浅色 / 跟随系统，持久化到 `appearance`；`Palette` 全部改为动态 NSColor 自适应；浅色模式品牌标自动换成红色版 `ROGLogoRed.png`。侧栏底部有切换器。
- **偏好存储**：统一走 `UserDefaults(suiteName: "dev.asuscontrol.mac.prefs")`。原因：CLI 经 `build/asuscontrol` 符号链接调用时 `Bundle.main` 解析不到 Info.plist，`UserDefaults.standard` 会落到别的域 —— GUI 和 CLI 必须共用同一份 suite。同理 `AppInfo.plistValue()` 与 `ROGLogo` 加载资源都做了按 executablePath 回溯的多路查找。

---

## 六、版本演进摘要

| 版本 | 要点 |
|---|---|
| 1.7.0 | 可选采样频率；定位并修掉卡顿两大根因（`Control.currentLevel()` 13.4ms/次、`TempRing` 锥形渐变软格栅）；首屏三卡对齐 |
| 1.8.0 | ROG 品牌标接入（去留白工具）；NVIDIA 驱动更新检测 |
| 1.9.0 | NVIDIA 独立成页 +「关于」页；版本号兼容符号链接场景 |
| 1.9.1 | 修「已授权仍提示没权限」：TCC 启动只读一次 + ad-hoc cdhash 失效；新增自签证书工具、权限四态文案、`hid-permission` |
| 1.10.0 | 修「授权正常却控不了灯」：亮度命令应是 **SET_FEATURE** 且要按长度补零，不是裸 4 字节 output |
| 1.11.0 | UI 全改圆角 + Liquid Glass 风格（模拟，因原生 `glassEffect()` 需 macOS 26） |
| 1.12.0 | 深浅色主题系统（深/浅/跟随系统）+ 浅色红色 logo + 侧栏外观切换器 |
| 1.12.1 | 合入「亮度帧首字节必须是报告 ID」的修正；设备筛选放开并优先 N-KEY |
| **1.12.2** | 合并修好的 RGB 灯效预设（`AuraPanel`/`AuraEffects`）；首次以本地证书稳定签名；新增 dmg 打包；基线已回写资料库 |

---

## 七、迁移后待办 / 已知遗留

- **RGB 灯效尚未在真机实测** —— 本机自检环境没有输入监控权限，面板会正确显示「申请授权」引导；请在目标机上授权后实测 12 种模式与颜色是否生效。
- `README.md` 里「整窗强制暗色，跟系统深浅色设置无关」这句**已过时**（现为深浅可切 + 跟随系统），建议下次更新。
- 项目根有一份残留 `AsusControl.app/`（02:45 的旧拷贝，**不是**构建产物，构建产物在 `build/`）。源码包已排除；确认无用后可自行删除。
- `docs/screenshots/`（27 MB）不在本源码包内，README 里的图片引用就地缺失；需要的话从资料库基线或原环境拷。
- 资料库基线节点 **AsusControl-RGB** 已同步到 v1.12.2（节点 ID 与链接不变），含源码 + 构建好的 app。

---

## 八、迁移检查清单

- [ ] 装 Xcode Command Line Tools
- [ ] `./Tools/make_signing_cert.sh`（避免 TCC 授权随重编译失效）
- [ ] `./build.sh` 双架构编译通过
- [ ] `./Tools/make_dmg.sh` 产出 dmg（可选）
- [ ] 首次运行：右键「打开」放行 Gatekeeper
- [ ] 系统设置 → 隐私与安全性 → 输入监控 → 勾选本 App → **重启 App**
- [ ] 键盘背光页：亮度 0–3 档实际生效 + RGB 面板出现 12 种模式
- [ ] `build/asuscontrol doctor` 无 ERROR；`hid-permission` 显示 granted
