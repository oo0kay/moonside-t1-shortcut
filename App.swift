import SwiftUI
import CoreBluetooth
import AppIntents

@main
struct MoonsideT1App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - 1. 后台静默蓝牙控制器 (专配 MOONSIDE-T1)
class MoonsideBLE: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = MoonsideBLE()
    
    private var central: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var pendingCommand: String = ""
    private var completion: (() -> Void)?
    
    let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    let charUUID    = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    
    func send(_ cmd: String, done: @escaping () -> Void) {
        self.pendingCommand = cmd
        self.completion = done
        
        if let p = targetPeripheral, p.state == .connected, let c = writeChar {
            writeData(to: p, char: c)
            return
        }
        
        self.central = CBCentralManager(delegate: self, queue: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            self.finish()
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
            if let existing = connected.first {
                self.targetPeripheral = existing
                existing.delegate = self
                central.connect(existing, options: nil)
            } else {
                central.scanForPeripherals(withServices: nil, options: nil)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = (peripheral.name ?? "").uppercased()
        if name.contains("MOONSIDE") || name.contains("MS-") {
            self.targetPeripheral = peripheral
            peripheral.delegate = self
            central.stopScan()
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services where s.uuid == serviceUUID {
            peripheral.discoverCharacteristics([charUUID], for: s)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars where c.uuid == charUUID {
            self.writeChar = c
            writeData(to: peripheral, char: c)
        }
    }
    
    private func writeData(to p: CBPeripheral, char: CBCharacteristic) {
        if let data = pendingCommand.data(using: .utf8) {
            p.writeValue(data, for: char, type: .withResponse)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.finish()
        }
    }
    
    private func finish() {
        completion?()
        completion = nil
    }
}

// MARK: - 2. 暴露给 iOS「快捷指令」的后台静默接口
struct MoonsideCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "发送蓝牙指令给 Moonside T1"
    static var description = IntentDescription("无需打开App，在后台直接通过蓝牙控制 Moonside T1")
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "蓝牙指令 (无末尾点)", default: "LEDON")
    var command: String
    
    func perform() async throws -> some IntentResult {
        await withCheckedContinuation { continuation in
            MoonsideBLE.shared.send(command) {
                continuation.resume()
            }
        }
        return .result()
    }
}

// MARK: - 3. App 主界面遥控面板
struct ContentView: View {
    @State private var customCmd: String = "COLOR255000120"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("✨ Moonside T1 捷径中枢").font(.title2).bold()
            Text("首次打开请随便点个按钮以弹出并允许【蓝牙权限】").font(.caption).foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button("💡 开灯 (LEDON)") { MoonsideBLE.shared.send("LEDON") {} }
                    .buttonStyle(.borderedProminent).tint(.green)
                Button("🌑 关灯 (全黑)") { MoonsideBLE.shared.send("COLOR000000000") {} }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
            
            VStack(spacing: 10) {
                Text("常用纯色与主题").font(.subheadline).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button("🔴 纯红") { MoonsideBLE.shared.send("COLOR255000000") {} }.buttonStyle(.bordered)
                    Button("🟢 纯绿") { MoonsideBLE.shared.send("COLOR000255000") {} }.buttonStyle(.bordered)
                    Button("🔵 纯蓝") { MoonsideBLE.shared.send("COLOR000000255") {} }.buttonStyle(.bordered)
                }
                HStack(spacing: 10) {
                    Button("🟣 赛博粉") { MoonsideBLE.shared.send("COLOR255000120") {} }.buttonStyle(.bordered)
                    Button("🟠 暖橙光") { MoonsideBLE.shared.send("COLOR255120000") {} }.buttonStyle(.bordered)
                    Button("🌈 彩虹波浪") { MoonsideBLE.shared.send("THEME.RAINBOW1") {} }.buttonStyle(.bordered)
                }
            }
            
            VStack(spacing: 10) {
                Text("亮度快捷调节").font(.subheadline).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button("🌙 10%") { MoonsideBLE.shared.send("BRIGH012") {} }.buttonStyle(.bordered)
                    Button("⛅ 50%") { MoonsideBLE.shared.send("BRIGH060") {} }.buttonStyle(.bordered)
                    Button("☀️ 100%") { MoonsideBLE.shared.send("BRIGH120") {} }.buttonStyle(.bordered)
                }
            }
            
            HStack {
                TextField("输入指令...", text: $customCmd)
                    .textFieldStyle(.roundedBorder)
                Button("发送") { MoonsideBLE.shared.send(customCmd) {} }
                    .buttonStyle(.borderedProminent)
            }.padding(.horizontal)
        }
        .padding()
    }
}
