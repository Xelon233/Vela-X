//
//  CustomCurve.swift
//  VelaX —— 自定义风扇曲线（交付件，直接放进 Sources/ 即可）
//
//  设计原则：自包含。不修改 FanControl / Views / CLI 里的任何类型定义，
//  只依赖它们已有的模块内成员。接入只需在两处各贴一小段代码
//  （见 VelaX-CustomCurve.patch.swift 与 README.md）。
//
//  链路：
//    GUI 拖动 8 点 → CustomCurveController 写 /tmp/vela_custom_curve.json
//    → 以 root 重跑自身 CLI：fan apply-custom <json>
//    → FanController.apply 写 AFMf / AFW1..4 / AFWg（kext 早已具备该通道）
//
//  注意：EC 不回显写进去的曲线，是否生效只能看转速（F0Ac/F1Ac）变化。
//

import Foundation
import SwiftUI

// MARK: - 数据模型

/// 编辑用的可变曲线（FanCurve 是只读值类型，UI 需要逐点拖动修改）。
struct EditableCurve: Equatable {
    var temp: [Int]
    var duty: [Int]

    /// 兜底初值：温和递增，8 点单调不减
    static let defaultCurve = EditableCurve(
        temp: [40, 48, 56, 64, 72, 80, 88, 96],
        duty: [28, 32, 40, 50, 62, 74, 86, 96]
    )

    init(temp: [Int], duty: [Int]) {
        self.temp = temp
        self.duty = duty
    }

    init(_ c: FanCurve) {
        self.temp = c.temp
        self.duty = c.duty
    }

    var points: Int { min(temp.count, duty.count) }

    func toFanCurve() -> FanCurve { FanCurve(temp: temp, duty: duty) }

    /// 单调 + 范围校验；通过返回 nil，否则返回可直接显示的中文原因。
    func validationError(points: Int,
                         tempRange: ClosedRange<Int>,
                         dutyRange: ClosedRange<Int>) -> String? {
        guard temp.count == points, duty.count == points else {
            return "需要 \(points) 个点（当前温度 \(temp.count) / 占空 \(duty.count)）"
        }
        for i in 1..<temp.count where temp[i] < temp[i - 1] {
            return "温度必须单调不减：第 \(i + 1) 点 \(temp[i])°C < 第 \(i) 点 \(temp[i - 1])°C"
        }
        for i in 1..<duty.count where duty[i] < duty[i - 1] {
            return "占空比必须单调不减：第 \(i + 1) 点 \(duty[i])% < 第 \(i) 点 \(duty[i - 1])%"
        }
        if let t0 = temp.first, t0 < tempRange.lowerBound {
            return "最低温度 \(t0)°C 低于机型允许的 \(tempRange.lowerBound)°C"
        }
        if let t1 = temp.last, t1 > tempRange.upperBound {
            return "最高温度 \(t1)°C 高于机型允许的 \(tempRange.upperBound)°C"
        }
        if let dMin = duty.min(), dMin < dutyRange.lowerBound {
            return "占空比 \(dMin)% 低于下限 \(dutyRange.lowerBound)%"
        }
        if let dMax = duty.max(), dMax > dutyRange.upperBound {
            return "占空比 \(dMax)% 超过上限 \(dutyRange.upperBound)%"
        }
        return nil
    }
}

/// 提权后 CLI 读取的曲线文件格式（/tmp/vela_custom_curve.json）。
struct CustomCurveFile: Codable {
    var cpu: FanCurve
    var gpu: FanCurve
}

// MARK: - 控制器（单一数据源 + 下发）

@MainActor
final class CustomCurveController: ObservableObject {
    static let shared = CustomCurveController()

    @Published private(set) var cpu: EditableCurve
    @Published private(set) var gpu: EditableCurve
    @Published private(set) var applying = false
    @Published private(set) var message: String?
    /// 是否已成功下发过（仅用于界面提示）
    @Published private(set) var lastApplied = false
    /// 功能解锁开关：默认关，需在「高级功能」页确认风险后解锁
    @Published private(set) var unlocked: Bool

    private let fan = FanControl.shared
    private var seeded = false

    private init() {
        unlocked = Prefs.bool("fan.customUnlocked")
        if let json = Prefs.string("fan.customCurve"),
           let data = json.data(using: .utf8),
           let file = try? JSONDecoder().decode(CustomCurveFile.self, from: data),
           file.cpu.temp.count == 8, file.gpu.temp.count == 8 {
            cpu = EditableCurve(file.cpu)
            gpu = EditableCurve(file.gpu)
            seeded = true
        } else {
            cpu = .defaultCurve
            gpu = .defaultCurve
        }
    }

    /// 首次进入页面时，若还没有自定义曲线，用该机型的「平衡」预设做初值
    func ensureSeededFromPresets() {
        guard !seeded else { return }
        if let p = fan.presets?.preset("balanced") {
            cpu = EditableCurve(p.cpu)
            gpu = EditableCurve(p.gpu)
            seeded = true
        }
    }

    func update(_ which: FanController.Fan, _ curve: EditableCurve) {
        if which == .cpu { cpu = curve } else { gpu = curve }
    }

    func seed(from preset: String) {
        guard let p = fan.presets?.preset(preset) else { return }
        cpu = EditableCurve(p.cpu)
        gpu = EditableCurve(p.gpu)
        seeded = true
    }

    // 机型 EC 配置决定点数与温度/占空范围
    var tempRange: ClosedRange<Int> {
        (fan.ecProfile?.tempMin ?? 20)...(fan.ecProfile?.tempMax ?? 110)
    }
    var dutyRange: ClosedRange<Int> {
        (fan.ecProfile?.dutyMin ?? 0)...(fan.ecProfile?.dutyMax ?? 100)
    }
    var pointCount: Int { fan.ecProfile?.curvePoints ?? 8 }

    func validationError() -> String? {
        let pts = pointCount, tr = tempRange, dr = dutyRange
        if let e = cpu.validationError(points: pts, tempRange: tr, dutyRange: dr) {
            return "CPU：" + e
        }
        if let e = gpu.validationError(points: pts, tempRange: tr, dutyRange: dr) {
            return "GPU：" + e
        }
        return nil
    }

    /// 机型不匹配 / 未识别且尚未确认风险 → 需要先确认
    var needsRiskConfirm: Bool {
        fan.status != .matched && !fan.acknowledgedMismatch
    }

    var riskMessage: String {
        fan.status == .mismatched
            ? ModelDisclaimer.short(selected: fan.selectedCode, detected: fan.detection.code)
            : ModelDisclaimer.shortUndetected(selected: fan.selectedCode)
    }

    func acknowledgeRisk() {
        fan.acknowledgeMismatch()
    }

    /// 高级功能页确认风险后解锁 / 关闭
    func unlock() {
        unlocked = true
        Prefs.set(true, for: "fan.customUnlocked")
    }

    func lock() {
        unlocked = false
        Prefs.set(false, for: "fan.customUnlocked")
    }

    /// 下发自定义曲线：写临时 JSON → 以 root 重跑自身 CLI `fan apply-custom`
    func apply() {
        guard !applying else { return }
        if let err = validationError() { message = err; return }
        if needsRiskConfirm { message = riskMessage; return }

        let file = CustomCurveFile(cpu: cpu.toFanCurve(), gpu: gpu.toFanCurve())
        guard let data = try? JSONEncoder().encode(file) else {
            message = "曲线编码失败"
            return
        }
        // 路径不能带空格：Admin 提权时参数是按空格拼接的
        let path = "/tmp/vela_custom_curve.json"
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            message = "写入曲线文件失败：\(error.localizedDescription)"
            return
        }

        applying = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Admin.runSelfAsAdmin(["fan", "apply-custom", path])
            DispatchQueue.main.async {
                self.applying = false
                if result.ok {
                    self.lastApplied = true
                    self.persist()
                    // 让「当前档位」切到 custom，预设不再显示「使用中」
                    FanControl.shared.noteCustomApplied()
                    self.message = "已下发自定义曲线，转速通常几秒内跟上"
                } else {
                    let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.message = text.isEmpty ? "自定义曲线下发失败（未拿到输出）" : text
                }
            }
        }
    }

    private func persist() {
        let file = CustomCurveFile(cpu: cpu.toFanCurve(), gpu: gpu.toFanCurve())
        if let data = try? JSONEncoder().encode(file),
           let s = String(data: data, encoding: .utf8) {
            Prefs.set(s, for: "fan.customCurve")
        }
    }
}

// MARK: - 界面：自定义曲线卡片（整段放进「性能与风扇」页即可）

struct CustomCurveCard: View {
    @ObservedObject private var fan = FanControl.shared
    @ObservedObject private var controller = CustomCurveController.shared

    @State private var editingFan: FanController.Fan = .cpu
    @State private var cpu: EditableCurve = .defaultCurve
    @State private var gpu: EditableCurve = .defaultCurve
    @State private var seeded = false
    @State private var showRisk = false

    private var editingBinding: Binding<EditableCurve> {
        Binding(
            get: { editingFan == .cpu ? cpu : gpu },
            set: { newValue in
                if editingFan == .cpu { cpu = newValue } else { gpu = newValue }
            }
        )
    }

    private var localError: String? {
        let pts = controller.pointCount
        let tr = controller.tempRange
        let dr = controller.dutyRange
        if let e = cpu.validationError(points: pts, tempRange: tr, dutyRange: dr) {
            return "CPU：" + e
        }
        if let e = gpu.validationError(points: pts, tempRange: tr, dutyRange: dr) {
            return "GPU：" + e
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "自定义曲线",
                         trailing: fan.kextLoaded ? "可下发" : "kext 未加载")

            Card {
                VStack(alignment: .leading, spacing: 11) {
                    header

                    CurveEditorCanvas(curve: editingBinding,
                                      tempRange: controller.tempRange,
                                      dutyRange: controller.dutyRange,
                                      pointCount: controller.pointCount)
                        .frame(height: 168)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Palette.panelTop.opacity(0.45)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Palette.cardStroke, lineWidth: 0.7))

                    numericStrip

                    Text("拖动圆点：横向=温度、纵向=占空比，自动保持单调不减。改动后点「应用自定义曲线」才会写入 EC。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let err = localError {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.bad)
                            Text(err)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.bad)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    applyRow

                    if showRisk, controller.needsRiskConfirm {
                        riskConfirm
                    }

                    if let m = controller.message {
                        Text(m)
                            .font(.system(size: 10))
                            .foregroundStyle(m.hasPrefix("已下发") ? Palette.ok : Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear {
            controller.ensureSeededFromPresets()
            if !seeded {
                cpu = controller.cpu
                gpu = controller.gpu
                seeded = true
            }
        }
    }

    // MARK: 子视图

    private var header: some View {
        HStack(spacing: 10) {
            Text("风扇")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
            Picker("", selection: $editingFan) {
                Text("CPU").tag(FanController.Fan.cpu)
                Text("GPU").tag(FanController.Fan.gpu)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
            Spacer(minLength: 6)
            // 一键把当前编辑的曲线复制到另一只风扇：避免「只改了 CPU、忘了 GPU」
            Button {
                if editingFan == .cpu { gpu = cpu } else { cpu = gpu }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("同步到\(editingFan == .cpu ? "GPU" : "CPU")")
                }
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Palette.accent.opacity(0.14)))
                .overlay(Capsule().stroke(Palette.accent.opacity(0.30), lineWidth: 0.8))
                .foregroundStyle(Palette.accent)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            Menu {
                ForEach(FanControl.order, id: \.self) { name in
                    if let p = fan.presets?.preset(name) {
                        Button("载入「\(p.label ?? name)」") {
                            cpu = EditableCurve(p.cpu)
                            gpu = EditableCurve(p.gpu)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("从预设载入")
                }
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Palette.accent.opacity(0.14)))
                .overlay(Capsule().stroke(Palette.accent.opacity(0.30), lineWidth: 0.8))
                .foregroundStyle(Palette.accent)
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var numericStrip: some View {
        HStack(spacing: 3) {
            ForEach(0..<controller.pointCount, id: \.self) { i in
                VStack(spacing: 1) {
                    Text("\(tempValue(i))°")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                    Text("\(dutyValue(i))%")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Palette.panelTop.opacity(0.35)))
            }
        }
    }

    private var applyRow: some View {
        HStack(spacing: 10) {
            Button {
                controller.update(.cpu, cpu)
                controller.update(.gpu, gpu)
                if controller.needsRiskConfirm {
                    showRisk = true
                } else {
                    controller.apply()
                }
            } label: {
                Group {
                    if controller.applying {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Text("应用自定义曲线")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 5)
                .background(Capsule().fill(Palette.accent.opacity(0.18)))
                .overlay(Capsule().stroke(Palette.accent.opacity(0.36), lineWidth: 0.8))
                .foregroundStyle(Palette.accent)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(controller.applying || !fan.kextLoaded || localError != nil)
            .opacity((fan.kextLoaded && localError == nil) ? 1 : 0.45)

            Text("下发后看上方的 CPU / GPU 转速是否变化来确认生效")
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var riskConfirm: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.warn)
                Text(controller.riskMessage)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    controller.acknowledgeRisk()
                    controller.apply()
                    showRisk = false
                } label: {
                    Text("我已知晓风险，仍要下发")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Palette.warn.opacity(0.16)))
                        .overlay(Capsule().stroke(Palette.warn.opacity(0.4), lineWidth: 0.8))
                        .foregroundStyle(Palette.warn)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    showRisk = false
                } label: {
                    Text("取消").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func tempValue(_ i: Int) -> Int {
        let c = editingFan == .cpu ? cpu : gpu
        return i < c.temp.count ? c.temp[i] : 0
    }

    private func dutyValue(_ i: Int) -> Int {
        let c = editingFan == .cpu ? cpu : gpu
        return i < c.duty.count ? c.duty[i] : 0
    }
}

// MARK: - 可拖动曲线画布

/// x=温度、y=占空比；拖动时对相邻点做单调夹紧，保证两条曲线都单调不减。
struct CurveEditorCanvas: View {
    @Binding var curve: EditableCurve
    let tempRange: ClosedRange<Int>
    let dutyRange: ClosedRange<Int>
    let pointCount: Int

    private var tSpan: CGFloat { CGFloat(max(1, tempRange.upperBound - tempRange.lowerBound)) }
    private var dSpan: CGFloat { CGFloat(max(1, dutyRange.upperBound - dutyRange.lowerBound)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    for frac in stride(from: 0.0, through: 1.0, by: 0.25) {
                        var p = Path()
                        let y = size.height * CGFloat(1 - frac)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: .color(Palette.cardStroke.opacity(0.55)), lineWidth: 0.5)
                    }

                    let n = min(pointCount, curve.points)
                    guard n > 1 else { return }
                    var line = Path()
                    for i in 0..<n {
                        let pt = CGPoint(x: xPos(curve.temp[i], width: size.width),
                                         y: yPos(curve.duty[i], height: size.height))
                        if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                    }
                    var area = line
                    area.addLine(to: CGPoint(x: size.width, y: size.height))
                    area.addLine(to: CGPoint(x: 0, y: size.height))
                    area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(
                        Gradient(colors: [Palette.accent.opacity(0.18), Palette.accent.opacity(0)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    ctx.stroke(line, with: .color(Palette.accent),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }

                ForEach(0..<min(pointCount, curve.points), id: \.self) { i in
                    handle(i, width: w, height: h)
                }
            }
            .coordinateSpace(name: "curveCanvas")
        }
        .onHover { inside in
            // 悬停画布时锁住窗口背景拖动：否则拖圆点会把整个窗口一起拖走
            WindowState.shared.interactionLocked = inside
        }
        .onDisappear { WindowState.shared.interactionLocked = false }
    }

    private func handle(_ i: Int, width: CGFloat, height: CGFloat) -> some View {
        Circle()
            .fill(Palette.accent)
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 1, y: 0.5)
            .position(x: xPos(curve.temp[i], width: width),
                      y: yPos(curve.duty[i], height: height))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("curveCanvas"))
                    .onChanged { value in
                        drag(i, to: value.location, width: width, height: height)
                    }
            )
    }

    private func drag(_ i: Int, to p: CGPoint, width: CGFloat, height: CGFloat) {
        let n = min(pointCount, curve.points)
        guard n > 0, i < n, width > 0, height > 0 else { return }

        var t = tempRange.lowerBound + Int(round(min(max(p.x, 0), width) / width * tSpan))
        var d = dutyRange.lowerBound + Int(round((1 - min(max(p.y, 0), height) / height) * dSpan))

        let loT = i == 0 ? tempRange.lowerBound : max(tempRange.lowerBound, curve.temp[i - 1])
        let hiT = i == n - 1 ? tempRange.upperBound : min(tempRange.upperBound, curve.temp[i + 1])
        let loD = i == 0 ? dutyRange.lowerBound : max(dutyRange.lowerBound, curve.duty[i - 1])
        let hiD = i == n - 1 ? dutyRange.upperBound : min(dutyRange.upperBound, curve.duty[i + 1])

        t = min(max(t, loT), max(loT, hiT))
        d = min(max(d, loD), max(loD, hiD))

        curve.temp[i] = t
        curve.duty[i] = d
    }

    private func xPos(_ t: Int, width: CGFloat) -> CGFloat {
        CGFloat(t - tempRange.lowerBound) / tSpan * width
    }

    private func yPos(_ d: Int, height: CGFloat) -> CGFloat {
        height - CGFloat(d - dutyRange.lowerBound) / dSpan * height
    }
}

// MARK: - 解锁门

/// 只有「高级功能」页里确认风险、解锁之后，才在「性能与风扇」页显示自定义曲线编辑器。
struct CustomCurveGate: View {
    @ObservedObject private var controller = CustomCurveController.shared

    var body: some View {
        if controller.unlocked {
            CustomCurveCard()
        }
    }
}
