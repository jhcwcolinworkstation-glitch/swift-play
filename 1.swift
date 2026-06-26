import SwiftUI

@main
struct DemoApp: App {
    @AppStorage("userColorScheme") private var userColorScheme: String = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(resolvedColorScheme)
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch userColorScheme {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}

struct ContentView: View {
    @AppStorage("userColorScheme") private var userColorScheme: String = "system"

    @State private var message = "Hello, SwiftUI!"
    @State private var textInput = ""
    @State private var isOn = true
    @State private var selectedColor = "Blue"
    @State private var volume = 50.0

    let colors = ["Red", "Green", "Blue", "Yellow"]

    var body: some View {
        NavigationStack {
            Form {

                // 外观切换
                Section("外观") {
                    Picker("显示模式", selection: $userColorScheme) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                // 文本示例
                Section("文本示例") {
                    Text(message)
                        .font(.title)
                        .foregroundStyle(isOn ? .primary : .secondary)

                    Text("这是一段辅助说明文字，支持 **Markdown**")
                        .font(.footnote)
                }

                // 按钮示例
                Section("按钮示例") {
                    Button("点击我问好") {
                        message = "你好，SwiftUI！"
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        message = "已重置"
                    } label: {
                        Label("重置", systemImage: "trash")
                    }
                }

                // 文本输入
                Section("文本输入") {
                    TextField("输入一些文字...", text: $textInput)

                    Text("你输入了：\(textInput)")
                        .font(.caption)
                }

                // 开关
                Section("开关控件") {
                    Toggle("启用高亮", isOn: $isOn)
                }

                // 选择器
                Section("选择器") {
                    Picker("选择颜色", selection: $selectedColor) {
                        ForEach(colors, id: \.self) { color in
                            Text(color)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // 滑块
                Section("滑块") {
                    Slider(
                        value: $volume,
                        in: 0...100
                    ) {
                        Text("音量")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    }

                    Text("音量：\(Int(volume))%")
                }

                // 列表示例（修复版）
                Section("列表") {
                    ForEach(1..<4, id: \.self) { index in
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)

                            Text("第 \(index) 项")
                        }
                    }
                }
            }
            .navigationTitle("iOS 原生控件")
        }
    }
}
