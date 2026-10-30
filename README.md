# Vela X（原 AsusControl / ROG X）

> macOS 上的华硕 / ROG 笔记本控制中心 —— [G-Helper](https://github.com/seerge/g-helper) 的 macOS 对应实现。  
> 性能模式、风扇曲线、键盘背光与 Aura 灯效、传感器监控、菜单栏多指标、NVIDIA 驱动管理，  
> 全部跑在原生 SwiftUI + Liquid Glass 界面里。

- 版本：**1.4.0**（build 10）
- 界面：macOS 26 Liquid Glass（透明窗 + behindWindow 玻璃 + 26pt 窗口圆角）
- 最低系统：**macOS 13.0**（Liquid Glass 效果在 macOS 26 上最完整）
- 架构：Universal（x86_64 + arm64）
- 许可证：[GPLv3](#许可证)

> 本项目与华硕（ASUS）无任何官方关联，是社区第三方实现。详情见文末[商标声明](#商标声明)。

---

## 功能

| 模块        | 说明                                                           |
| --------- | ------------------------------------------------------------ |
| 性能与风扇     | 性能模式切换；双风扇实时转速；**三档风扇曲线**（静音 / 平衡 / 性能），依赖 `SMCAsusFan.kext` |
| 键盘背光      | HID 写入（report ID `0x5A`），0–3 档亮度                             |
| Aura 灯效   | HID 写入（report ID `0x5D`），12 种灯效模式                            |
| 传感器监控     | CPU / GPU 温度、负载、频率、内存、网速、功耗                                  |
| 菜单栏       | 可勾选 7 项指标实时拼接进菜单栏标题                                          |
| NVIDIA 驱动 | 检查 / 下载 / 安装 NullMoth 的 macOS NVIDIA 驱动                      |
| 命令行       | 同源 CLI：`vela status` / `vela fan ...` / `vela aura ...`      |

---

## 环境要求

- 一台**黑苹果 / OpenCore** 的华硕 / ROG 笔记本（原生 Mac 没有这些 EC 设备，用不了）
- macOS 13.0+，建议 macOS 26 以获得完整 Liquid Glass 观感
- Command Line Tools（`xcode-select --install`，**不需要 Xcode**）
- 风扇曲线需要 [`SMCAsusFan.kext`](https://github.com/seerge/g-helper)（EC 风扇邮箱 → SMC 键的桥接内核扩展）

---

## 构建

只需要 Command Line Tools：

```bash
xcode-select --install          # 若尚未安装命令行工具

./build.sh                      # 编译 → build/Vela X.app
./build.sh --dmg                # 编译 + 打包 → dist/Vela X-<版本>.dmg
./build.sh x86_64               # 只编指定架构
```

### 签名（推荐但非必须）

本程序需要 **「输入监控」** 权限才能写键盘背光和 Aura 灯效。该权限按代码签名（cdhash）记录，  
而 ad-hoc 签名的 cdhash **每次编译都会变**，导致授权反复失效。所以建议先用本地自签证书：

```bash
./Tools/make_signing_cert.sh    # 只需跑一次，证书存于独立钥匙串
./build.sh                      # 之后自动用它签名（TCC 授权稳定）
```

若钥匙串被锁定，构建前先解锁：

```bash
security unlock-keychain -p asuscontrol-signing ~/Library/Keychains/asuscontrol-signing.keychain-db
```

不创建证书也能跑，只是每次重编译后需要重新勾选「输入监控」。

---

## 风扇曲线（需要 SMCAsusFan.kext）

「性能与风扇」页能读双风扇转速、切换三档曲线（静音 / 平衡 / 性能）：

- 读状态免 root：转速走 `F0Ac` / `F1Ac`，kext 是否在跑看 `AFMd`
- 切档位要写 SMC 键（`AFMf` + `AFW1..4` + `AFWg`），点「应用」时用系统授权提权一次，程序本身**不常驻 root**
- 曲线配置随包发布（`Resources/fan_presets.json`），也支持 `~/Library/Application Support/SMCAsusFan/fan_presets.json` 覆盖
- 命令行同源：`vela fan status` / `vela fan list` / `vela fan set <档位>`

命令：

```bash
vela fan status                              # kext 版本 + 双风扇转速（免 root）
vela fan list                                # 三档曲线摘要
sudo vela fan set silent|balanced|performance   # 下发曲线（写 SMC 需 root）
```

> ⚠️ 写 EC 风扇曲线有风险：错误的曲线可能导致风扇失控。操作前建议用  
> `tools/curve.py read 0` 备份原始曲线；真出问题时断电重启即可回到出厂曲线。

### 机型与 EC 配置识别

不同机型的 EC（嵌入式控制器）布局不同——MMIO 地址、邮箱寄存器、曲线格式、风扇数量都不一样。
**把 A 机型的曲线写进 B 机型，可能损坏硬件。** 所以程序会先做机型识别，并在不一致时强制确认。

程序用**硬件指纹**判定机型：CPU 型号代号 + 独显世代 + 出厂电池容量 + 主屏规格，
四条证据逐项打分（CPU 代号 50 分、独显 30 分、电池 12 分、屏幕 8 分），取最高分机型并给出置信度。

为什么不是读 `DeviceName`：OpenCore 会把 SMBIOS 整套换成 Mac（`hw.model` 恒为 `MacBookPro16,4`
之类），看起来最可靠的「电池 `DeviceName`」其实是**电池部件号** —— 同一块电池装在多款机器上，
实测魔霸6（G513RM）和魔霸7 Plus（G713PV）都报 `GA50358`。所以它只作为附注显示，不参与判定。

CPU 代号之所以是最强证据，是因为华硕的 CPU 后缀就是产品线分界线：

| 产品线 | CPU 代号 | 独显 |
|---|---|---|
| 幻15 GA503（2022） | `6900HS` / `5900HS`（**HS**） | RTX 30 |
| 魔霸6 G513（2022） | `6900HX` / `6800H`（**H / HX**） | RTX 30 |
| 魔霸7 Plus G713P（2023） | `7945HX` / `7845HX`（Dragon Range） | RTX 40 |

判定结果分三档，显示在「性能与风扇」页顶部的机型卡上（可展开「查看判定依据」逐条核对）：

| 状态 | 含义 | 能否下发曲线 |
|---|---|---|
| ✅ **机型匹配** | 所选机型与判定结果一致 | 可以直接下发 |
| ⚠️ **机型待确认** | 指纹没匹配到任何已收录机型，无从核对所选机型 | 需核对型号并确认一次 |
| ⛔ **机型不匹配** | 所选机型与判定结果不一致（中/高置信度） | **必须先确认免责声明** |

> 低置信度或压根没认出来时**不会**拦你 —— 没有证据，就不该拿免责声明吓人。

**机主可以手动选择机型**（按 model 名，例如 `G513RM`）：机型卡上有已知机型菜单，
也可以直接输入型号代码。所选机型与判定结果不一致时，页面会显示红色警告卡，
点「查看风险并继续」后弹出免责声明，逐条说明可能的后果（风扇失控、EC 锁死、散热失效导致
CPU/GPU 过热降频甚至永久损坏、电池与供电异常、保修失效），**必须显式确认才允许下发曲线**。

命令行同源：

```bash
vela model                     # 显示硬件指纹、判定机型、置信度、候选得分、匹配状态
vela model probe               # 打印完整指纹与逐条判定依据（反馈新机型时贴这个）
vela model set G513RM          # 手动选择机型（未获确认时会打印免责声明并拒绝）
vela model set G513RM --i-understand   # 未获确认但确认风险，强制写入
vela model clear               # 清除手动选择，回到自动判定
```

### 已收录机型

| 机型代码 | 机型 | EC | 曲线可信度 |
|---|---|---|---|
| `G513RM` `G513RS` `G513RW` `G513` | ROG Strix G15 / **魔霸6** (2022) | ITE IT5571 · `TI5825_G513_1027` | ✅ 实机已验证 |
| `G713PV` `G713PI` `G713PY` `G713P` | ROG Strix G17 / **魔霸7 Plus** (2023) | ITE IT5571 · `ITE EC-V14.6` | ⚠️ 逆向未实机验证 |

**「机型能对上」不等于「曲线在这台机器上跑过」**，所以每个机型还带一个 `verification` 标记：

- `verifiedOnDevice` —— 已在本机型实机下发过，转速/温度响应符合预期
- `reverseEngineered` —— EC 布局已逆向确认，但曲线**没在这台机器上实机验证过**。
  界面与 CLI 都会显示黄色提示，要求先做只读验证（能读到转速且随负载变化），
  再下发曲线并观察转速是否真的响应

给新机型加支持，往 `Sources/ECProfiles.swift` 的 `catalog` 加一条（含 `fingerprint`），
曲线放到 `Resources/fan_presets-<MODEL>.json`（`build.sh` 会带进 bundle），其它代码不用动：

```swift
ECProfile(
    modelCodes: ["G713PV", "G713PI", "G713PY", "G713P"],
    familyPrefixes: ["G713P"],
    familyName: "ROG Strix G17 / 魔霸7 Plus (2023)",
    ecChip: "ITE IT5571",
    ecFirmware: "ITE EC-V14.6",
    curvePoints: 8, tempMin: 20, tempMax: 110, dutyMin: 0, dutyMax: 100,
    mmio: ["it55": "0xFE700600", "mb00": "0xFE700B00", "mc00": "0xFE700C00"],
    note: "...",
    source: "内置",
    verification: .reverseEngineered,     // 没有实机验证过就别写成 .verifiedOnDevice
    fingerprint: ModelFingerprint(
        // cpuCodes 是**精确相等**比较，别写成子串包含：那会让 "6800H" 误吃幻15 的 "6800HS"
        cpuCodes: ["7945HX", "7845HX", "7745HX"],
        gpuHints: ["RTX 4060", "RTX 4070", "RTX 4080"],
        batteryWh: 84...96,
        minScreenPixels: 2560
    )
)
```

> `familyPrefixes` 要收窄到已验证的范围。比如魔霸7 Plus 只写 `G713P` 而不是 `G713`，
> 否则会把魔霸6 Plus（G713RW / G713RS，2022）也吸进来套用未验证的曲线。
> 收窄后 6 Plus 会落到「未收录」（没有 EC 配置），而不是被当成「兼容」放行 —— 宁可不给，也不给错的。

> 新机型的 MMIO / 邮箱寄存器需要重新逆向。交付包里的 `tools/mkconfig.py --capture`
> 可以从 Windows 下的 Armoury Crate 抓取通信记录，再用 `mkconfig.py` 生成配置。

### 确认实际用的是哪份曲线

多机型共存时，**三档曲线的数值可能完全一样**（例如魔霸7 Plus 沿用了魔霸6 G513RM 的实测值），
光看数值分辨不出加载了哪份文件。`vela fan list` 会打印来源：

```bash
$ vela model set G713PV --i-understand
$ vela fan list
来源         .../Resources/fan_presets-G713PV.json
针对机型     ASUS ROG Strix G17 G713PV
```

---

## 目录结构

```
build.sh                    构建脚本（编译 + 签名 + 可选打包 dmg）
Sources/                    Swift 源码
  main.swift / App.swift      入口、主窗口、菜单栏项目
  Views.swift                 主界面骨架、侧栏、页面路由、滚动条自动隐藏
  VisualEffectView.swift      透明窗 / 玻璃 / 窗口外观装配（圆角、标题栏）
  Theme.swift / UIComponents.swift  调色板、主题、通用控件
  SMC.swift / SMCBridge.{h,c}       SMC 读写（温度、风扇、功耗）
  SMCClient.swift / FanPresets.swift / FanControl.swift  风扇曲线（接 SMCAsusFan）
  ECProfiles.swift                 机型/EC 配置目录、机型检测、匹配状态、免责声明
  HIDBacklight.swift               键盘背光（report ID 0x5A）
  AuraEffects.swift / AuraPanel.swift   Aura 灯效（report ID 0x5D）
  SystemLoad.swift / SystemInfo.swift  负载与硬件信息
  MenuMetrics.swift            菜单栏指标采集（网速、温度、内存…）
  NvidiaUpdate.swift / NvidiaView.swift  NVIDIA 驱动检查、下载安装
  MonitorView.swift / LoadViews.swift / SensorStore.swift  监控与负载页面
  Prefs.swift / CLI.swift / AppInfo.swift  偏好、命令行、版本信息
Resources/                   Info.plist、图标、品牌标、fan_presets.json
                             + fan_presets-<MODEL>.json（机型专属曲线，如 G713PV）
                             + device_profile-<MODEL>.h（kext 用的机型 EC 常量，重新编译 kext 时参考）
Tools/                       make_signing_cert.sh、make_dmg.sh、图标生成脚本
MIGRATION.md                 v2.x 更名（AsusControl → Vela X）迁移说明
```

---

## 权限

首次运行需要在「系统设置 → 隐私与安全性」中授予：

- **输入监控**：键盘背光与 Aura 灯效（HID 写入）
- **辅助功能 / 管理员密码**：部分需要提权的操作（驱动安装、风扇控制）

TCC 授权在进程启动时读取一次，**授权后需要重启 App** 才生效。

---

## 协议要点（改动前务必确认）

- 亮度通道：report ID `0x5A`，载荷 `5A BA C5 C4 <level>` 补零到 64 字节，首字节必须是报告 ID。
- Aura 通道：report ID `0x5D`，效果 `5D B3 ...`（17 字节）→ 提交 `5D B5 00 00 00` → 应用 `5D B4`。
- 两个通道不能混用；HID 设备筛选优先按产品名含 `N-KEY`，不要按「有 feature report」过滤。

---

## 自测（无 UI 交互）

```bash
ASUS_SELFTEST=1 ASUS_PAGE=overview ASUS_THEME=dark ASUS_SELFTEST_DELAY=10 \
  ./build/Vela X.app/Contents/MacOS/AsusControl
# 约 10 秒后把窗口截图写到 /tmp/live_window.png 并退出
```

|                           |         |           |       |             |        |
| ------------------------- | ------- | --------- | ----- | ----------- | ------ |
| `ASUS_PAGE` 可选 \`overview | menubar | nvidia    | about | performance | ...\`， |
|                           |         |           |       |             |        |
| ---                       | ---     | ---       |       |             |        |
| `ASUS_THEME` 可选 \`dark    | light   | system\`。 |       |             |        |

---

## 安全与风险提示

- 本程序直接读写笔记本的 **EC（嵌入式控制器）** 与 **SMC**。错误的写入可能改变风扇行为、  
  背光逻辑甚至温度保护策略。请在理解后果的前提下使用，**作者不对任何硬件损坏负责**。
- 它会请求「输入监控」权限（用于 HID 写入背光），这是 macOS 正常的硬件控制机制，  
  但请只从可信来源运行。
- 程序**不常驻 root**，仅在需要下发风扇曲线 / 安装驱动时通过系统授权弹窗提权一次。
- 这并非华硕官方软件，**使用本程序可能导致保修失效**，请自行权衡。

---

## 商标声明

- **ROG** 及 **Republic of Gamers** 是华硕（ASUS）的注册商标。`Resources/ROGLogo.png` /  
  `ROGLogoRed.png` 为品牌展示用图，本项目使用不构成任何授权或关联。
- 本项目名称 **Vela X** 为独立品牌，与华硕无隶属关系。
- 所有厂商名、产品名为其各自所有者的财产。

---

## 贡献

欢迎 Issue 和 Pull Request。

- 提 Bug 请附：`vela status` 输出、macOS 版本、机型、kext 状态
- 改协议 / 灯效前请先读上面的[协议要点](#协议要点改动前务必确认)
- 本地构建见[构建](#构建)；提交前请确保 `./build.sh` 通过、无遗留 `build/` 产物

---

## 许可证

[GPLv3](LICENSE) © 2026 XelonJangs

本项目基于 **GNU General Public License v3.0** 发布。你可以自由使用、修改、再分发，  
但任何分发（含修改版）都必须以相同许可证开源全部源代码。

## 致谢

- [G-Helper](https://github.com/seerge/g-helper) — 原始 Windows 实现与思路来源
- 奥创中心（Armoury Crate）— 设备协议参考
- [NullMoth](https://github.com/nullmoth/nvidia-macos-driver) — macOS NVIDIA 驱动
- angus666888 — EC 灯效修复思路
