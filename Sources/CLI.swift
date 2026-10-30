//
//  CLI.swift
//  命令行接口 —— 同一份二进制，带参数即进入 CLI 模式
//
//  用法：
//    AsusControl status            概览
//    AsusControl sensors           传感器读数
//    AsusControl kbd <0-16>        设置键盘背光（需 root）
//    AsusControl smc list|read KEY|write KEY HEX
//    AsusControl doctor            能力诊断
//

import Foundation

enum CLI {
    static var lastMessage = ""

    /// 命令文件路径：`open` 启动时用文件传参（macOS 不支持 open --args）
    static var pendingCommandFile: String? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".asuscontrol-cmd").path
    }

    /// 通过 `open` 启动时拿不到 stdout，输出同时写到 ~/.asuscontrol-cli.log
    private static let logURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".asuscontrol-cli.log")
    }()

    private static func appendLog(_ text: String) {
        let line = text.hasSuffix("\n") ? text : text + "\n"
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private static func emit(_ text: String, printOutput: Bool) {
        lastMessage = text
        appendLog(text)
        if printOutput { print(text) }
    }

    static func run(_ rawArgs: [String], printOutput: Bool = true) -> Int32 {
        let args = rawArgs
        guard let cmd = args.first else {
            emit(helpText, printOutput: printOutput)
            return 0
        }

        switch cmd {
        case "status":
            emit(statusText(), printOutput: printOutput)
            return 0

        case "sensors", "sensor":
            emit(sensorsText(), printOutput: printOutput)
            return 0

        case "kbd", "keyboard":
            let mode = Control.mode
            guard mode.maxLevel > 0 else {
                switch Control.permissionState {
                case .notDetermined:
                    emit("""
                    ERR 还没有拿到「输入监控」权限，无法打开键盘控制器。
                        运行 `asuscontrol hid-permission` 查看状态；授权后需要重启（GUI 里点「立即重启」）
                    """, printOutput: printOutput)
                    return 3
                case .needsRestart:
                    emit("""
                    ERR 已授权，但当前进程启动时还没读到 —— 重启程序后再试。
                        输入监控权限: \(HIDBacklight.listenPermission.rawValue)
                    """, printOutput: printOutput)
                    return 3
                case .denied:
                    emit("""
                    ERR 「输入监控」被拒绝。若刚重新编译过（ad-hoc 签名换 cdhash），先：
                        asuscontrol hid-permission reset
                        然后去 系统设置 → 隐私与安全性 → 输入监控 勾选并重启
                    """, printOutput: printOutput)
                    return 3
                case .busy:
                    emit("ERR 背光设备被其他进程占用，先退出多余的 Vela X 实例", printOutput: printOutput)
                    return 3
                case .noDevice:
                    emit("ERR 没找到 ASUS Aura HID 控制器（0x0B05），这台机器可能走 SMC 的 LKSB 通道", printOutput: printOutput)
                    return 4
                case .granted:
                    emit("ERR 当前机型不可控：ATK 设备无 SKBV 方法，也没找到 Aura HID 控制器", printOutput: printOutput)
                    return 4
                }
            }
            guard args.count >= 2 else {
                emit("通道: \(mode.label)  (0-\(mode.maxLevel))\n当前: \(Control.currentLevel())\n\(mode.detail)",
                     printOutput: printOutput)
                return 0
            }
            guard let level = Int(args[1]) else {
                emit("ERR 用法: kbd <0-\(mode.maxLevel)>", printOutput: printOutput)
                return 2
            }
            if let err = Control.setBacklight(level) {
                emit("ERR \(err)", printOutput: printOutput)
                return err.contains("root") ? 3 : 5
            }
            emit("""
            OK 键盘背光 = \(max(0, min(mode.maxLevel, level)))/\(mode.maxLevel)
               通道 \(mode.label) · 写入方式 \(HIDBacklight.shared.writeMethodText)
            """, printOutput: printOutput)
            return 0

        case "aura", "rgb", "effect":
            return runAura(Array(args.dropFirst()), printOutput: printOutput)

        case "smc":
            return runSMC(Array(args.dropFirst()), printOutput: printOutput)

        case "hid-scan", "hidscan":
            var lines: [String] = []
            for cls in ["IOHIDDevice", "AppleUserHIDDevice"] {
                var iter: io_iterator_t = 0
                let kr = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter)
                lines.append("\(cls): matching kr=0x\(String(UInt32(bitPattern: kr), radix: 16))")
                guard kr == KERN_SUCCESS else { continue }
                var svc = IOIteratorNext(iter)
                while svc != 0 {
                    if let dev = IOHIDDeviceCreate(kCFAllocatorDefault, svc) {
                        func p(_ k: String) -> Int { (IOHIDDeviceGetProperty(dev, k as CFString) as? NSNumber)?.intValue ?? -1 }
                        let vid = p(kIOHIDVendorIDKey), pid = p(kIOHIDProductIDKey)
                        if vid == 0x0B05 {
                            let name = (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String) ?? "?"
                            lines.append(String(format: "  ASUS 0x%04X:0x%04X %@ out=%d", vid, pid, name, p(kIOHIDMaxOutputReportSizeKey)))
                        }
                    }
                    IOObjectRelease(svc)
                    svc = IOIteratorNext(iter)
                }
                IOObjectRelease(iter)
            }
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return 0

        case "hid-permission", "hidperm":
            if args.contains("reset") {
                let rc = HIDBacklight.resetPermission()
                let granted = HIDBacklight.requestPermission()
                emit("""
                已重置「输入监控」授权（tccutil 返回 \(rc)），并重新发起申请：\(granted ? "系统已允许" : "等待系统弹窗/勾选")
                接下来：系统设置 → 隐私与安全性 → 输入监控 → 勾选 Vela X → 重启本程序
                """, printOutput: printOutput)
                return 0
            }

            let before = HIDBacklight.listenPermission.rawValue
            let requested = HIDBacklight.requestPermission()
            let after = HIDBacklight.listenPermission.rawValue
            let state = HIDBacklight.shared.permissionState

            var lines: [String] = []
            lines.append("输入监控权限: \(before) → \(after)（申请返回 \(requested)）")
            lines.append("实际状态    : \(Self.permissionText(state))")
            lines.append("Aura 设备   : \(HIDBacklight.shared.deviceFound ? "已找到（0x0B05）" : "未找到")")
            lines.append("打开设备    : \(Self.kernText(HIDBacklight.shared.lastOpenResult))")
            switch state {
            case .granted:
                lines.append("结论        : 可以直接控制背光（0–3 档）")
            case .needsRestart:
                lines.append("结论        : 系统里已授权，但本进程启动时还没读到 → 必须重启程序")
            case .denied:
                lines.append("结论        : 被明确拒绝。若是重新编译过的版本，先 `asuscontrol hid-permission reset` 再勾选")
            case .notDetermined:
                lines.append("结论        : 还没授权，去 系统设置 → 隐私与安全性 → 输入监控 勾选后重启")
            case .busy:
                lines.append("结论        : 设备被别的进程占着，先退出其它实例")
            case .noDevice:
                lines.append("结论        : 没找到 Aura 控制器，与权限无关")
            }
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return 0

        case "load", "cpu":
            _ = SystemLoad.sample()          // 建立基线
            usleep(400_000)
            emit(loadText(SystemLoad.sample()), printOutput: printOutput)
            return 0

        case "top", "ps":
            _ = ProcessSampler.sample()
            usleep(600_000)
            let list = ProcessSampler.sample()
            let byMem = args.contains("mem") || args.contains("--mem")
            let rows = ProcessSampler.top(list, byCPU: !byMem, limit: 12)
            var lines: [String] = [byMem ? "按内存排序：" : "按 CPU 排序："]
            for p in rows {
                lines.append(String(format: "  %-28@ pid %-6d  cpu %5.1f%%   mem %7.1f MB",
                                    p.name as NSString, p.pid, p.cpu * 100, p.memoryMB))
            }
            lines.append("")
            lines.append("共 \(list.count) 个可读进程（libproc，无需 root）")
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return 0

        case "record":
            // record <秒数> [标签]
            let seconds = args.count >= 2 ? (Int(args[1]) ?? 30) : 30
            let label = args.count >= 3 ? args[2] : "CLI 录制"
            var samples: [MetricSample] = []
            let start = Date()
            var last = SystemLoad.sample()
            while Date().timeIntervalSince(start) < Double(seconds) {
                last = SystemLoad.sample()
                let temp = SMC.read("TC0P")?.number
                samples.append(MetricSample(time: Date(), temp: temp,
                                            load: last.total, mem: last.memoryUsedRatio,
                                            appCPU: nil, appMemMB: nil))
                Thread.sleep(forTimeInterval: 1.0)
            }
            if let summary = RecordingStore.save(label: label, appName: nil, appPID: nil,
                                                 start: start, end: Date(), samples: samples) {
                emit("""
                OK 录制完成：\(summary.label)
                   时长 \(Int(summary.duration)) 秒 · \(summary.sampleCount) 个采样
                   温度 平均 \(String(format: "%.1f", summary.avgTemp)) / 峰值 \(String(format: "%.1f", summary.maxTemp)) °C
                   负载 平均 \(String(format: "%.0f", summary.avgLoad * 100))%
                   文件 \(RecordingStore.fileURL(for: summary).path)
                """, printOutput: printOutput)
                return 0
            }
            emit("ERR 录制失败（没有采样点）", printOutput: printOutput)
            return 5

        case "rate", "interval":
            if args.count >= 2, let v = Int(args[1]), let r = SamplingRate(rawValue: v) {
                r.persist()
                emit("OK 采样间隔 = \(r.longLabel)（\(r.summary)）", printOutput: printOutput)
                return 0
            }
            let cur = SamplingRate.saved
            let options = SamplingRate.allCases.map { "\($0.rawValue)" }.joined(separator: " / ")
            emit("""
            当前采样间隔：\(cur.longLabel) — \(cur.summary)
            可选：\(options) 秒
            用法：asuscontrol rate <1|2|3|5>
            """, printOutput: printOutput)
            return args.count >= 2 ? 2 : 0

        case "fan", "fans":
            return fanCommand(Array(args.dropFirst()), printOutput: printOutput)

        case "model":
            return modelCommand(Array(args.dropFirst()), printOutput: printOutput)

        case "about", "version", "-v", "--version":
            emit("""
            \(AppInfo.name) \(AppInfo.displayVersion) (build \(AppInfo.build))
            作者      \(AppInfo.author) · 构建于 \(AppInfo.buildDateText)
            系统      \(AppInfo.osVersion)
            灵感参考  \(AppInfo.helperName)（\(AppInfo.helperAuthor)）\(AppInfo.helperURL)
            UI 灵感   \(AppInfo.uiInspiration)
            \(AppInfo.tagline)
            """, printOutput: printOutput)
            return 0

        case "nvidia", "driver", "gpu-update":
            let installed = NvidiaUpdate.installedVersion()
            var state = NvidiaUpdate.stateFromCache()
            var release = NvidiaUpdate.cachedRelease

            if args.count >= 2 {
                switch NvidiaUpdate.fetchLatestSync() {
                case .success(let latest):
                    release = latest
                    if let installed {
                        state = NvidiaUpdate.isNewer(latest.tag, than: installed)
                            ? .available(installed: installed, latest: latest.tag)
                            : .upToDate(installed: installed, latest: latest.tag)
                    }
                case .failure(let error):
                    state = .failed(installed: installed ?? "—",
                                    message: error.localizedDescription)
                }
            } else if installed == nil {
                state = .notInstalled
            }

            var lines: [String] = []
            lines.append("已安装      \(installed ?? "未检测到 NullMoth")")
            lines.append("GitHub 最新 \(release?.tag ?? "—（用 nvidia check 联网查询）")")
            if let r = release { lines.append("发布时间    \(r.publishedText)") }
            lines.append("状态        \(state.label)")
            if case .failed(_, let message) = state {
                lines.append("失败原因    \(message)")
            }
            if let r = release, !r.notes.isEmpty { lines.append("更新说明    \(r.notes)") }
            lines.append("发布页      \(release?.pageURL ?? NvidiaUpdate.releasesURL)")
            lines.append("网络代理    \(NvidiaUpdate.systemProxyText)")
            if let last = NvidiaUpdate.lastChecked {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm"
                lines.append("上次检查    \(f.string(from: last))")
            }
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return 0

        case "bench":
            let n = args.count >= 2 ? max(1, Int(args[1]) ?? 15) : 15
            var lines: [String] = ["每项执行 \(n) 次，单位毫秒（平均 / 峰值）："]
            func measure(_ name: String, _ body: () -> Void) {
                var worst = 0.0
                let t0 = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<n {
                    let a = DispatchTime.now().uptimeNanoseconds
                    body()
                    let d = Double(DispatchTime.now().uptimeNanoseconds - a) / 1e6
                    worst = max(worst, d)
                }
                let total = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                lines.append(String(format: "  %-26@ %7.3f / %7.3f", name as NSString, total / Double(n), worst))
            }
            measure("SMC 单键读取") { _ = SMC.read("TC0P") }
            measure("SMC 十键（传感器页）") {
                for k in ["TC0P", "TC0E", "TC0F", "F0Ac", "FNum", "LKSB", "LKSS", "ALV0", "B0RM", "B0FC"] {
                    _ = SMC.read(k)
                }
            }
            measure("Control.currentLevel") { _ = Control.currentLevel() }
            measure("SystemLoad.sample") { _ = SystemLoad.sample() }
            measure("ProcessSampler.sample") { _ = ProcessSampler.sample() }
            measure("Battery (IOKit)") { _ = SystemProbe.battery() }
            measure("HID 设备枚举") { _ = HIDBacklight.shared.probe() }
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return 0

        case "doctor":
            emit(doctorText(), printOutput: printOutput)
            return 0

        case "-h", "--help", "help":
            emit(helpText, printOutput: printOutput)
            return 0

        default:
            emit("ERR 未知命令: \(cmd)\n\n" + helpText, printOutput: printOutput)
            return 2
        }
    }

    // MARK: - 子命令

    // MARK: - 机型识别（安全相关：机型不匹配可能损坏硬件）

    /// 机型识别与 EC 配置选择。
    ///   vela model              显示硬件指纹、判定出的机型、当前选择、匹配状态、EC 配置
    ///   vela model probe        只打印原始指纹（排查识别问题 / 反馈新机型用）
    ///   vela model set <代码>   选择机型；与判定出的机型不一致时必须加 --i-understand
    ///   vela model clear        清除覆盖，恢复使用判定的机型
    private static func modelCommand(_ args: [String], printOutput: Bool) -> Int32 {
        let detection = ModelDetector.detect()
        let override = Prefs.string("fan.modelOverride")
        // 迁移：旧版本存过电池部件号（GA50358）当机型，这里同样不认它
        var effectiveOverride = override
        if let o = override, MachineModel.isLegacyBatteryCode(o) {
            effectiveOverride = nil
            Prefs.set(nil as String?, for: "fan.modelOverride")
            Prefs.set(false, for: "fan.mismatchAck")
        }
        let selected = (effectiveOverride ?? detection.code).trimmingCharacters(in: .whitespaces)
        let (profile, level) = ECProfiles.match(selected)

        let sub = args.first ?? ""

        switch sub {
        case "probe":
            var lines = ["硬件指纹（机型判定的原始输入）："]
            lines.append("  CPU         \(detection.fingerprint.cpu)")
            lines.append("  CPU 代号    \(detection.fingerprint.cpuCode.isEmpty ? "—（没抠出来）" : detection.fingerprint.cpuCode)")
            lines.append("  显卡        \(detection.fingerprint.gpus.isEmpty ? "—" : detection.fingerprint.gpus.joined(separator: " / "))")
            lines.append("  电池        \(Int(detection.fingerprint.batteryWh.rounded()))Wh（出厂设计容量）")
            if let n = detection.fingerprint.batteryName {
                lines.append("  电池部件号  \(n)（多机型共用，不作判定依据）")
            }
            if let s = detection.fingerprint.screen {
                lines.append("  主屏        \(s)")
            }
            lines.append("  内存        \(Int(detection.fingerprint.ramGB.rounded()))GB")
            lines.append("  厂商        \(detection.fingerprint.vendor.isEmpty ? "—" : detection.fingerprint.vendor)")
            lines.append("  SMBIOS      \(detection.fingerprint.smbiosModel)（OpenCore 覆盖过，不可信）")
            lines.append("")
            lines.append("判定结果：\(detection.code)（\(detection.name)）· \(detection.confidence.label)")
            if detection.scores.isEmpty {
                lines.append("没有任何已收录机型命中本机指纹。")
            } else {
                for s in detection.scores {
                    lines.append("  \(s.profile.modelCodes.first ?? s.profile.familyName) · \(s.points) 分")
                    for r in s.reasons { lines.append("      · \(r)") }
                }
            }
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return 0

        case "set":
            guard args.count >= 2 else {
                emit("用法：vela model set <机型代码> [--i-understand]", printOutput: printOutput)
                return 2
            }
            let code = args[1]
            let understand = args.contains("--i-understand")
            let nowMatched = code.trimmingCharacters(in: .whitespaces).uppercased()
                == detection.code.uppercased()
            if !nowMatched, !understand {
                if detection.confidence.isTrustworthy {
                    emit(ModelDisclaimer.body(selected: code, detected: detection.code), printOutput: printOutput)
                } else {
                    emit(ModelDisclaimer.bodyUndetected(selected: code), printOutput: printOutput)
                }
                emit("\n⚠️ 机型未获确认。确认风险后加 --i-understand 再执行：", printOutput: printOutput)
                emit("    vela model set \(code) --i-understand", printOutput: printOutput)
                return 2
            }
            Prefs.set(code, for: "fan.modelOverride")
            if !nowMatched { Prefs.set(true, for: "fan.mismatchAck") }
            emit("已选择机型 \(code)。重启 Vela X 后 GUI 会按此机型加载曲线。", printOutput: printOutput)
            return 0

        case "clear", "reset":
            Prefs.set(nil as String?, for: "fan.modelOverride")
            Prefs.set(false, for: "fan.mismatchAck")
            emit("已清除机型覆盖，恢复使用判定的 \(detection.code)。", printOutput: printOutput)
            return 0

        default:
            let matched = detection.confidence.isTrustworthy
                && selected.uppercased() == detection.code.uppercased()
            var lines = [
                "硬件指纹     \(detection.evidenceLine)",
                "推断机型     \(detection.code)（\(detection.name)）· \(detection.confidence.label)",
                "当前选择     \(selected)",
                "匹配状态     \(matched ? "匹配" : (detection.confidence.isTrustworthy ? "不匹配 ⚠️" : "未能自动识别，需手动核对"))",
                "EC 配置      " + (profile.map { "\($0.ecChip) · \($0.ecFirmware)" }
                                 ?? "未收录（无对应曲线，应用需谨慎）")
            ]
            for s in detection.scores {
                lines.append("候选         \(s.profile.modelCodes.first ?? s.profile.familyName) \(s.points) 分：\(s.reasons.joined(separator: "、"))")
            }
            if let p = profile {
                lines.append("收录级别     \(level == .verified ? "精确匹配" : "家族兼容（未本机验证）")")
                lines.append("曲线可信度   \(p.verification.label)")
            }
            if !matched {
                lines.append("")
                lines.append(detection.confidence.isTrustworthy
                             ? ModelDisclaimer.short(selected: selected, detected: detection.code)
                             : ModelDisclaimer.shortUndetected(selected: selected))
            }
            // 逆向未实机验证的机型：把验证步骤打出来，别让人直接下发
            if let caveat = profile?.verification.caveat {
                lines.append("")
                lines.append(caveat)
            }
            lines.append("")
            lines.append("（vela model probe 可查看完整指纹与逐条判定依据）")
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return 0
        }
    }

    // MARK: - 风扇（SMCAsusFan.kext 通道）
    /// 风扇档位：读状态免 root，下发曲线必须 root。
    /// GUI 点「应用」时会以管理员身份重新执行本程序，走的就是 `fan set`。
    private static func fanCommand(_ args: [String], printOutput: Bool) -> Int32 {
        let sub = args.first ?? "status"
        let ctrl = FanController()

        /// 按「当前生效机型」加载曲线：手动覆盖优先，否则用检测到的机型。
        /// 必须与 FanControl 的解析逻辑一致，否则 CLI 会静默用错机型的曲线
        /// （多机型共存时数值可能完全一样，看输出分辨不出来）。
        func currentModel() -> String {
            let detection = ModelDetector.detect().code
            // 旧版本存过电池部件号（GA50358）当机型，那种值不认，回落到指纹判定
            if let o = Prefs.string("fan.modelOverride"), !MachineModel.isLegacyBatteryCode(o) {
                return o.trimmingCharacters(in: .whitespaces)
            }
            return detection
        }

        func loadPresets() -> FanPresets? {
            do {
                return try FanPresets.load(for: currentModel())
            } catch {
                emit("ERR 读不到风扇曲线配置（机型 \(currentModel())）：\(error.localizedDescription)",
                     printOutput: printOutput)
                return nil
            }
        }

        switch sub {
        case "status":
            let r = ctrl.rpms()
            var lines = [
                "kext      " + (ctrl.isKextLoaded ? (ctrl.kextBuild ?? "已加载") : "未加载（AFMd 键不存在）"),
                "CPU 转速  \(r.cpu) RPM",
                "GPU 转速  \(r.gpu) RPM"
            ]
            if let m = ctrl.modeMirror { lines.append("FANM 镜像 \(m)") }
            if !FanController.isPrivileged { lines.append("（下发曲线需要 root）") }
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return ctrl.isKextLoaded ? 0 : 1

        case "list", "presets":
            guard let presets = loadPresets() else { return 1 }
            var lines: [String] = []
            // 打印实际读取的文件：多机型共存时，光看曲线数值分辨不出用的是哪份
            // （比如 G713PV 与 G513RM 的三档数值完全相同），必须让用户看到来源。
            if let src = presets.sourceURL?.path {
                lines.append("来源         \(src)")
            }
            if let dev = presets.deviceModel {
                lines.append("针对机型     \(dev)")
            }
            lines.append("")
            for name in FanControl.order {
                guard let p = presets.preset(name) else { continue }
                lines.append("\(name)\t\(p.label ?? "")\t\(curveSummary(p.cpu))")
            }
            emit(lines.isEmpty ? "配置里没有可用档位" : lines.joined(separator: "\n"),
                 printOutput: printOutput)
            return lines.isEmpty ? 1 : 0

        case "set":
            guard args.count >= 2 else {
                emit("ERR 用法：fan set <silent|balanced|performance>", printOutput: printOutput)
                return 2
            }
            let name = args[1]
            guard FanControl.order.contains(name) else {
                emit("ERR 未知档位：\(name)（可选：\(FanControl.order.joined(separator: " / "))）",
                     printOutput: printOutput)
                return 2
            }
            guard FanController.isPrivileged else {
                emit("ERR 需要 root 权限才能写 SMC 键", printOutput: printOutput)
                return 3
            }
            guard let presets = loadPresets(), let preset = presets.preset(name) else { return 1 }
            do {
                try ctrl.apply(preset.cpu, fan: .cpu)
                try ctrl.apply(preset.gpu, fan: .gpu)
                // 顺手把档位记到交付包工具用的同一个状态文件里，
                // 这样 `fanmode.py status` 和 GUI 显示的是同一个值
                recordToolState(name)
                emit("OK 已下发 \(name)（\(preset.label ?? "")）\nCPU \(curveSummary(preset.cpu))\nGPU \(curveSummary(preset.gpu))",
                     printOutput: printOutput)
                return 0
            } catch {
                emit("ERR 下发失败：\(error.localizedDescription)", printOutput: printOutput)
                return 4
            }

        default:
            emit("ERR 未知子命令：\(sub)\n用法：fan status | fan list | fan set <档位>",
                 printOutput: printOutput)
            return 2
        }
    }

    /// 与交付包里的 tools/fanmode.py 共用 /tmp/fanmode.state（尽力而为，失败不影响结果）
    private static func recordToolState(_ mode: String) {
        let payload: [String: Any] = [
            "mode": mode,
            "time": Int(Date().timeIntervalSince1970),
            "by": AppInfo.name
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/fanmode.state"))
        }
    }

    /// 曲线的一句话摘要，便于命令行核对
    private static func curveSummary(_ c: FanCurve) -> String {
        "温度 \(c.temp.map(String.init).joined(separator: "/")) · 占空比 \(c.duty.map(String.init).joined(separator: "/"))"
    }

    // MARK: - Aura 灯效

    /// 解析 #RRGGBB 或 "r,g,b"
    private static func parseColor(_ s: String) -> (r: Int, g: Int, b: Int)? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("#") {
            let hex = String(t.dropFirst())
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
            return (Int((v >> 16) & 0xFF), Int((v >> 8) & 0xFF), Int(v & 0xFF))
        }
        let parts = t.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3, parts.allSatisfy({ (0...255).contains($0) }) {
            return (parts[0], parts[1], parts[2])
        }
        return nil
    }

    private static func runAura(_ args: [String], printOutput: Bool) -> Int32 {
        let sub = args.first ?? "list"

        switch sub {
        case "list", "modes", "模式":
            var lines: [String] = ["Aura 灯效模式（报文第 4 字节）："]
            for m in AuraMode.allCases {
                lines.append(String(format: "  %2d  %@%@", m.rawValue, m.title,
                                    m.needsSecondColor ? "  (可设第二颜色)" : ""))
            }
            lines.append("")
            lines.append("速度: 0xE1 慢 / 0xEB 中 / 0xF5 快")
            lines.append("方向: 0 向右 / 1 向左 / 2 向上 / 3 向下")
            lines.append("用法: asuscontrol aura <mode> <#RRGGBB> [speed] [dir] [zone] [#RRGGBB2]")
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return 0

        case "scan", "dev", "设备":
            let pids = AuraEffects.shared.probe()
            emit(pids.isEmpty ? "没有找到 ASUS Aura HID 控制器"
                               : "Aura 控制器 PID: " + pids.map { String(format: "0x%04X", $0) }.joined(separator: ", "),
                  printOutput: printOutput)
            return pids.isEmpty ? 4 : 0

        case "probe", "diag", "诊断":
            // 一键机型诊断：适配其他机型时让用户跑这个并回传输出
            emit(AuraEffects.shared.diagnosticReport(), printOutput: printOutput)
            return 0

        case "raw", "rawsend":
            // raw <hex bytes...>
            guard args.count >= 2 else {
                emit("ERR 用法: aura raw <hex> [hex ...]   例如: aura raw 5D B3 00 03 FF 00 00 EB 00 00", printOutput: printOutput)
                return 2
            }
            var bytes: [UInt8] = []
            for a in args.dropFirst() {
                guard let v = UInt8(a.replacingOccurrences(of: "0x", with: ""), radix: 16) else {
                    emit("ERR 不是合法的十六进制字节: \(a)", printOutput: printOutput)
                    return 2
                }
                bytes.append(v)
            }
            let rc = AuraEffects.shared.raw(bytes)
            emit("已发送 \(bytes.count) 字节 → 0x\(String(UInt32(bitPattern: rc), radix: 16))", printOutput: printOutput)
            return rc == kIOReturnSuccess ? 0 : 5

        default:
            break
        }

        // aura <mode> <color> [speed] [dir] [zone] [color2]
        guard let modeValue = Int(sub), let mode = AuraMode(rawValue: modeValue) else {
            emit("""
            ERR 未知模式「\(sub)」。用 `asuscontrol aura list` 看可用模式。
            用法: asuscontrol aura <mode> <#RRGGBB> [speed 0|1|2] [dir 0-3] [zone 0-4] [#RRGGBB2]
            """, printOutput: printOutput)
            return 2
        }
        guard args.count >= 2, let c1 = parseColor(args[1]) else {
            emit("""
            ERR 需要颜色。用法: asuscontrol aura \(modeValue) <#RRGGBB> [speed 0|1|2] [dir 0-3] [zone 0-4] [#RRGGBB2]
            例:   asuscontrol aura \(modeValue) #FF0000
            """, printOutput: printOutput)
            return 2
        }

        var effect = AuraEffect()
        effect.mode = mode
        effect.color1 = c1
        if args.count >= 3, let sp = Int(args[2]), let s = AuraSpeed(rawValue: [0xE1, 0xEB, 0xF5][max(0, min(2, sp))]) {
            effect.speed = s
        }
        if args.count >= 4, let d = Int(args[3]), let dir = AuraDirection(rawValue: d) {
            effect.direction = dir
        }
        if args.count >= 5, let z = Int(args[4]) { effect.zone = z }
        if args.count >= 6, let c2 = parseColor(args[5]) { effect.color2 = c2 }

        if let err = AuraEffects.shared.apply(effect) {
            emit("""
            ERR \(err)
            若提示权限问题：系统设置 → 隐私与安全性 → 输入监控 → 勾选 Vela X → 重启本程序。
            """, printOutput: printOutput)
            return 5
        }

        let msg = effect.message.prefix(13).map { String(format: "%02X", $0) }.joined(separator: " ")
        emit("""
        OK 灯效已应用：\(mode.title) · 主色 #\(String(format: "%02X%02X%02X", c1.r, c1.g, c1.b)) · 速度 \(effect.speed.title) · 方向 \(effect.direction.title)
           报文 \(msg) ...
        """, printOutput: printOutput)
        return 0
    }

    private static func runSMC(_ args: [String], printOutput: Bool) -> Int32 {
        guard let sub = args.first else {
            emit("ERR 用法: smc list | read KEY | write KEY HEX", printOutput: printOutput)
            return 2
        }
        switch sub {
        case "list":
            let keys = SMC.allKeys()
            var lines = ["共 \(keys.count) 个键："]
            for chunk in stride(from: 0, to: keys.count, by: 9) {
                let slice = keys[chunk..<min(chunk + 9, keys.count)]
                lines.append("  " + slice.joined(separator: "  "))
            }
            emit(lines.joined(separator: "\n"), printOutput: printOutput)
            return 0

        case "read":
            guard args.count >= 2 else {
                emit("ERR 用法: smc read KEY", printOutput: printOutput)
                return 2
            }
            guard let r = SMC.read(args[1]) else {
                emit("ERR 无法读取 \(args[1])", printOutput: printOutput)
                return 4
            }
            let value = r.number.map { String(format: "%.3f", $0) } ?? "—"
            emit("\(r.key)  type=\(r.type)  size=\(r.size)  value=\(value)  raw=\(r.hex)",
                 printOutput: printOutput)
            return 0

        case "write":
            guard args.count >= 3 else {
                emit("ERR 用法: smc write KEY HEXBYTES", printOutput: printOutput)
                return 2
            }
            let hex = args[2]
            var bytes: [UInt8] = []
            var i = hex.startIndex
            while i < hex.endIndex, let next = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) {
                if let b = UInt8(hex[i..<next], radix: 16) { bytes.append(b) }
                i = next
            }
            let rc = SMC.write(args[1], bytes: bytes)
            if rc == 0 { emit("OK \(args[1]) <- \(hex)", printOutput: printOutput); return 0 }
            if rc == 1 { emit("ERR 需要 root 权限", printOutput: printOutput); return 3 }
            emit("ERR 写入失败: \(smc_last_kern_return())", printOutput: printOutput)
            return 5

        default:
            emit("ERR 未知子命令: \(sub)", printOutput: printOutput)
            return 2
        }
    }

    // MARK: - 文本输出

    static var helpText: String {
        """
        Vela X for macOS —— 基于 AppleSMC 的轻量控制工具

        用法: AsusControl <命令> [参数]

          status              机器与状态概览
          sensors             传感器实时读数
          load                CPU 负载 / 每线程占用 / 热压力（无需 kext）
          rate [1|2|3|5]      查看 / 设置采样间隔（默认 2 秒，最长 5 秒）
          nvidia [check]      NVIDIA（NullMoth）驱动版本，check 联网查最新版
          about               版本、作者与致谢
          bench [n]           各子系统单次耗时（用来确认卡顿来源）
          top [mem]           进程排行（CPU 或内存），无需 root
          record <秒> [标签]  录制一段温度/负载/内存，写成 CSV
          kbd <0-16>          设置键盘背光（0=关闭，需 root）
          aura list           列出 RGB 灯效模式
          aura <模式> <#色>   设置键盘 RGB 灯效，如: aura 3 #FF0000
          aura scan          扫描 ASUS Aura HID 控制器
          aura raw <hex...>  原始发送灯效报文（调试）
          fan status          风扇转速 + SMCAsusFan kext 状态
          fan list            列出风扇曲线档位（静音/平衡/性能）
          fan set <档位>       下发风扇曲线（需 root）
          model               显示检测到的机型 / 当前选择 / 匹配状态
          model set <代码>    手动选择机型（不匹配时须加 --i-understand）
          smc list            列出全部 SMC 键
          smc read <KEY>      读取某个 SMC 键
          smc write <KEY> <HEX>  写入 SMC 键（需 root）
          doctor              能力诊断（哪些功能在 macOS 上可用）

        不带参数直接运行会打开图形界面。
        """
    }

    private static func statusText() -> String {
        let hw = SystemProbe.hardware()
        let bat = SystemProbe.battery()
        let kext = SystemProbe.kexts()
        let temp = SMC.read("TC0P")?.number
        let kbdMode = Control.mode
        let kbd = Control.currentLevel()
        var lines: [String] = []
        lines.append("机型     \(hw.productName)  [\(hw.modelCode) · \(hw.nameSource)]")
        lines.append("CPU      \(hw.cpu)  (\(hw.cores) 线程)")
        lines.append("内存     \(String(format: "%.0f", hw.ramGB)) GB")
        lines.append("系统     \(hw.osVersion)")
        for g in hw.gpus { lines.append("显卡     \(g.name) — \(g.driver)") }
        lines.append("")
        lines.append("CPU 温度 \(temp.map { String(format: "%.1f °C", $0) } ?? "不可用")")
        lines.append("风扇     \(fanDescription())")
        _ = SystemLoad.sample()
        usleep(200_000)
        let load = SystemLoad.sample()
        lines.append(String(format: "负载     %.0f%%  (热压力 %@)", load.total * 100, load.thermalText))
        if kbdMode.maxLevel > 0 {
            lines.append("背光     \(kbd)/\(kbdMode.maxLevel)  \u{2190} \(kbdMode.label)")
        } else if Control.hidBlocked {
            lines.append("背光     不可用（Aura HID 待授「输入监控」权限）")
        } else {
            lines.append("背光     不可用")
        }
        if bat.present {
            lines.append("电池     \(bat.charge)%  健康 \(String(format: "%.0f%%", bat.healthPercent))  循环 \(bat.cycleCount) 次\(bat.externalPower ? "  (已接电源)" : "")")
        }
        lines.append("驱动     \(kext.summary)")
        return lines.joined(separator: "\n")
    }

    private static func permissionText(_ s: HIDBacklight.PermissionState) -> String {
        switch s {
        case .granted: return "granted（可用）"
        case .needsRestart: return "needsRestart（已授权但未生效）"
        case .denied: return "denied（被拒绝）"
        case .notDetermined: return "notDetermined（未申请）"
        case .busy: return "busy（设备被占用）"
        case .noDevice: return "noDevice（没有 Aura 控制器）"
        }
    }

    private static func kernText(_ rc: kern_return_t) -> String {
        rc == kIOReturnSuccess ? "成功" : String(format: "0x%08X", UInt32(bitPattern: rc))
    }

    private static func loadText(_ l: SystemLoadSnapshot) -> String {
        var lines: [String] = []
        lines.append(String(format: "CPU 总占用  %.1f%%   (%d 线程)", l.total * 100, l.perCore.count))
        let coreText = l.perCore.enumerated()
            .map { String(format: "%d:%.0f%%", $0.offset, $0.element * 100) }
            .joined(separator: "  ")
        lines.append("每线程      " + coreText)
        lines.append(String(format: "负载均值    %.2f / %.2f / %.2f", l.load1, l.load5, l.load15))
        lines.append("内核热压力  \(l.thermalText)")
        lines.append(String(format: "内存占用    %.1f%%", l.memoryUsedRatio * 100))
        lines.append("数据来源    Mach 内核计数器（不依赖 kext）")
        return lines.joined(separator: "\n")
    }

    private static func sensorsText() -> String {
        let fanExposed = (SMC.read("FNum")?.number ?? 0) > 0
        var lines: [String] = []
        for meta in SMCKeyCatalog.interesting {
            // 风扇未被 VirtualSMC 暴露时，F0Ac 的固定占位值没有意义，直接标注不可用
            if meta.key == "F0Ac" && !fanExposed {
                lines.append(String(format: "%-6@ %-16@ %10@ %@",
                                    meta.key as NSString, meta.name as NSString,
                                    "不可用" as NSString, "VirtualSMC FNum=0" as NSString))
                continue
            }
            guard let r = SMC.read(meta.key) else { continue }
            let value = r.number.map { String(format: "%.\(meta.decimals)f", $0) } ?? r.hex
            lines.append(String(format: "%-6@ %-16@ %10@ %@",
                                meta.key as NSString, meta.name as NSString,
                                value as NSString, meta.unit))
        }
        return lines.isEmpty ? "没有可用的传感器" : lines.joined(separator: "\n")
    }

    private static func fanDescription() -> String {
        if let rpm = FanProbe.rpm, FanProbe.isAvailable {
            return String(format: "%.0f RPM", rpm)
        }
        let raw = SMC.read("F0Ac")?.number ?? 0
        return String(format: "不可用（FNum=%d，F0Ac=%.0f 为占位值）", FanProbe.count, raw)
    }

    private static func doctorText() -> String {
        var lines: [String] = ["Vela X 能力诊断", String(repeating: "─", count: 46)]
        for cap in Capabilities.all() {
            lines.append("[\(cap.status.badge)] \(cap.title)")
            lines.append("     \(cap.summary)")
        }
        lines.append(String(repeating: "─", count: 46))
        let kbdModeLine: String
        if Control.mode.maxLevel > 0 {
            kbdModeLine = "\(Control.mode.label)（0–\(Control.mode.maxLevel)）"
        } else if Control.hidBlocked {
            kbdModeLine = "Aura HID 已找到，但被系统拦截（缺「输入监控」权限）"
        } else {
            kbdModeLine = "不可用（无 SKBV、无 Aura HID）"
        }
        lines.append("背光通道: \(kbdModeLine)")
        lines.append("输入监控权限: \(HIDBacklight.listenPermission.rawValue)")
        lines.append("IOReport: 无 CPU/能耗/温度组（本机仅设备级计数器）")
        lines.append("用户态内存访问: 不可用（无 /dev/mem、无 IOPort 客户端，MSR/SMN 需 ring0）")
        lines.append("AsusSMC SKBV: \(Control.asusSMCBacklightSupported ? "已识别" : "缺失")")
        lines.append("采样间隔: \(SamplingRate.saved.longLabel)（可选 1/2/3/5 秒）")
        lines.append("NVIDIA 驱动: \(NvidiaUpdate.installedVersion() ?? "未安装")（nvidia check 查最新版）")
        lines.append("系统代理: \(NvidiaUpdate.systemProxyText)")
        lines.append("背光写入: \(HIDBacklight.shared.writeMethodText)")
        lines.append("SMC 键数: \(SMC.allKeys().count)")
        lines.append("驱动: \(SystemProbe.kexts().summary)")
        return lines.joined(separator: "\n")
    }
}
