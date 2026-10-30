//
//  Capabilities.swift
//  能力矩阵：在 macOS 上到底哪些 G-Helper 功能真的可用，为什么不可用
//

import Foundation

enum CapStatus {
    case available      // 完全可用
    case limited        // 部分可用 / 需要 root / 数据不可靠
    case unavailable    // 无法实现

    var badge: String {
        switch self {
        case .available: return "✔"
        case .limited: return "◐"
        case .unavailable: return "✘"
        }
    }

    var label: String {
        switch self {
        case .available: return "可用"
        case .limited: return "受限"
        case .unavailable: return "不可用"
        }
    }
}

struct Capability: Identifiable {
    let id = UUID()
    let title: String
    let status: CapStatus
    let summary: String
    let backend: String
}

enum Capabilities {

    /// 权限受阻时的说明，按真实原因区分
    private static func backlightBlockedSummary() -> String {
        switch Control.permissionState {
        case .needsRestart:
            return "已拿到「输入监控」授权，但当前进程启动时还没读到它：重启本程序即可（TCC 判定在进程启动时缓存）"
        case .denied:
            return "「输入监控」被拒绝；重新编译过的版本会因为 cdhash 变化丢掉旧授权，需重置后重新勾选"
        case .busy:
            return "Aura 控制器被其他进程占用，关掉多余的实例再试"
        case .noDevice:
            return "没有找到 Aura HID 控制器"
        default:
            return "已找到 Aura HID 控制器（0x0B05:0x19B6），需要「输入监控」权限才能打开键盘类 HID 设备"
        }
    }

    private static func isHID(_ mode: BacklightMode) -> Bool {
        if case .hid = mode { return true }
        return false
    }

    private static func backlightSummary(_ mode: BacklightMode) -> String {
        switch mode {
        case .hid:
            return "Aura HID 输出报告（report 0x5A）直接控键盘控制器，共 4 个状态，不需要 root"
        case .smc:
            return "写 LKSB 后由 AsusSMC 调 ACPI 的 SKBV，16 档，需要管理员授权"
        case .none:
            return "ATK 设备没有 SKBV 方法（AsusSMC 报 IsKeyboardBacklightSupported=No），也没有找到 Aura HID 控制器"
        }
    }

    private static func backlightBackend(_ mode: BacklightMode) -> String {
        switch mode {
        case .hid(let pid):
            return String(format: "IOHIDManager → ASUS 0x0B05:0x%04X → 键盘控制器", pid)
        case .smc:
            return "AppleSMC → AsusSMC(LKSB) → ACPI SKBV"
        case .none:
            return "无可用通道"
        }
    }

    /// NVIDIA（NullMoth）驱动更新状态 → 能力矩阵里的一行
    private static func nvidiaCapability(_ state: NvidiaUpdateState) -> Capability {
        let backend = "本地 /Library/NullMoth/driver-version ⇄ GitHub Releases API"
        switch state {
        case .notInstalled:
            return Capability(title: "NVIDIA 驱动更新",
                              status: .unavailable,
                              summary: "没有检测到 NullMoth 驱动（/Library/Extensions 里没有 NVRM）",
                              backend: backend)
        case .unknown:
            return Capability(title: "NVIDIA 驱动更新",
                              status: .limited,
                              summary: "尚未检查过 GitHub 上的最新版本",
                              backend: backend)
        case .checking:
            return Capability(title: "NVIDIA 驱动更新",
                              status: .limited,
                              summary: "正在查询 GitHub Releases…",
                              backend: backend)
        case .upToDate(let installed, let latest):
            return Capability(title: "NVIDIA 驱动更新",
                              status: .available,
                              summary: "已安装 \(installed)，GitHub 最新 \(latest)，无需更新",
                              backend: backend)
        case .available(let installed, let latest):
            return Capability(title: "NVIDIA 驱动更新",
                              status: .limited,
                              summary: "已安装 \(installed)，最新 \(latest)，建议更新后再重启",
                              backend: backend)
        case .failed(let installed, let message):
            return Capability(title: "NVIDIA 驱动更新",
                              status: .limited,
                              summary: "已安装 \(installed)，暂时查不到最新版：\(message)",
                              backend: backend)
        }
    }

    static func all(gpus: [GPUInfo]? = nil,
                    nvidia: NvidiaUpdateState = NvidiaUpdate.stateFromCache()) -> [Capability] {
        let dgpus = gpus ?? SystemProbe.listGPUs()
        let kbdMode = Control.mode
        let fanCount = Double(FanProbe.count)
        let fanUsable = FanProbe.isAvailable
        // 曲线写入通道存在（kext 暴露了选风扇 + 触发键）→ 可改曲线
        let fanCurveReady = SMC.exists("AFWg") && SMC.exists("AFMf")
        // Aura RGB 以「能否打开 Aura HID 控制器」为准
        let auraReady = AuraEffects.shared.isAvailable
        let hasALS = SMC.exists("ALV0")
        let bat = SystemProbe.battery()

        var list: [Capability] = [
            Capability(
                title: "CPU 温度监控",
                status: SMC.exists("TC0P") ? .available : .unavailable,
                summary: SMC.exists("TC0P")
                    ? "通过 SMCAMDProcessor 暴露的 TC0P 读取，按设定间隔采样（默认 2 秒）"
                    : "未找到 TC0P，需要 SMCAMDProcessor 或 SMCIntelProcessor",
                backend: "AppleSMC → SMCAMDProcessor → MSR"
            ),
            Capability(
                // 被权限拦住时通道探测不出来，但机型本身是 HID 的，
                // 这里按 HID 的上限显示，与授权后的「0–3 档」说法保持一致
                title: "键盘背光（\(Control.hidBlocked ? HIDBacklight.maxLevel : kbdMode.maxLevel) 档）",
                status: kbdMode.maxLevel == 0
                    ? (Control.hidBlocked ? .limited : .unavailable)
                    : (isHID(kbdMode) ? .available : .limited),
                summary: Control.hidBlocked
                    ? backlightBlockedSummary()
                    : backlightSummary(kbdMode),
                backend: Control.hidBlocked
                    ? "IOHIDManager → ASUS 0x0B05:0x19B6（等待授权）"
                    : backlightBackend(kbdMode)
            ),
            Capability(
                title: "应用级监控与录制",
                status: .available,
                summary: "逐进程 CPU / 内存排行（libproc），可手动录制一段会话的温度、负载、内存与目标应用数据并导出 CSV",
                backend: "libproc PROC_PIDTASKINFO（无需 root）"
            ),
            Capability(
                title: "CPU 负载 / 热压力",
                status: .available,
                summary: "逐线程占用、load average、内核热压力、内存占用，全部来自 Mach 内核计数器",
                backend: "host_processor_info · ProcessInfo.thermalState（无需 kext）"
            ),
            Capability(
                title: "环境光 / 自动背光",
                status: hasALS ? .available : .unavailable,
                summary: hasALS ? "ALV0 可用，由 AsusSMC 直接接管" : "未找到 ALV0",
                backend: "AppleSMC → AsusSMC(ALS) → EC"
            ),
            Capability(
                title: "电池状态与健康度",
                status: bat.present ? .available : .unavailable,
                summary: bat.present
                    ? "IOKit AppleSmartBattery：电量 / 健康 / 循环 / 温度"
                    : "未检测到电池设备",
                backend: "IOKit AppleSmartBattery"
            ),
            Capability(
                title: "风扇转速读数",
                status: fanUsable ? .available : .unavailable,
                summary: fanUsable
                    ? "检测到 \(Int(fanCount)) 个风扇，F0Ac 读数合理"
                    : "FNum 上报 \(Int(fanCount))、F0Ac 恒为 10000 RPM 且不随负载变化，判定为占位值",
                backend: "AppleSMC → F0Ac"
            ),
            Capability(
                title: "风扇曲线 / 手动转速",
                status: fanCurveReady ? .available : .unavailable,
                summary: fanCurveReady
                    ? "SMCAsusFan.kext 已暴露 AFMf / AFW1–4 / AFWg，可读写 CPU / GPU 风扇曲线"
                    : "未检测到曲线写入通道（AFWg / AFMf），当前机型只能读转速",
                backend: "SMCAsusFan.kext → AFMf / AFW1–4 / AFWg"
            ),
            Capability(
                title: "性能模式（静音/平衡/增强）",
                status: .unavailable,
                summary: "G-Helper 通过 ACPI-WMI（ASUS WMI GUID）调用 DEVS/threshhold 方法，macOS 的 ACPI 实现不把 WMI 暴露给用户态",
                backend: "需要 kext 内部调用 _WDG/WMNB"
            ),
            Capability(
                title: "Aura RGB / Anime Matrix",
                status: auraReady ? .available : .unavailable,
                summary: auraReady
                    ? "Aura HID 控制器已打开，可下发键盘灯效（0x5D 通道）"
                    : "未找到可用的 Aura HID 控制器（可能需要「输入监控」授权）",
                backend: "IOHIDManager → ASUS 0x0B05 Aura"
            )
        ]

        // 独立显卡：按 IORegistry 中实际绑定的驱动判断，而不是按厂商猜
        if let dgpu = dgpus.first(where: { $0.vendor == "NVIDIA" || $0.name.contains("Radeon RX") || $0.name.contains("Radeon Pro") }) {
            list.insert(Capability(
                title: "独立显卡加速（\(dgpu.shortDriver)）",
                status: dgpu.accelerated ? .available : .unavailable,
                summary: dgpu.accelerated
                    ? "\(dgpu.name) 已绑定 \(dgpu.driver)，NVRM + NVAccel 均在线"
                    : "\(dgpu.name) \(dgpu.driver)",
                backend: dgpu.accelerated
                    ? "IORegistry → \(dgpu.shortDriver) (NVRM / NVAccel)"
                    : "IORegistry → PCI 节点无 framebuffer 绑定"
            ), at: 3)
        }

        // 驱动更新检测紧跟显卡那一条
        list.insert(nvidiaCapability(nvidia), at: dgpus.isEmpty ? list.count : 4)

        return list
    }
}
