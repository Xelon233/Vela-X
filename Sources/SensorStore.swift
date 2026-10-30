//
//  SensorStore.swift
//  采样引擎 + 状态中枢
//
//  线程模型：
//    · 采样队列（串行，.utility）负责所有 IOKit / libproc / Mach 调用
//    · 主线程只做「把一次采样结果写回 @Published」，不碰任何系统调用
//
//  为什么这样改：Control.currentLevel() 每次要枚举全部 IOHID 设备并尝试 open，
//  单次 13 ms（峰值 21 ms），原来每秒在主线程跑一次，必然每秒掉一帧。
//  现在这类调用要么被缓存，要么移到后台队列，主线程一轮只剩微秒级赋值。
//

import Foundation
import Combine

/// 一次采样的不可变结果（后台队列生产，主线程消费）
struct SampleFrame {
    var seq: Int = 0
    var at = Date()
    var temp: Double?
    var fanRPM: Double?
    var fanRPMGPU: Double?
    var fanCount: Int = 0
    var fanOK = false
    var load = SystemLoadSnapshot()
    var battery: BatteryInfo?
    var tiles: [String: SMCReading]?
    var processes: [ProcSample]?
    var net = NetSpeedSnapshot()
    var gpuUsage: Double?
    var gpuTemp: Double?
    var powerWatts: Double?
    /// CPU 实时频率（GHz），来自 AMDRyzenCPUPowerManagement 用户客户端；nil = 没采到
    var cpuFreqGHz: Double?
    var disk: DiskInfo?
}

final class SensorStore: ObservableObject {
    static let shared = SensorStore()

    // 硬件 / 静态信息
    @Published var hardware = HardwareInfo()
    @Published var battery = BatteryInfo()
    @Published var disk = DiskInfo()
    @Published var kexts = KextState()
    @Published var capabilities: [Capability] = []

    // 采样数据（后台产出 → 主线程批量写入）
    //
    // 这些字段故意不用 @Published：一轮采样会同时改十几个值，
    // 每个 @Published 各发一次 objectWillChange，SwiftUI 就会把整页重排十几遍
    // （实测每帧 ~190 ms CPU）。改成普通属性 + 帧首手动发一次通知。
    private(set) var cpuTemp: Double?
    private(set) var tempHistory: [Double] = []
    private(set) var freqHistory: [Double] = []
    private(set) var powerHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var fanRPM: Double?
    private(set) var fanRPMGPU: Double?
    private(set) var fanCount = 0
    private(set) var fanAvailable = false
    private(set) var gpuTemp: Double?
    private(set) var load = SystemLoadSnapshot()
    private(set) var loadHistory: [Double] = []
    private(set) var tiles: [String: SMCReading] = [:]
    private(set) var sampleCount = 0
    private(set) var lastUpdate = Date()

    // 菜单栏可选项（见 MenuMetrics.swift）
    //
    // 网速每帧都采（getifaddrs 很便宜）；显卡占用要遍历 IORegistry，降到每 5 帧一次；
    // 功耗读 SMC 键很便宜，但只在探测到有这个键时才读。
    private(set) var netSpeed = NetSpeedSnapshot()
    private(set) var gpuUsage: Double?
    private(set) var powerWatts: Double?
    private(set) var cpuFreq = CPUFrequencyInfo()

    // 应用级监控
    private(set) var processes: [ProcSample] = []
    private(set) var history: [MetricSample] = []

    // 录制
    private(set) var recording: ActiveRecording?
    @Published var recordings: [RecordingSummary] = []
    private(set) var recordingTick: Int = 0          // 仅用于驱动界面刷新计时

    // 键盘背光
    @Published var kbdLevel: Int = 0
    @Published var kbdMaxLevel: Int = 0
    @Published var kbdMode: BacklightMode = .none
    @Published var kbdPermission: HIDBacklight.PermissionState = .notDetermined
    @Published var kbdBlockedByPermission = false
    @Published var kbdAvailable = false
    @Published var kbdBusy = false
    @Published var kbdError: String?
    @Published var kbdAssumed = false   // 授权期间乐观显示

    // NVIDIA（NullMoth）驱动更新
    @Published private(set) var nvidiaUpdate: NvidiaUpdateState = .unknown
    @Published private(set) var nvidiaRelease: NvidiaRelease?

    // 全键表
    @Published var readings: [SMCReading] = []
    @Published var keyNames: [String] = []
    @Published var smcReady = false

    /// 采样间隔（改动会立即重建定时器并持久化）
    @Published private(set) var samplingRate: SamplingRate = .saved

    // MARK: 采样线程私有状态（只在 sampleQueue 上访问）

    private struct SamplerConfig {
        var interval: TimeInterval = 2
        var batteryPeriod: TimeInterval = 15
        var diskPeriod: TimeInterval = 15
        var processPeriod: TimeInterval = 2
        var wantTiles = false
        var pageProcesses = false
        var recordingPID: Int32?

        var wantProcesses: Bool { pageProcesses || recordingPID != nil }
    }

    private let sampleQueue = DispatchQueue(label: "dev.vela.sampler", qos: .utility)
    private var sensorTimer: DispatchSourceTimer?
    private var config = SamplerConfig()
    private var seq = 0
    private var lastBattery = Date.distantPast
    private var lastDisk = Date.distantPast
    private var lastProcess = Date.distantPast
    private var collecting = false

    private var kbdDebounce: Timer?
    private var pendingKbd: Int?

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard sensorTimer == nil else { return }
        smcReady = SMC.available
        loadStaticInfo()
        recordings = RecordingStore.loadIndex()
        restartTimer()
        nvidiaUpdate = NvidiaUpdate.stateFromCache()
        nvidiaRelease = NvidiaUpdate.cachedRelease
        if NvidiaUpdate.needsAutoCheck { checkNvidiaUpdate() }
    }

    /// 快照 / 自检用：临时提高采样率但不写入偏好
    func overrideRate(_ rate: SamplingRate) {
        guard rate != samplingRate else { return }
        samplingRate = rate
        restartTimer()
    }

    func setSamplingRate(_ rate: SamplingRate) {
        guard rate != samplingRate else { return }
        samplingRate = rate
        rate.persist()
        trimHistory()
        restartTimer()
    }

    private func restartTimer() {
        let seconds = samplingRate.rawValue
        let rate = samplingRate
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.config.interval = TimeInterval(seconds)
            self.config.batteryPeriod = rate.batteryPeriod
            self.config.diskPeriod = rate.batteryPeriod
            self.config.processPeriod = rate.processPeriod
            self.sensorTimer?.cancel()

            let timer = DispatchSource.makeTimerSource(queue: self.sampleQueue)
            timer.schedule(deadline: .now() + 0.05,
                           repeating: .milliseconds(seconds * 1000),
                           leeway: .milliseconds(seconds >= 3 ? 400 : 120))
            timer.setEventHandler { [weak self] in self?.collect() }
            timer.resume()
            self.sensorTimer = timer
        }
    }

    private func trimHistory() {
        let tempCap = samplingRate.tempCapacity
        if tempHistory.count > tempCap { tempHistory.removeFirst(tempHistory.count - tempCap) }
        if loadHistory.count > tempCap { loadHistory.removeFirst(loadHistory.count - tempCap) }
        if freqHistory.count > tempCap { freqHistory.removeFirst(freqHistory.count - tempCap) }
        if powerHistory.count > tempCap { powerHistory.removeFirst(powerHistory.count - tempCap) }
        if gpuHistory.count > tempCap { gpuHistory.removeFirst(gpuHistory.count - tempCap) }
        let histCap = samplingRate.historyCapacity
        if history.count > histCap { history.removeFirst(history.count - histCap) }
    }

    private func loadStaticInfo() {
        let store = self
        DispatchQueue.global(qos: .userInitiated).async {
            let hw = SystemProbe.hardware()
            let kext = SystemProbe.kexts()
            let bat = SystemProbe.battery()
            let caps = Capabilities.all(gpus: hw.gpus)
            let names = SMC.allKeys()
            // 菜单栏那几项能不能用，开机探一次就够（不会随运行变化）
            MetricProbe.shared.probeIfNeeded()
            let freq = MetricProbe.shared.cpuFreq
            let gpu = MetricProbe.shared.gpuUsage
            let gpuTemp = MetricProbe.shared.gpuTemp
            DispatchQueue.main.async {
                store.hardware = hw
                store.kexts = kext
                store.battery = bat
                store.capabilities = caps
                store.keyNames = names
                store.cpuFreq = freq
                store.gpuUsage = gpu
                store.gpuTemp = gpuTemp
                // powerWatts / cpuFreq.liveGHz 每帧由 AMDRyzenProbe 填充（需 kext）
                let mode = Control.mode
                store.kbdMode = mode
                store.kbdMaxLevel = mode.maxLevel
                store.kbdAvailable = mode.maxLevel > 0
                store.kbdPermission = Control.permissionState
                store.kbdBlockedByPermission = Control.hidBlocked
                store.kbdLevel = Control.currentLevel()
                store.maybeRequestHIDPermission()
            }
        }
    }

    /// 首次发现「Aura HID 被系统拦截」时申请一次输入监控权限，
    /// 这样程序才会被登记进 系统设置 → 隐私与安全性 → 输入监控 的列表里
    private func maybeRequestHIDPermission() {
        guard Control.hidBlocked,
              HIDBacklight.listenPermission == .unknown else { return }
        let key = "hid.permissionAsked"
        if Prefs.bool(key) { return }
        Prefs.set(true, for: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            _ = HIDBacklight.requestPermission()
        }
    }

    // MARK: - 采集（后台队列）

    private func collect() {
        guard !collecting else { return }
        collecting = true
        defer { collecting = false }

        seq += 1
        var frame = SampleFrame(seq: seq, at: Date())

        frame.temp = SMC.read("TC0P")?.number

        frame.fanCount = FanProbe.count
        if let rpm = FanProbe.rpm {
            frame.fanRPM = rpm
            frame.fanOK = true
        }
        frame.fanRPMGPU = FanProbe.gpuRPM

        frame.load = SystemLoad.sample()
        frame.net = NetSpeed.sample()

        // 显卡占用/温度要遍历 IORegistry 并拷属性字典，比其它项重，降频到每 5 帧
        if (MetricProbe.shared.gpuUsage != nil || MetricProbe.shared.gpuTemp != nil), seq % 5 == 0 {
            let g = GPUProbe.stats()
            frame.gpuUsage = g.usage
            frame.gpuTemp = g.temperature
        }
        // CPU 功耗 / 频率来自 AMDRyzenCPUPowerManagement 用户客户端（selector 4），
        // 普通用户态即可读，不需要 root。kext 没装时 amdAvailable=false，跳过。
        if MetricProbe.shared.amdAvailable {
            let s = AMDRyzenProbe.shared.sample()
            frame.powerWatts = s.powerWatts
            frame.cpuFreqGHz = s.avgFreqGHz
        }

        if config.wantTiles {
            var dict: [String: SMCReading] = [:]
            dict.reserveCapacity(SMCKeyCatalog.interesting.count)
            for meta in SMCKeyCatalog.interesting {
                if let r = SMC.read(meta.key) { dict[meta.key] = r }
            }
            frame.tiles = dict
        }

        if frame.at.timeIntervalSince(lastBattery) >= config.batteryPeriod {
            lastBattery = frame.at
            frame.battery = SystemProbe.battery()
        }

        if frame.at.timeIntervalSince(lastDisk) >= config.diskPeriod {
            lastDisk = frame.at
            frame.disk = DiskInfo.current()
        }

        if config.wantProcesses,
           frame.at.timeIntervalSince(lastProcess) >= config.processPeriod {
            lastProcess = frame.at
            frame.processes = ProcessSampler.sample()
        }

        DispatchQueue.main.async { [weak self] in self?.apply(frame) }
    }

    /// 上一轮推给界面的「可见值签名」。0 表示还没推过，第一帧必须放行。
    private var lastVisibleSignature: UInt64 = 0

    /// 把这一帧里「会改变像素」的量按显示精度抹零后揉成一个整数（FNV-1a）。
    /// 只取界面上真的会显示、且精度有限的项：温度 0.1 °C、负载 0.5%、网速 0.5 KB/s……
    /// 传感器页（tiles）和监控页（processes）要逐项刷新，有这两类数据不做合并。
    private func visibleSignature(_ frame: SampleFrame) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x0000_0100_0000_01b3 }
        func mixRounded(_ v: Double?, _ scale: Double) {
            guard let v else { mix(0xFFFF_FFFF); return }
            mix(UInt64(bitPattern: Int64((v * scale).rounded())))
        }

        mixRounded(frame.temp, 10)              // 0.1 °C
        mixRounded(frame.fanRPM, 0.1)           // 10 RPM
        mixRounded(frame.fanRPMGPU, 0.1)
        mixRounded(frame.load.total, 500)       // 0.5 %
        mixRounded(frame.load.memoryUsedRatio, 500)
        mixRounded(frame.load.swapUsed > 0 ? Double(frame.load.swapUsed) / 1e6 : nil, 10)
        mixRounded(frame.gpuUsage, 1)
        mixRounded(frame.gpuTemp, 1)
        mixRounded(frame.powerWatts, 1)
        mixRounded(frame.cpuFreqGHz, 100)     // 0.01 GHz
        mixRounded(frame.net.down, 2)           // 0.5 KB/s
        mixRounded(frame.net.up, 2)
        mix(UInt64(frame.load.perCore.count))
        for core in frame.load.perCore.prefix(32) { mixRounded(core, 100) }
        if let b = frame.battery {
            mix(UInt64(bitPattern: Int64(b.charge)))
            mix(b.charging ? 1 : 2)
            mix(b.externalPower ? 3 : 4)
        }
        if let d = frame.disk {
            mix(UInt64(bitPattern: d.usedBytes))
            mix(UInt64(d.totalBytes))
        }
        if frame.tiles != nil { mix(0xA11CE) }
        if frame.processes != nil { mix(0xBEEF) }
        return h
    }

    private func apply(_ frame: SampleFrame) {
        // 一整帧只通知一次，避免十几次重排；
        // 而且「值没变就不通知」—— 采样间隔 1 秒时，温度、负载、内存大多只是
        // 在小数点后抖动，四舍五入到显示精度后屏幕上一个像素都不会变，
        // 却要重绘整窗玻璃 + 十几张卡片。签名相同就直接跳过，空闲时 CPU 归零。
        let signature = visibleSignature(frame)
        // 每 10 帧兜底放行一次：界面上的「采样点 / 时间戳」这类派生信息偶尔要靠
        // 刷新才会动，不能让它们长时间停住。
        let changed = signature != lastVisibleSignature || sampleCount % 10 == 0
        lastVisibleSignature = signature
        if changed { objectWillChange.send() }

        if let t = frame.temp {
            cpuTemp = t
            tempHistory.append(t)
            let cap = samplingRate.tempCapacity
            if tempHistory.count > cap { tempHistory.removeFirst(tempHistory.count - cap) }
        }

        if frame.fanCount > 0 { fanCount = frame.fanCount }
        if frame.fanOK {
            fanRPM = frame.fanRPM
            fanRPMGPU = frame.fanRPMGPU
            fanAvailable = true
        } else if fanAvailable {
            fanAvailable = false
            fanRPM = nil
            fanRPMGPU = nil
        }

        load = frame.load
        netSpeed = frame.net
        if let g = frame.gpuUsage {
            gpuUsage = g
            gpuHistory.append(g)
            let cap = samplingRate.tempCapacity
            if gpuHistory.count > cap { gpuHistory.removeFirst(gpuHistory.count - cap) }
        }
        if let t = frame.gpuTemp { gpuTemp = t }
        if let w = frame.powerWatts {
            powerWatts = w
            powerHistory.append(w)
            let cap = samplingRate.tempCapacity
            if powerHistory.count > cap { powerHistory.removeFirst(powerHistory.count - cap) }
        }
        if let ghz = frame.cpuFreqGHz {
            cpuFreq.liveGHz = ghz
            freqHistory.append(ghz)
            let cap = samplingRate.tempCapacity
            if freqHistory.count > cap { freqHistory.removeFirst(freqHistory.count - cap) }
        }
        if frame.load.sampled {
            loadHistory.append(frame.load.total)
            let cap = samplingRate.tempCapacity
            if loadHistory.count > cap { loadHistory.removeFirst(loadHistory.count - cap) }
        }

        if let b = frame.battery { battery = b }
        if let d = frame.disk { disk = d }
        if let d = frame.tiles { tiles = d }
        if let list = frame.processes { processes = list }

        sampleCount += 1

        // 背光档位：HID 通道读 Prefs、SMC 通道读一个键，都很便宜，放主线程即可
        if !kbdBusy, kbdMaxLevel > 0, sampleCount % 3 == 1 {
            let lv = Control.currentLevel()
            if lv != kbdLevel { kbdLevel = lv; kbdAssumed = false }
        }
        lastUpdate = frame.at

        let sample = MetricSample(
            time: frame.at,
            temp: cpuTemp,
            load: frame.load.sampled ? frame.load.total : (history.last?.load ?? 0),
            mem: frame.load.memoryUsedRatio,
            appCPU: nil,
            appMemMB: nil,
            freqGHz: frame.cpuFreqGHz,
            power: frame.powerWatts
        )
        appendHistory(sample)
        appendRecording(sample)

        // 通道不可用时每 5 个采样点复查一次（模式带 60 秒缓存，不会每次都枚举设备）
        if kbdMaxLevel == 0, sampleCount % 5 == 0 {
            let mode = Control.mode
            let permission = Control.permissionState
            if permission != kbdPermission { kbdPermission = permission }
            if mode.maxLevel > 0 {
                kbdMode = mode
                kbdMaxLevel = mode.maxLevel
                kbdAvailable = true
                kbdBlockedByPermission = false
                kbdLevel = Control.currentLevel()
            } else {
                kbdBlockedByPermission = (permission == .denied || permission == .needsRestart)
            }
        }
    }

    /// 重新检测背光通道与输入监控权限（授权/重启后可手动触发）
    func recheckBacklightPermission() {
        Control.invalidateMode()
        DispatchQueue.global(qos: .userInitiated).async {
            let mode = Control.mode
            let permission = Control.permissionState
            DispatchQueue.main.async {
                self.kbdMode = mode
                self.kbdPermission = permission
                self.kbdMaxLevel = mode.maxLevel
                self.kbdAvailable = mode.maxLevel > 0
                self.kbdBlockedByPermission = (permission == .denied || permission == .needsRestart)
                self.kbdLevel = Control.currentLevel()
                self.capabilities = Capabilities.all(gpus: self.hardware.gpus,
                                                     nvidia: self.nvidiaUpdate)
            }
        }
    }

    // MARK: - NVIDIA 驱动更新

    func checkNvidiaUpdate() {
        guard !nvidiaUpdate.isChecking else { return }
        let installed = NvidiaUpdate.installedVersion()
        guard let installed else {
            nvidiaUpdate = .notInstalled
            return
        }
        nvidiaUpdate = .checking
        NvidiaUpdate.fetchLatest(completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let release):
                self.nvidiaRelease = release
                self.nvidiaUpdate = NvidiaUpdate.isNewer(release.tag, than: installed)
                    ? .available(installed: installed, latest: release.tag)
                    : .upToDate(installed: installed, latest: release.tag)
            case .failure(let error):
                self.nvidiaUpdate = .failed(installed: installed,
                                            message: error.localizedDescription)
            }
            // 能力矩阵里有一行要跟着更新
            self.capabilities = Capabilities.all(gpus: self.hardware.gpus,
                                                 nvidia: self.nvidiaUpdate)
        }, onEnrich: { [weak self] release in
            // 后台补到的发布说明，只更新展示，不改变版本状态
            self?.nvidiaRelease = release
        })
    }

    // MARK: - 按页面启用采样（不看监控页就不枚举进程）

    func setTilesActive(_ active: Bool) {
        sampleQueue.async { self.config.wantTiles = active }
    }

    func setProcessSamplingActive(_ active: Bool) {
        let pid = recording?.appPID
        sampleQueue.async {
            self.config.pageProcesses = active
            self.config.recordingPID = pid
        }
    }

    /// 读取全部 SMC 键（诊断页用）
    func reloadAllReadings(completion: (() -> Void)? = nil) {
        let store = self
        DispatchQueue.global(qos: .userInitiated).async {
            var list: [SMCReading] = []
            for name in store.keyNames {
                if let r = SMC.read(name) { list.append(r) }
            }
            let sorted = list.sorted { $0.key < $1.key }
            DispatchQueue.main.async {
                store.readings = sorted
                completion?()
            }
        }
    }

    // MARK: - 历史与录制

    private func appendHistory(_ sample: MetricSample) {
        var s = sample
        if let pid = recording?.appPID,
           let p = ProcessSampler.findByPID(processes, pid: pid) {
            s = MetricSample(time: sample.time, temp: sample.temp, load: sample.load,
                             mem: sample.mem, appCPU: p.cpu, appMemMB: p.memoryMB,
                             freqGHz: sample.freqGHz, power: sample.power)
        }
        history.append(s)
        let cap = samplingRate.historyCapacity
        if history.count > cap { history.removeFirst(history.count - cap) }
    }

    private func appendRecording(_ sample: MetricSample) {
        guard var rec = recording else { return }
        var s = sample
        if let pid = rec.appPID, let p = ProcessSampler.findByPID(processes, pid: pid) {
            s = MetricSample(time: sample.time, temp: sample.temp, load: sample.load,
                             mem: sample.mem, appCPU: p.cpu, appMemMB: p.memoryMB,
                             freqGHz: sample.freqGHz, power: sample.power)
        }
        rec.samples.append(s)
        recording = rec
        recordingTick &+= 1
    }

    func startRecording(label: String, appName: String?, appPID: Int32?) {
        recording = ActiveRecording(label: label.isEmpty ? "未命名录制" : label,
                                    appName: appName,
                                    appPID: appPID,
                                    start: Date())
        recordingTick = 0
        sampleQueue.async { self.config.recordingPID = appPID }
        objectWillChange.send()
    }

    @discardableResult
    func stopRecording() -> RecordingSummary? {
        guard let rec = recording else { return nil }
        recording = nil
        sampleQueue.async { self.config.recordingPID = nil }
        objectWillChange.send()
        let summary = RecordingStore.save(label: rec.label, appName: rec.appName,
                                          appPID: rec.appPID, start: rec.start,
                                          end: Date(), samples: rec.samples)
        recordings = RecordingStore.loadIndex()
        return summary
    }

    func deleteRecording(_ summary: RecordingSummary) {
        RecordingStore.delete(summary)
        recordings = RecordingStore.loadIndex()
    }

    /// 历史窗口（秒）
    func samples(window: Int) -> [MetricSample] {
        let cutoff = Date().addingTimeInterval(-Double(window))
        return history.filter { $0.time >= cutoff }
    }

    // MARK: - 键盘背光

    func setKeyboardBacklight(_ level: Int) {
        guard kbdMaxLevel > 0 else {
            kbdError = "当前机型不可控（见「诊断」页）"
            return
        }
        let clamped = max(0, min(kbdMaxLevel, level))
        kbdLevel = clamped
        kbdAssumed = true
        pendingKbd = clamped
        kbdError = nil

        kbdDebounce?.invalidate()
        kbdDebounce = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.commitKeyboardBacklight()
        }
        RunLoop.main.add(kbdDebounce!, forMode: .common)
    }

    private func commitKeyboardBacklight() {
        guard let level = pendingKbd else { return }
        pendingKbd = nil
        kbdBusy = true
        let store = self
        DispatchQueue.global(qos: .userInitiated).async {
            let err = Control.setBacklight(level)
            DispatchQueue.main.async {
                store.kbdBusy = false
                if let err {
                    store.kbdError = err
                } else {
                    store.kbdError = nil
                }
                store.kbdAssumed = false
                store.kbdLevel = Control.currentLevel()
                store.kbdPermission = Control.permissionState
                store.maybeRequestHIDPermission()
            }
        }
    }

    /// 设置机型显示名（nil = 恢复自动识别）
    func setProductName(_ name: String?, global: String? = nil) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Prefs.set(trimmed, for: ModelCatalog.overrideKey)
        Prefs.set(global ?? "", for: ModelCatalog.overrideGlobalKey)
        hardware = SystemProbe.hardware()
    }

    // MARK: - 派生值

    var tempText: String {
        guard let t = cpuTemp else { return "—" }
        return String(format: "%.0f", t)
    }

    var tempStatusText: String {
        guard let t = cpuTemp else { return "无数据" }
        switch t {
        case ..<55: return "凉爽"
        case ..<70: return "正常"
        case ..<85: return "偏高"
        case ..<95: return "高温"
        default: return "过热"
        }
    }

    /// 菜单栏标题：按「菜单栏」页里勾选的项目拼一段紧凑文本
    var menuBarTitle: String {
        let picked = MenuBarPrefs.enabled.compactMap { shortText($0) }
        return picked.isEmpty ? "Vela X" : picked.joined(separator: " ")
    }

    /// 菜单栏状态项用的结构化条目（图标 + 短标签 + 数值），供 App.swift 渲染图标版标签
    var menuBarItems: [MenuBarItem] {
        MenuBarPrefs.enabled.compactMap { metric in
            shortText(metric).map { MenuBarItem(metric: metric, value: $0) }
        }
    }

    /// 菜单栏窗口里每一行的完整显示（带项目名）
    func menuValue(_ metric: MenuMetric) -> MenuMetricValue {
        switch metric {
        case .cpuTemp:
            if let t = cpuTemp {
                return MenuMetricValue(text: String(format: "%.0f °C", t), available: true)
            }
            return MenuMetricValue(text: "—", available: false,
                                   reason: "读不到 TC0P，需要 SMCAMDProcessor（或 SMCIntelProcessor）")

        case .cpuLoad:
            guard load.sampled else {
                return MenuMetricValue(text: "—", available: false, reason: "采样中…")
            }
            return MenuMetricValue(text: String(format: "%.0f%%", load.total * 100), available: true)

        case .cpuFreq:
            if let ghz = cpuFreq.liveGHz {
                return MenuMetricValue(text: String(format: "%.2f GHz", ghz), available: true)
            }
            let nominal = cpuFreq.nominalHz > 0
                ? String(format: "sysctl 只给了一个标称值 %.2f GHz", Double(cpuFreq.nominalHz) / 1e9)
                : "sysctl 里连标称频率都没有"
            return MenuMetricValue(text: "不可用", available: false,
                                   reason: "需要 AMDRyzenCPUPowerManagement.kext（SMCAMDProcessor 套件）提供实时频率；\(nominal)")

        case .memUsage:
            guard load.memTotal > 0 else {
                return MenuMetricValue(text: "—", available: false, reason: "读不到内存统计")
            }
            return MenuMetricValue(text: String(format: "%.0f%%", load.memoryUsedRatio * 100), available: true)

        case .netSpeed:
            guard netSpeed.sampled else {
                return MenuMetricValue(text: "—", available: false, reason: "采样中…")
            }
            switch MenuBarPrefs.netMode {
            case .down: return MenuMetricValue(text: "↓ \(netSpeed.down.asRate)", available: true)
            case .up:   return MenuMetricValue(text: "↑ \(netSpeed.up.asRate)", available: true)
            case .both: return MenuMetricValue(text: "↓ \(netSpeed.down.asRate)  ↑ \(netSpeed.up.asRate)",
                                               available: true)
            }


        case .gpuLoad:
            guard let g = gpuUsage else {
                return MenuMetricValue(text: "不可用", available: false,
                                       reason: "驱动没有上报利用率：\(GPUProbe.displayName) 的 PerformanceStatistics 里没有 utilization 键；macOS 下也没有 NVML 的等价接口")
            }
            return MenuMetricValue(text: String(format: "%.0f%%", g), available: true)

        case .gpuTemp:
            guard let t = gpuTemp else {
                return MenuMetricValue(text: "不可用", available: false,
                                       reason: "驱动没有上报温度：\(GPUProbe.displayName) 的 PerformanceStatistics 里没有 Temperature(C) 键")
            }
            return MenuMetricValue(text: String(format: "%.0f °C", t), available: true)

        case .power:
            guard let w = powerWatts else {
                return MenuMetricValue(text: "不可用", available: false,
                                   reason: "需要 AMDRyzenCPUPowerManagement.kext（SMCAMDProcessor 套件）提供整包功耗；powermetrics 需 root 这条路在黑苹果上走不通")
            }
            return MenuMetricValue(text: String(format: "%.1f W", w), available: true)
        }
    }

    /// 这一项在本机能不能用 —— 与「此刻有没有读到值」是两回事，
    /// 设置页用这个决定开关能不能点，避免采样间隙里开关来回闪
    func isAvailable(_ metric: MenuMetric) -> Bool {
        switch metric {
        case .cpuTemp:  return cpuTemp != nil
        case .cpuLoad:  return true
        case .cpuFreq:  return cpuFreq.live
        case .memUsage: return load.memTotal > 0
        case .netSpeed: return true
        case .gpuLoad:  return gpuUsage != nil
        case .gpuTemp:  return gpuTemp != nil
        case .power:    return powerWatts != nil
        }
    }

    func unavailableReason(_ metric: MenuMetric) -> String? {
        isAvailable(metric) ? nil : menuValue(metric).reason
    }

    /// 菜单栏标题用的紧凑写法（不带项目名，长度要控制）
    func shortText(_ metric: MenuMetric) -> String? {
        switch metric {
        case .cpuTemp:
            guard let t = cpuTemp else { return nil }
            return String(format: "%.0f°", t)
        case .cpuLoad:
            guard load.sampled else { return nil }
            return String(format: "%.0f%%", load.total * 100)
        case .memUsage:
            guard load.memTotal > 0 else { return nil }
            return String(format: "%.0f%%", load.memoryUsedRatio * 100)
        case .netSpeed:
            guard netSpeed.sampled else { return nil }
            switch MenuBarPrefs.netMode {
            case .down: return "↓\(netSpeed.down.asRate)"
            case .up:   return "↑\(netSpeed.up.asRate)"
            // 「上下行」以前只显示下行，跟设置名不符，补上上行
            case .both: return "↓\(netSpeed.down.asRate) ↑\(netSpeed.up.asRate)"
            }
        case .cpuFreq:
            guard let ghz = cpuFreq.liveGHz else { return nil }
            return String(format: "%.2fG", ghz)
        case .gpuLoad:
            guard let g = gpuUsage else { return nil }
            return String(format: "%.0f%%", g)
        case .gpuTemp:
            guard let t = gpuTemp else { return nil }
            return String(format: "%.0f°", t)
        case .power:
            guard let w = powerWatts else { return nil }
            return String(format: "%.0fW", w)
        }
    }

    var availableCount: Int {
        capabilities.filter { $0.status != .unavailable }.count
    }
}
