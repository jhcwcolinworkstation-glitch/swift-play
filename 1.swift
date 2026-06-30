import SwiftUI
import WebKit
import Combine
import AVFoundation
import UniformTypeIdentifiers
import PhotosUI

// MARK: - 数据模型

struct Message: Identifiable, Codable {
    let id: String
    let role: Role
    var content: String
    let timestamp: Date
    var attachments: [Attachment]?
    var generatedImages: [String]?
    var model: String?
    var reasoning: String?

    enum Role: String, Codable {
        case user, assistant, system
    }

    init(id: String = UUID().uuidString, role: Role, content: String, timestamp: Date = Date(), attachments: [Attachment]? = nil, generatedImages: [String]? = nil, model: String? = nil, reasoning: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachments = attachments
        self.generatedImages = generatedImages
        self.model = model
        self.reasoning = reasoning
    }
}

struct Attachment: Identifiable, Codable {
    let id: String
    let name: String
    let type: String
    var data: String?
    var fullDataUrl: String?
    let size: Int
    let isImage: Bool
    let isText: Bool

    init(id: String = UUID().uuidString, name: String, type: String, data: String? = nil, fullDataUrl: String? = nil, size: Int, isImage: Bool, isText: Bool) {
        self.id = id
        self.name = name
        self.type = type
        self.data = data
        self.fullDataUrl = fullDataUrl
        self.size = size
        self.isImage = isImage
        self.isText = isText
    }
}

struct Chat: Identifiable, Codable {
    let id: String
    var title: String
    var messages: [Message]
    var updatedAt: Date
    var canvasEnabled: Bool
    var canvasCode: [String]
    var lcObjectId: String?

    init(id: String = UUID().uuidString, title: String = "新对话", messages: [Message] = [], updatedAt: Date = Date(), canvasEnabled: Bool = false, canvasCode: [String] = [""], lcObjectId: String? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
        self.canvasEnabled = canvasEnabled
        self.canvasCode = canvasCode
        self.lcObjectId = lcObjectId
    }
}

// MARK: - 应用状态管理

class AppState: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var activeChatId: String?
    @Published var isGenerating = false
    @Published var currentAttachments: [Attachment] = []
    @Published var systemPrompt: String = ""
    @Published var temperature: Double = 0.7
    @Published var selectedModel: String = "gpt-5.5-2026-04-24"
    @Published var apiKey: String = "sk-FsuAh4g9yaBtkTVQEf53F3473b3d4bD9A2822d17EbFbA6B8"
    @Published var baseURL: String = "https://api.vveai.com/v1"
    @Published var maxTokens: Int = 0
    @Published var isDarkMode: Bool = false
    @Published var showingSettings = false
    @Published var showingSidebar = false
    @Published var fontSize: FontSize = .medium
    @Published var backgroundImageIndex: Int = 1
    @Published var layoutMode: LayoutMode = .classic
    @Published var canvasFontSize: CGFloat = 14
    @Published var canvasCode: String = ""
    @Published var canvasEnabled: Bool = false
    @Published var isImageMode: Bool = false
    @Published var isImageEditMode: Bool = false
    @Published var voiceModel: String = "whisper-1"
    @Published var memories: [String] = []
    @Published var isCloudEnabled: Bool = false
    @Published var lcAppId: String = ""
    @Published var lcApiKey: String = ""
    @Published var lcMasterKey: String = ""
    @Published var lcBaseURL: String = ""

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadFromStorage()
        setupBindings()
        fetchMemories()
    }

    private func setupBindings() {
        $chats
            .sink { [weak self] _ in self?.saveToStorage() }
            .store(in: &cancellables)
        $systemPrompt
            .sink { UserDefaults.standard.set($0, forKey: "systemPrompt") }
            .store(in: &cancellables)
        $temperature
            .sink { UserDefaults.standard.set($0, forKey: "temperature") }
            .store(in: &cancellables)
        $selectedModel
            .sink { UserDefaults.standard.set($0, forKey: "selectedModel") }
            .store(in: &cancellables)
        $apiKey
            .sink { UserDefaults.standard.set($0, forKey: "apiKey") }
            .store(in: &cancellables)
        $baseURL
            .sink { UserDefaults.standard.set($0, forKey: "baseURL") }
            .store(in: &cancellables)
        $maxTokens
            .sink { UserDefaults.standard.set($0, forKey: "maxTokens") }
            .store(in: &cancellables)
        $isDarkMode
            .sink { UserDefaults.standard.set($0, forKey: "isDarkMode") }
            .store(in: &cancellables)
        $fontSize
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "fontSize") }
            .store(in: &cancellables)
        $backgroundImageIndex
            .sink { UserDefaults.standard.set($0, forKey: "backgroundImageIndex") }
            .store(in: &cancellables)
        $layoutMode
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "layoutMode") }
            .store(in: &cancellables)
        $canvasFontSize
            .sink { UserDefaults.standard.set($0, forKey: "canvasFontSize") }
            .store(in: &cancellables)
        $voiceModel
            .sink { UserDefaults.standard.set($0, forKey: "voiceModel") }
            .store(in: &cancellables)
        $isCloudEnabled
            .sink { UserDefaults.standard.set($0, forKey: "isCloudEnabled") }
            .store(in: &cancellables)
        $lcAppId
            .sink { UserDefaults.standard.set($0, forKey: "lcAppId") }
            .store(in: &cancellables)
        $lcApiKey
            .sink { UserDefaults.standard.set($0, forKey: "lcApiKey") }
            .store(in: &cancellables)
        $lcMasterKey
            .sink { UserDefaults.standard.set($0, forKey: "lcMasterKey") }
            .store(in: &cancellables)
        $lcBaseURL
            .sink { UserDefaults.standard.set($0, forKey: "lcBaseURL") }
            .store(in: &cancellables)
    }

    private func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: "chats"),
           let decoded = try? JSONDecoder().decode([Chat].self, from: data) {
            chats = decoded
        }
        systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? ""
        temperature = UserDefaults.standard.double(forKey: "temperature")
        if temperature == 0 { temperature = 0.7 }
        selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "gpt-5.5-2026-04-24"
        apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? "sk-FsuAh4g9yaBtkTVQEf53F3473b3d4bD9A2822d17EbFbA6B8"
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.vveai.com/v1"
        maxTokens = UserDefaults.standard.integer(forKey: "maxTokens")
        isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        fontSize = FontSize(rawValue: UserDefaults.standard.string(forKey: "fontSize") ?? "medium") ?? .medium
        backgroundImageIndex = UserDefaults.standard.integer(forKey: "backgroundImageIndex")
        if backgroundImageIndex == 0 { backgroundImageIndex = 1 }
        layoutMode = LayoutMode(rawValue: UserDefaults.standard.string(forKey: "layoutMode") ?? "classic") ?? .classic
        canvasFontSize = UserDefaults.standard.double(forKey: "canvasFontSize")
        if canvasFontSize == 0 { canvasFontSize = 14 }
        voiceModel = UserDefaults.standard.string(forKey: "voiceModel") ?? "whisper-1"
        isCloudEnabled = UserDefaults.standard.bool(forKey: "isCloudEnabled")
        lcAppId = UserDefaults.standard.string(forKey: "lcAppId") ?? ""
        lcApiKey = UserDefaults.standard.string(forKey: "lcApiKey") ?? ""
        lcMasterKey = UserDefaults.standard.string(forKey: "lcMasterKey") ?? ""
        lcBaseURL = UserDefaults.standard.string(forKey: "lcBaseURL") ?? ""

        if chats.isEmpty { createNewChat() }
        else { activeChatId = chats.first?.id }
    }

    private func saveToStorage() {
        if let encoded = try? JSONEncoder().encode(chats) {
            UserDefaults.standard.set(encoded, forKey: "chats")
        }
    }

    func createNewChat() {
        let chat = Chat()
        chats.insert(chat, at: 0)
        activeChatId = chat.id
        canvasEnabled = false
        canvasCode = ""
        isImageMode = false
        isImageEditMode = false
        saveToStorage()
    }

    func deleteChat(_ chatId: String) {
        chats.removeAll { $0.id == chatId }
        if activeChatId == chatId {
            if let first = chats.first { activeChatId = first.id }
            else { createNewChat() }
        }
        saveToStorage()
    }

    func getActiveChat() -> Chat? {
        chats.first { $0.id == activeChatId }
    }

    func updateChat(_ chat: Chat) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index] = chat
            saveToStorage()
        }
    }

    func addMessage(_ message: Message, to chatId: String) {
        if let index = chats.firstIndex(where: { $0.id == chatId }) {
            chats[index].messages.append(message)
            chats[index].updatedAt = Date()
            if chats[index].messages.count == 1 && message.role == .user {
                chats[index].title = String(message.content.prefix(20))
            }
            saveToStorage()
        }
    }

    func updateLastMessage(_ content: String, reasoning: String? = nil, in chatId: String) {
        if let index = chats.firstIndex(where: { $0.id == chatId }),
           let lastIndex = chats[index].messages.indices.last,
           chats[index].messages[lastIndex].role == .assistant {
            chats[index].messages[lastIndex].content = content
            if let reasoning = reasoning {
                chats[index].messages[lastIndex].reasoning = reasoning
            }
            chats[index].updatedAt = Date()
            saveToStorage()
        }
    }

    func fetchMemories() {
        guard isCloudEnabled, !lcAppId.isEmpty, !lcMasterKey.isEmpty else {
            memories = []
            return
        }
        let urlString = lcBaseURL.replacingOccurrences(of: "AIChats", with: "Memory")
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue(lcAppId, forHTTPHeaderField: "X-LC-Id")
        request.setValue("\(lcMasterKey),master", forHTTPHeaderField: "X-LC-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { self.memories = [] }
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let results = json?["results"] as? [[String: Any]] ?? []
                let mems = results.compactMap { $0["Memory"] as? String }.filter { !$0.isEmpty }
                DispatchQueue.main.async { self.memories = mems }
            } catch {
                DispatchQueue.main.async { self.memories = [] }
            }
        }.resume()
    }

    func syncToCloud() {
        guard isCloudEnabled, !lcAppId.isEmpty, !lcMasterKey.isEmpty else { return }
        for chat in chats {
            let body: [String: Any] = [
                "chatId": chat.id,
                "title": chat.title,
                "messages": chat.messages.map { msg -> [String: Any] in
                    var dict: [String: Any] = [
                        "role": msg.role.rawValue,
                        "content": msg.content,
                        "timestamp": msg.timestamp.timeIntervalSince1970
                    ]
                    if let model = msg.model { dict["model"] = model }
                    return dict
                },
                "updatedAtMs": chat.updatedAt.timeIntervalSince1970 * 1000,
                "canvasEnabled": chat.canvasEnabled,
                "canvasCode": chat.canvasCode
            ]
            guard let url = URL(string: lcBaseURL) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(lcAppId, forHTTPHeaderField: "X-LC-Id")
            request.setValue("\(lcMasterKey),master", forHTTPHeaderField: "X-LC-Key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request).resume()
        }
    }
}

enum FontSize: String { case small, medium, large }
enum LayoutMode: String { case classic, split }

// MARK: - API 服务

class APIService {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func sendMessage(chatId: String, messages: [Message], model: String, onChunk: @escaping (String, String?) -> Void, onComplete: @escaping (Result<Bool, Error>) -> Void) -> AnyCancellable? {
        guard let chat = appState.getActiveChat() else {
            onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "对话不存在"])))
            return nil
        }

        let apiKey = appState.apiKey
        let baseURL = appState.baseURL
        let maxTokens = appState.maxTokens

        guard !apiKey.isEmpty else {
            onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "请先在设置中配置 API Key"])))
            return nil
        }

        var apiMessages: [[String: Any]] = []

        if !appState.systemPrompt.isEmpty {
            apiMessages.append(["role": "system", "content": appState.systemPrompt])
        }

        for msg in messages {
            if msg.role == .user {
                var content: Any = msg.content
                if let attachments = msg.attachments, !attachments.isEmpty {
                    var contentArray: [[String: Any]] = []
                    if !msg.content.isEmpty {
                        contentArray.append(["type": "text", "text": msg.content])
                    }
                    for att in attachments where att.isImage && att.fullDataUrl != nil {
                        contentArray.append([
                            "type": "image_url",
                            "image_url": ["url": att.fullDataUrl!]
                        ])
                    }
                    content = contentArray
                }
                apiMessages.append(["role": "user", "content": content])
            } else if msg.role == .assistant {
                apiMessages.append(["role": "assistant", "content": msg.content])
            }
        }

        if !appState.currentAttachments.isEmpty {
            if let lastIdx = apiMessages.indices.last,
               var last = apiMessages[lastIdx] as? [String: Any],
               last["role"] as? String == "user" {
                var contentArray: [[String: Any]] = []
                if let existing = last["content"] as? String {
                    contentArray.append(["type": "text", "text": existing])
                } else if let existingArray = last["content"] as? [[String: Any]] {
                    contentArray = existingArray
                }
                for att in appState.currentAttachments where att.isImage && att.fullDataUrl != nil {
                    contentArray.append([
                        "type": "image_url",
                        "image_url": ["url": att.fullDataUrl!]
                    ])
                }
                last["content"] = contentArray
                apiMessages[lastIdx] = last
            }
        }

        if appState.canvasEnabled && !appState.canvasCode.isEmpty {
            let canvasContext = "\n\n【Canvas代码区域】\n\(appState.canvasCode)\n"
            if let lastIdx = apiMessages.indices.last,
               var last = apiMessages[lastIdx] as? [String: Any],
               last["role"] as? String == "user" {
                if let existing = last["content"] as? String {
                    last["content"] = existing + canvasContext
                } else if var array = last["content"] as? [[String: Any]] {
                    array.append(["type": "text", "text": canvasContext])
                    last["content"] = array
                }
                apiMessages[lastIdx] = last
            }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": appState.temperature,
            "stream": true
        ]
        if maxTokens > 0 { body["max_tokens"] = maxTokens }

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的API地址"])))
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { onComplete(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无数据"]))) }
                return
            }

            let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
            var fullContent = "", reasoningContent = ""

            for line in lines {
                if line.hasPrefix("data: ") {
                    let jsonStr = String(line.dropFirst(6))
                    if jsonStr == "[DONE]" { continue }
                    if let jsonData = jsonStr.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let first = choices.first,
                       let delta = first["delta"] as? [String: Any] {
                        if let content = delta["content"] as? String {
                            fullContent += content
                            let currentFull = fullContent
let currentReasoning = reasoningContent

DispatchQueue.main.async {
    onChunk(currentFull, currentReasoning)
}
                        }
                        if let reasoning = delta["reasoning_content"] as? String {
                            reasoningContent += reasoning
                            DispatchQueue.main.async { onChunk(fullContent, reasoningContent) }
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                if !fullContent.isEmpty { onComplete(.success(true)) }
                else { onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无有效内容"]))) }
            }
        }
        task.resume()
        return AnyCancellable { task.cancel() }
    }

    func generateImage(prompt: String, model: String, imageBase64: String? = nil, onComplete: @escaping (Result<String, Error>) -> Void) -> AnyCancellable? {
        let apiKey = appState.apiKey
        let baseURL = appState.baseURL
        guard !apiKey.isEmpty else {
            onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "API Key 缺失"])))
            return nil
        }

        var request: URLRequest
        if let imageBase64 = imageBase64 {
            guard let url = URL(string: "\(baseURL)/images/edits") else { return nil }
            let boundary = UUID().uuidString
            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n\(prompt)\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"edit.png\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
            if let imageData = Data(base64Encoded: imageBase64.components(separatedBy: ",").last ?? "") {
                body.append(imageData)
            }
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = body
        } else {
            guard let url = URL(string: "\(baseURL)/images/generations") else { return nil }
            let body: [String: Any] = [
                "model": model,
                "prompt": prompt,
                "n": 1,
                "size": "1024x1024",
                "response_format": "b64_json"
            ]
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { onComplete(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无数据"]))) }
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let dataArray = json?["data"] as? [[String: Any]],
                   let first = dataArray.first,
                   let b64 = first["b64_json"] as? String {
                    let dataUrl = "data:image/png;base64,\(b64)"
                    DispatchQueue.main.async { onComplete(.success(dataUrl)) }
                } else {
                    let msg = (json?["error"] as? [String: Any])?["message"] as? String ?? "生成失败"
                    DispatchQueue.main.async { onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))) }
                }
            } catch {
                DispatchQueue.main.async { onComplete(.failure(error)) }
            }
        }
        task.resume()
        return AnyCancellable { task.cancel() }
    }

    func transcribeAudio(audioData: Data, model: String, onComplete: @escaping (Result<String, Error>) -> Void) -> AnyCancellable? {
        let apiKey = appState.apiKey
        let baseURL = appState.baseURL
        guard !apiKey.isEmpty else {
            onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "API Key 缺失"])))
            return nil
        }
        guard let url = URL(string: "\(baseURL)/audio/transcriptions") else { return nil }

        let boundary = UUID().uuidString
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { onComplete(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无数据"]))) }
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let text = json?["text"] as? String {
                    DispatchQueue.main.async { onComplete(.success(text)) }
                } else {
                    let msg = (json?["error"] as? [String: Any])?["message"] as? String ?? "转录失败"
                    DispatchQueue.main.async { onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))) }
                }
            } catch {
                DispatchQueue.main.async { onComplete(.failure(error)) }
            }
        }
        task.resume()
        return AnyCancellable { task.cancel() }
    }
}

// MARK: - 视图组件

struct MessageWebView: UIViewRepresentable {
    let content: String
    let isDark: Bool
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "heightChanged")
        config.userContentController = userController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = buildHTML(content: content, isDark: isDark)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MessageWebView

        init(_ parent: MessageWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightChanged", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.parent.height = height
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let h = result as? CGFloat {
                    DispatchQueue.main.async { self.parent.height = h }
                }
            }
        }
    }

    private func buildHTML(content: String, isDark: Bool) -> String {
        let theme = isDark ? "github-dark" : "github"
        let bgColor = isDark ? "#1a1a1a" : "#ffffff"
        let textColor = isDark ? "#f0f0f0" : "#1f1f1f"
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        return """
        <!DOCTYPE html>
        <html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.5.0/github-markdown.min.css">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/\(theme).min.css">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.9/katex.min.css">
        <style>
            body{background:\(bgColor);color:\(textColor);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;padding:0;margin:0;line-height:1.6;font-size:15px;}
            .markdown-body{background:\(bgColor);color:\(textColor);padding:4px 0;font-size:15px;}
            .markdown-body pre{background:\(isDark ? "#2d2d2d" : "#f6f8fa");border-radius:8px;padding:12px;overflow-x:auto;}
            .markdown-body code{font-family:"SF Mono","JetBrains Mono",monospace;font-size:13px;background:\(isDark ? "#2d2d2d" : "#f6f8fa");border-radius:4px;padding:2px 6px;}
            .markdown-body pre code{background:transparent;padding:0;border-radius:0;}
            .markdown-body img{max-width:100%;border-radius:8px;margin:8px 0;}
            .markdown-body table{border-collapse:collapse;width:100%;}
            .markdown-body table th,.markdown-body table td{border:1px solid \(isDark ? "#444" : "#ddd");padding:6px 10px;}
            .markdown-body blockquote{border-left:3px solid \(isDark ? "#555" : "#ddd");padding-left:16px;color:\(isDark ? "#aaa" : "#666");margin:8px 0;}
            .katex-display{margin:12px 0!important;overflow-x:auto;}
            .katex{font-size:1.05em!important;}
            .canvas-replace-notice{color:#10b981;font-weight:600;display:block;margin:8px 0;padding:6px 12px;border-left:3px solid #10b981;background:\(isDark ? "rgba(16,185,129,0.1)" : "rgba(16,185,129,0.05)");border-radius:4px;}
            .thinking-text{color:\(isDark ? "#9ca3af" : "#6b7280");font-style:italic;font-size:0.85em;white-space:pre-wrap;padding-left:12px;margin-bottom:4px;opacity:0.8;}
            hr{border:none;border-top:1px solid \(isDark ? "#333" : "#ddd");margin:16px 0;}
            a{color:#10b981;text-decoration:none;}
        </style>
        </head>
        <body>
        <div class="markdown-body"><div id="content"></div></div>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/marked/11.1.1/marked.min.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.9/katex.min.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.9/contrib/auto-render.min.js"></script>
        <script>
        function renderMath(container) {
            if (window.renderMathInElement) {
                try { window.renderMathInElement(container, { delimiters: [{left:'$$',right:'$$',display:true},{left:'\\\\[',right:'\\\\]',display:true},{left:'$',right:'$',display:false}], throwOnError:false }); }
                catch(e){}
            }
        }
        function renderContent() {
            const raw = `\(escaped)`;
            const container = document.getElementById('content');
            let html = raw;
            html = html.replace(/\\[replace\\]\\s*\\nstart:(\\d+)\\s*\\nend:(\\d+)\\s*\\n```\\n?([\\s\\S]*?)```/g, function(match,start,end,code) {
                const lines = code.split('\\n').filter(l=>l.length>0||code.endsWith('\\n')).length;
                return `<span class="canvas-replace-notice">修改了画布代码：canvas[replace]with[${lines}行]。</span>`;
            });
            if (typeof marked !== 'undefined') { html = marked.parse(html); }
            container.innerHTML = html;
            if (typeof hljs !== 'undefined') { container.querySelectorAll('pre code').forEach(el=>hljs.highlightElement(el)); }
            renderMath(container);
            const height = document.body.scrollHeight;
            window.webkit.messageHandlers.heightChanged.postMessage(height);
        }
        document.addEventListener('DOMContentLoaded', renderContent);
        window.addEventListener('load', function(){ setTimeout(renderContent, 100); });
        const observer = new ResizeObserver(()=>{
            const h = document.body.scrollHeight;
            window.webkit.messageHandlers.heightChanged.postMessage(h);
        });
        observer.observe(document.body);
        </script>
        </body></html>
        """
    }
}

// 独立子视图以避免类型检查超时
struct AttachmentsScrollView: View {
    let attachments: [Attachment]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { att in
                    if att.isImage, let url = att.fullDataUrl, let data = try? Data(contentsOf: URL(string: url)!), let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "doc").font(.caption)
                            Text(att.name).font(.caption).lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct GeneratedImagesScrollView: View {
    let images: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images, id: \.self) { img in
                    if let data = try? Data(contentsOf: URL(string: img)!), let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct MessageBubbleView: View {
    let message: Message
    let isDark: Bool
    let onRetry: (() -> Void)?
    let onCopy: (() -> Void)?
    let onDownload: (() -> Void)?

    @State private var webViewHeight: CGFloat = 50

    var body: some View {
        let isUser = message.role == .user
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            if !isUser && !(message.reasoning?.isEmpty ?? true) {
                Text(message.reasoning ?? "")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .italic()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                MessageWebView(content: message.content, isDark: isDark, height: $webViewHeight)
                    .frame(height: max(40, webViewHeight))

                if let attachments = message.attachments, !attachments.isEmpty {
                    AttachmentsScrollView(attachments: attachments)
                }

                if let images = message.generatedImages, !images.isEmpty {
                    GeneratedImagesScrollView(images: images)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isUser
                    ? (isDark ? Color.blue.opacity(0.3) : Color.blue.opacity(0.1))
                    : (isDark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.05))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 0.5))

            if !isUser {
                HStack(spacing: 12) {
                    if let onRetry = onRetry {
                        Button(action: onRetry) { Label("重试", systemImage: "arrow.clockwise").font(.caption).foregroundColor(.gray) }
                            .buttonStyle(.plain)
                    }
                    if let onCopy = onCopy {
                        Button(action: onCopy) { Label("复制", systemImage: "doc.on.doc").font(.caption).foregroundColor(.gray) }
                            .buttonStyle(.plain)
                    }
                    if let onDownload = onDownload {
                        Button(action: onDownload) { Label("下载", systemImage: "square.and.arrow.down").font(.caption).foregroundColor(.gray) }
                            .buttonStyle(.plain)
                    }
                    if let model = message.model {
                        Text(model).font(.caption2).foregroundColor(.gray.opacity(0.6))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.horizontal, 8)
    }
}

// MARK: - 输入区域

struct InputAreaView: View {
    @ObservedObject var appState: AppState
    @Binding var inputText: String
    @Binding var isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttach: () -> Void
    let onVoice: () -> Void
    let onToggleImageMode: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if !appState.currentAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.currentAttachments.indices, id: \.self) { idx in
                            let att = appState.currentAttachments[idx]
                            HStack(spacing: 4) {
                                if att.isImage, let url = att.fullDataUrl, let data = try? Data(contentsOf: URL(string: url)!), let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Image(systemName: "doc").font(.caption)
                                }
                                Text(att.name).font(.caption).lineLimit(1).frame(maxWidth: 80)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                Button(action: { appState.currentAttachments.remove(at: idx) }) {
                                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.gray)
                                }
                                .offset(x: 10, y: -10),
                                alignment: .topTrailing
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(modelOptions, id: \.self) { model in
                        Button(action: { appState.selectedModel = model }) {
                            HStack { Text(model); if model == appState.selectedModel { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(appState.selectedModel).font(.caption).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.gray.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                Button(action: onToggleImageMode) {
                    Image(systemName: appState.isImageMode ? "photo.fill" : "photo")
                        .font(.caption)
                        .padding(6)
                        .background(appState.isImageMode ? Color.green.opacity(0.3) : Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Text("预估 tokens: \(estimateTokens())").font(.caption2).foregroundColor(.gray)
            }
            .padding(.horizontal, 4)

            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onAttach) {
                    Image(systemName: "plus").font(.system(size: 18)).frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                TextEditor(text: $inputText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minHeight: 36, maxHeight: 120)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .focused($isFocused)

                Button(action: onVoice) {
                    Image(systemName: "mic").font(.system(size: 18)).frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                if isGenerating {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill").font(.system(size: 18)).frame(width: 36, height: 36)
                            .background(Color.red.opacity(0.8)).foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold)).frame(width: 36, height: 36)
                            .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appState.currentAttachments.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appState.currentAttachments.isEmpty)
                }
            }
        }
        .padding(12)
        .background(
            (appState.isDarkMode ? Color.black.opacity(0.3) : Color.white.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal)
    }

    private func estimateTokens() -> Int {
        let text = inputText + appState.currentAttachments.map { $0.data ?? "" }.joined()
        if text.isEmpty { return 0 }
        let chinese = text.filter { $0 >= "\u{4e00}" && $0 <= "\u{9fff}" }.count
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        return chinese * 2 + words
    }

    private let modelOptions = [
        "gpt-5.5-2026-04-24", "gpt-5.5", "gemini-3.5-flash",
        "DeepSeek-V4-Flash", "DeepSeek-V4-Pro",
        "claude-opus-4-8", "claude-opus-4-7",
        "qwen3.6-plus", "qwen3.5-plus",
        "gpt-5.4", "gpt-5.4-pro", "gpt-5.2", "gpt-5.2-pro"
    ]
}

// MARK: - 对话列表

struct ChatListView: View {
    @ObservedObject var appState: AppState
    @Binding var showingSidebar: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { appState.createNewChat(); showingSidebar = false }) {
                HStack { Image(systemName: "plus"); Text("新建对话").font(.headline) }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.blue.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain).padding(.horizontal).padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appState.chats) { chat in
                        Button(action: {
                            appState.activeChatId = chat.id
                            appState.currentAttachments = []
                            if let chat = appState.getActiveChat() {
                                appState.canvasEnabled = chat.canvasEnabled
                                appState.canvasCode = chat.canvasCode.joined(separator: "\n")
                            }
                            showingSidebar = false
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.title).font(.subheadline).lineLimit(1)
                                    Text(chat.messages.last?.content ?? "空对话").font(.caption).foregroundColor(.gray).lineLimit(1)
                                }
                                Spacer()
                                if chat.id == appState.activeChatId {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.blue).font(.caption)
                                }
                                Button(action: { appState.deleteChat(chat.id) }) {
                                    Image(systemName: "trash").foregroundColor(.red.opacity(0.6)).font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(
                                chat.id == appState.activeChatId
                                    ? (appState.isDarkMode ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.top, 4)
            }

            Spacer()

            Button(action: { appState.showingSettings = true }) {
                HStack { Image(systemName: "gear"); Text("设置") }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color.gray.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain).padding(.horizontal).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appState.isDarkMode ? Color.black.opacity(0.9) : Color.white.opacity(0.95))
    }
}

// MARK: - 设置视图

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var tempSystemPrompt = ""
    @State private var tempTemperature = 0.7
    @State private var tempApiKey = ""
    @State private var tempBaseURL = ""
    @State private var tempMaxTokens = "0"
    @State private var tempFontSize: FontSize = .medium
    @State private var tempBgIndex = 1
    @State private var tempLayout: LayoutMode = .classic
    @State private var tempCanvasFontSize: CGFloat = 14
    @State private var tempVoiceModel = "whisper-1"
    @State private var tempCloudEnabled = false
    @State private var tempLcAppId = ""
    @State private var tempLcApiKey = ""
    @State private var tempLcMasterKey = ""
    @State private var tempLcBaseURL = ""
    @State private var memories: [String] = []

    var body: some View {
        NavigationView {
            Form {
                Section("AI 对话") {
                    VStack(alignment: .leading) {
                        Text("系统提示词").font(.caption).foregroundColor(.gray)
                        TextEditor(text: $tempSystemPrompt).frame(height: 80)
                            .scrollContentBackground(.hidden)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading) {
                        Text("随机性: \(String(format: "%.1f", tempTemperature))").font(.caption)
                        Slider(value: $tempTemperature, in: 0...2, step: 0.1)
                    }
                }

                Section("API 配置") {
                    SecureField("API Key", text: $tempApiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Base URL", text: $tempBaseURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        TextField("最大 Tokens (0=不限)", text: $tempMaxTokens).keyboardType(.numberPad)
                    }
                }

                Section("外观") {
                    Toggle("深色模式", isOn: $appState.isDarkMode)
                    Picker("字体大小", selection: $tempFontSize) {
                        Text("小").tag(FontSize.small)
                        Text("中").tag(FontSize.medium)
                        Text("大").tag(FontSize.large)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    Picker("背景图片", selection: $tempBgIndex) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("4").tag(4)
                        Text("5").tag(5)
                        Text("6").tag(6)
                    }
                }

                Section("布局与Canvas") {
                    Picker("布局模式", selection: $tempLayout) {
                        Text("经典").tag(LayoutMode.classic)
                        Text("分栏").tag(LayoutMode.split)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    VStack {
                        Text("Canvas 字体大小: \(Int(tempCanvasFontSize))")
                        Slider(value: $tempCanvasFontSize, in: 10...20, step: 1)
                    }
                }

                Section("语音输入") {
                    Picker("语音模型", selection: $tempVoiceModel) {
                        Text("whisper-1").tag("whisper-1")
                        Text("whisper-base").tag("whisper-base")
                        Text("whisper-large").tag("whisper-large")
                    }
                }

                Section("云端记忆 (LeanCloud)") {
                    Toggle("启用云端", isOn: $tempCloudEnabled)
                    if tempCloudEnabled {
                        TextField("App ID", text: $tempLcAppId)
                        SecureField("API Key", text: $tempLcApiKey)
                        SecureField("Master Key", text: $tempLcMasterKey)
                        TextField("Base URL", text: $tempLcBaseURL)
                        Button("立即同步") {
                            appState.lcAppId = tempLcAppId
                            appState.lcApiKey = tempLcApiKey
                            appState.lcMasterKey = tempLcMasterKey
                            appState.lcBaseURL = tempLcBaseURL
                            appState.isCloudEnabled = tempCloudEnabled
                            appState.syncToCloud()
                            appState.fetchMemories()
                            memories = appState.memories
                        }
                        if !memories.isEmpty {
                            VStack(alignment: .leading) {
                                Text("记忆列表").font(.caption).bold()
                                ForEach(memories, id: \.self) { mem in
                                    Text("• \(mem)").font(.caption)
                                }
                            }
                        }
                    }
                }

                Section("操作") {
                    Button("清除所有对话") {
                        appState.chats.removeAll()
                        appState.createNewChat()
                    }
                    .foregroundColor(.red)
                    Button("重置设置") {
                        tempSystemPrompt = ""
                        tempTemperature = 0.7
                        tempApiKey = "sk-FsuAh4g9yaBtkTVQEf53F3473b3d4bD9A2822d17EbFbA6B8"
                        tempBaseURL = "https://api.vveai.com/v1"
                        tempMaxTokens = "0"
                        tempFontSize = .medium
                        tempBgIndex = 1
                        tempLayout = .classic
                        tempCanvasFontSize = 14
                        tempVoiceModel = "whisper-1"
                        tempCloudEnabled = false
                        tempLcAppId = ""
                        tempLcApiKey = ""
                        tempLcMasterKey = ""
                        tempLcBaseURL = ""
                        memories = []
                        appState.systemPrompt = ""
                        appState.temperature = 0.7
                        appState.apiKey = "sk-FsuAh4g9yaBtkTVQEf53F3473b3d4bD9A2822d17EbFbA6B8"
                        appState.baseURL = "https://api.vveai.com/v1"
                        appState.maxTokens = 0
                        appState.fontSize = .medium
                        appState.backgroundImageIndex = 1
                        appState.layoutMode = .classic
                        appState.canvasFontSize = 14
                        appState.voiceModel = "whisper-1"
                        appState.isCloudEnabled = false
                        appState.lcAppId = ""
                        appState.lcApiKey = ""
                        appState.lcMasterKey = ""
                        appState.lcBaseURL = ""
                        appState.memories = []
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        appState.systemPrompt = tempSystemPrompt
                        appState.temperature = tempTemperature
                        appState.apiKey = tempApiKey
                        appState.baseURL = tempBaseURL
                        appState.maxTokens = Int(tempMaxTokens) ?? 0
                        appState.fontSize = tempFontSize
                        appState.backgroundImageIndex = tempBgIndex
                        appState.layoutMode = tempLayout
                        appState.canvasFontSize = tempCanvasFontSize
                        appState.voiceModel = tempVoiceModel
                        appState.isCloudEnabled = tempCloudEnabled
                        appState.lcAppId = tempLcAppId
                        appState.lcApiKey = tempLcApiKey
                        appState.lcMasterKey = tempLcMasterKey
                        appState.lcBaseURL = tempLcBaseURL
                        appState.fetchMemories()
                        dismiss()
                    }
                }
            }
            .onAppear {
                tempSystemPrompt = appState.systemPrompt
                tempTemperature = appState.temperature
                tempApiKey = appState.apiKey
                tempBaseURL = appState.baseURL
                tempMaxTokens = String(appState.maxTokens)
                tempFontSize = appState.fontSize
                tempBgIndex = appState.backgroundImageIndex
                tempLayout = appState.layoutMode
                tempCanvasFontSize = appState.canvasFontSize
                tempVoiceModel = appState.voiceModel
                tempCloudEnabled = appState.isCloudEnabled
                tempLcAppId = appState.lcAppId
                tempLcApiKey = appState.lcApiKey
                tempLcMasterKey = appState.lcMasterKey
                tempLcBaseURL = appState.lcBaseURL
                memories = appState.memories
            }
        }
    }
}

// MARK: - 图片选择器

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                parent.isPresented = false
                return
            }
            provider.loadObject(ofClass: UIImage.self) { image, _ in

    let selectedImage = image as? UIImage

    DispatchQueue.main.async {
        self.parent.selectedImage = selectedImage
        self.parent.isPresented = false
    }
}
        }
    }
}

// MARK: - 主视图

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var inputText = ""
    @State private var showingSidebar = false
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isGenerating = false
    @State private var cancellable: AnyCancellable?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var audioData = Data()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                let bgName = "\(appState.backgroundImageIndex).JPG"
                (appState.isDarkMode ? Color.black : Color.white)
                    .ignoresSafeArea()
                    .overlay(
                        Image(bgName)
                            .resizable()
                            .scaledToFill()
                            .opacity(appState.isDarkMode ? 0.3 : 0.6)
                            .ignoresSafeArea()
                    )

                HStack(spacing: 0) {
                    if geometry.size.width > 768 {
                        ChatListView(appState: appState, showingSidebar: $showingSidebar)
                            .frame(width: 280)
                            .transition(.move(edge: .leading))
                    }

                    ChatView(
                        appState: appState,
                        inputText: $inputText,
                        isGenerating: $isGenerating,
                        onSend: sendMessage,
                        onStop: stopGeneration,
                        onAttach: { showingImagePicker = true },
                        onVoice: toggleRecording,
                        onToggleImageMode: toggleImageMode,
                        onToggleSidebar: { withAnimation(.spring()) { showingSidebar.toggle() } }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if geometry.size.width <= 768 && showingSidebar {
                    Color.black.opacity(0.4).ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring()) { showingSidebar = false } }
                    ChatListView(appState: appState, showingSidebar: $showingSidebar)
                        .frame(width: 300)
                        .transition(.move(edge: .leading))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .preferredColorScheme(appState.isDarkMode ? .dark : .light)
        .sheet(isPresented: $appState.showingSettings) {
            SettingsView(appState: appState)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage, isPresented: $showingImagePicker)
                .onDisappear {
                    if let image = selectedImage { addImageAttachment(image) }
                    selectedImage = nil
                }
        }
        .onAppear {
            if let chat = appState.getActiveChat() {
                appState.canvasEnabled = chat.canvasEnabled
                appState.canvasCode = chat.canvasCode.joined(separator: "\n")
            }
        }
        .onChange(of: appState.activeChatId) { _ in
            if let chat = appState.getActiveChat() {
                appState.canvasEnabled = chat.canvasEnabled
                appState.canvasCode = chat.canvasCode.joined(separator: "\n")
            }
            appState.currentAttachments = []
        }
    }

    private func addImageAttachment(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }
        let base64 = data.base64EncodedString()
        let url = "data:image/jpeg;base64,\(base64)"
        let att = Attachment(
            name: "图片 \(appState.currentAttachments.count + 1).jpg",
            type: "image/jpeg",
            data: base64,
            fullDataUrl: url,
            size: data.count,
            isImage: true,
            isText: false
        )
        appState.currentAttachments.append(att)
    }

    private func toggleImageMode() {
        appState.isImageMode.toggle()
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !appState.currentAttachments.isEmpty else { return }
        guard let chatId = appState.activeChatId else { return }

        if appState.isImageMode {
            sendImageMessage(prompt: text)
            return
        }

        if text.hasPrefix("/canvas") {
            appState.canvasEnabled = true
            var chat = appState.getActiveChat()!
            chat.canvasEnabled = true
            if chat.canvasCode.isEmpty { chat.canvasCode = [""] }
            appState.updateChat(chat)
        }

        let userMsg = Message(
            role: .user,
            content: text,
            attachments: appState.currentAttachments.isEmpty ? nil : appState.currentAttachments
        )
        appState.addMessage(userMsg, to: chatId)

        let attachments = appState.currentAttachments
        inputText = ""
        appState.currentAttachments = []

        isGenerating = true
        appState.isGenerating = true

        let assistantMsg = Message(role: .assistant, content: "", model: appState.selectedModel)
        appState.addMessage(assistantMsg, to: chatId)

        guard let chat = appState.getActiveChat() else {
            isGenerating = false
            appState.isGenerating = false
            return
        }

        var history = chat.messages.filter { $0.id != assistantMsg.id }
        if let last = history.last, last.role == .user, last.id == userMsg.id {
            var mutable = last
            mutable.attachments = attachments
            history[history.count - 1] = mutable
        }

        if appState.canvasEnabled && !appState.canvasCode.isEmpty {
            if let lastIdx = history.indices.last, history[lastIdx].role == .user {
                var last = history[lastIdx]
                last.content += "\n\n【Canvas代码】\n\(appState.canvasCode)\n"
                history[lastIdx] = last
            }
        }

        let service = APIService(appState: appState)
        cancellable = service.sendMessage(
            chatId: chatId,
            messages: history,
            model: appState.selectedModel,
            onChunk: { content, reasoning in
                appState.updateLastMessage(content, reasoning: reasoning, in: chatId)
            },
            onComplete: { result in
                DispatchQueue.main.async {
                    isGenerating = false
                    appState.isGenerating = false
                    if case .failure(let error) = result {
                        appState.updateLastMessage("❌ 错误: \(error.localizedDescription)", in: chatId)
                    }
                    if let chat = appState.getActiveChat(), appState.canvasEnabled {
                        let lastMsg = chat.messages.last
                        if let content = lastMsg?.content {
                            parseCanvasReplace(content)
                        }
                    }
                }
            }
        )
    }

    private func parseCanvasReplace(_ content: String) {
        let pattern = #"\[replace\]\s*\nstart:(\d+)\s*\nend:(\d+)\s*\n```\n?([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let nsString = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return }

        var lines = appState.canvasCode.components(separatedBy: "\n")
        for match in matches.reversed() {
            let startStr = nsString.substring(with: match.range(at: 1))
            let endStr = nsString.substring(with: match.range(at: 2))
            let codeBlock = nsString.substring(with: match.range(at: 3))
            guard let start = Int(startStr), let end = Int(endStr) else { continue }
            let startIdx = start - 1
            let endIdx = end - 1
            guard startIdx >= 0, endIdx < lines.count, startIdx <= endIdx else { continue }
            let newLines = codeBlock.components(separatedBy: "\n")
            lines.replaceSubrange(startIdx...endIdx, with: newLines)
        }
        appState.canvasCode = lines.joined(separator: "\n")
        var chat = appState.getActiveChat()!
        chat.canvasCode = lines
        appState.updateChat(chat)
    }

    private func sendImageMessage(prompt: String) {
        guard let chatId = appState.activeChatId else { return }
        let model = appState.selectedModel
        var imageBase64: String? = nil
        if appState.isImageEditMode, let lastImage = appState.getActiveChat()?.messages.last(where: { $0.generatedImages?.isEmpty == false })?.generatedImages?.last {
            imageBase64 = lastImage
        } else if !appState.currentAttachments.isEmpty, let att = appState.currentAttachments.first(where: { $0.isImage }), let url = att.fullDataUrl {
            imageBase64 = url
        }

        let userMsg = Message(role: .user, content: prompt, attachments: appState.currentAttachments)
        appState.addMessage(userMsg, to: chatId)
        inputText = ""
        appState.currentAttachments = []

        isGenerating = true
        appState.isGenerating = true
        let assistantMsg = Message(role: .assistant, content: "生成中...", model: model)
        appState.addMessage(assistantMsg, to: chatId)

        let service = APIService(appState: appState)
        cancellable = service.generateImage(prompt: prompt, model: model, imageBase64: imageBase64) { result in
            DispatchQueue.main.async {
                isGenerating = false
                appState.isGenerating = false
                switch result {
                case .success(let dataUrl):
                    appState.updateLastMessage("生成完成", in: chatId)
                    if var chat = appState.getActiveChat() {
                        if let idx = chat.messages.indices.last, chat.messages[idx].role == .assistant {
                            chat.messages[idx].generatedImages = [dataUrl]
                            appState.updateChat(chat)
                        }
                    }
                case .failure(let error):
                    appState.updateLastMessage("❌ 生成失败: \(error.localizedDescription)", in: chatId)
                }
            }
        }
    }

    private func stopGeneration() {
        cancellable?.cancel()
        cancellable = nil
        isGenerating = false
        appState.isGenerating = false
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("音频会话设置失败: \(error)")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("recording.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("录音启动失败: \(error)")
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        guard let url = audioRecorder?.url else { return }
        do {
            let data = try Data(contentsOf: url)
            transcribeAudio(data)
        } catch {
            print("读取录音数据失败: \(error)")
        }
        audioRecorder = nil
    }

    private func transcribeAudio(_ data: Data) {
        let service = APIService(appState: appState)
        cancellable = service.transcribeAudio(audioData: data, model: appState.voiceModel) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    inputText += text
                case .failure(let error):
                    print("转录失败: \(error)")
                }
            }
        }
    }
}

// MARK: - 聊天视图

struct ChatView: View {
    @ObservedObject var appState: AppState
    @Binding var inputText: String
    @Binding var isGenerating: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttach: () -> Void
    let onVoice: () -> Void
    let onToggleImageMode: () -> Void
    let onToggleSidebar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onToggleSidebar) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 20))
                        .foregroundColor(appState.isDarkMode ? .white : .black)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(appState.getActiveChat()?.title ?? "新对话")
                    .font(.headline).lineLimit(1)

                Spacer()

                Button(action: { appState.showingSettings = true }) {
                    Image(systemName: "gear").font(.system(size: 20))
                        .foregroundColor(appState.isDarkMode ? .white : .black)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(
                (appState.isDarkMode ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                    .clipShape(Rectangle())
                    .shadow(color: Color.black.opacity(0.05), radius: 4, y: 1)
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        let messages = appState.getActiveChat()?.messages ?? []
                        ForEach(messages) { message in
                            MessageBubbleView(
                                message: message,
                                isDark: appState.isDarkMode,
                                onRetry: message.role == .assistant ? { handleRetry(message) } : nil,
                                onCopy: message.role == .assistant ? { copyMessage(message) } : nil,
                                onDownload: message.generatedImages?.isEmpty == false ? { downloadImage(message) } : nil
                            )
                            .id(message.id)
                            .padding(.horizontal, 8)
                        }
                        if isGenerating {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.7)
                                Text("AI 正在思考...").font(.caption).foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                            .id("loading")
                        }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: appState.getActiveChat()?.messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: isGenerating) { _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }

            InputAreaView(
                appState: appState,
                inputText: $inputText,
                isGenerating: $isGenerating,
                onSend: onSend,
                onStop: onStop,
                onAttach: onAttach,
                onVoice: onVoice,
                onToggleImageMode: onToggleImageMode
            )
            .padding(.vertical, 8)
        }
        .background(appState.isDarkMode ? Color.black : Color.white)
    }

    private func handleRetry(_ message: Message) {
        guard let chat = appState.getActiveChat(),
              let index = chat.messages.firstIndex(where: { $0.id == message.id }),
              index > 0 else { return }
        var updated = chat
        updated.messages.remove(at: index)
        appState.updateChat(updated)
        guard let lastUser = updated.messages.last, lastUser.role == .user else { return }
        appState.currentAttachments = lastUser.attachments ?? []
        inputText = lastUser.content
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onSend() }
    }

    private func copyMessage(_ message: Message) {
        UIPasteboard.general.string = message.content
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func downloadImage(_ message: Message) {
        guard let images = message.generatedImages, let first = images.first, let url = URL(string: first) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }.resume()
    }
}

@main
struct AIChatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
