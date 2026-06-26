import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers

// MARK: - 数据模型

/// 消息模型
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

/// 附件模型
struct Attachment: Identifiable, Codable {
    let id: String
    let name: String
    let type: String
    var data: String?         // 文本内容或base64数据
    var fullDataUrl: String?  // 图片的完整data URL
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

/// 对话模型
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
    @Published var apiKey: String = ""
    @Published var baseURL: String = "https://api.vveai.com/v1"
    @Published var maxTokens: Int = 0
    @Published var isDarkMode: Bool = false
    @Published var showingSettings = false
    @Published var showingSidebar = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadFromStorage()
        setupBindings()
    }

    private func setupBindings() {
        $chats
            .sink { [weak self] _ in
                self?.saveToStorage()
            }
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
    }

    private func loadFromStorage() {
        // 加载对话
        if let data = UserDefaults.standard.data(forKey: "chats"),
           let decoded = try? JSONDecoder().decode([Chat].self, from: data) {
            chats = decoded
        }

        // 加载设置
        systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt") ?? ""
        temperature = UserDefaults.standard.double(forKey: "temperature")
        if temperature == 0 { temperature = 0.7 }
        selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "gpt-5.5-2026-04-24"
        apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.vveai.com/v1"
        maxTokens = UserDefaults.standard.integer(forKey: "maxTokens")
        isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")

        // 如果对话为空，创建一个新对话
        if chats.isEmpty {
            createNewChat()
        } else {
            activeChatId = chats.first?.id
        }
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
        saveToStorage()
    }

    func deleteChat(_ chatId: String) {
        chats.removeAll { $0.id == chatId }
        if activeChatId == chatId {
            if let first = chats.first {
                activeChatId = first.id
            } else {
                createNewChat()
            }
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
}

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

        // 构建消息
        var apiMessages: [[String: Any]] = []

        // 系统消息
        var systemContent = appState.systemPrompt
        if !systemContent.isEmpty {
            apiMessages.append(["role": "system", "content": systemContent])
        }

        // 对话消息
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

        // 添加当前输入中的图片（从附件）
        if !appState.currentAttachments.isEmpty {
            let lastUserMsg = apiMessages.last(where: { $0["role"] as? String == "user" })
            if var content = lastUserMsg?["content"] as? String {
                // 简单文本，需要转换为多模态
                let index = apiMessages.firstIndex(where: { $0["role"] as? String == "user" && $0["content"] as? String == content })
                if let idx = index {
                    var contentArray: [[String: Any]] = [["type": "text", "text": content]]
                    for att in appState.currentAttachments where att.isImage && att.fullDataUrl != nil {
                        contentArray.append([
                            "type": "image_url",
                            "image_url": ["url": att.fullDataUrl!]
                        ])
                    }
                    apiMessages[idx]["content"] = contentArray
                }
            } else if var contentArray = lastUserMsg?["content"] as? [[String: Any]] {
                for att in appState.currentAttachments where att.isImage && att.fullDataUrl != nil {
                    contentArray.append([
                        "type": "image_url",
                        "image_url": ["url": att.fullDataUrl!]
                    ])
                }
                let index = apiMessages.firstIndex(where: { $0["role"] as? String == "user" && $0["content"] as? [[String: Any]] != nil })
                if let idx = index {
                    apiMessages[idx]["content"] = contentArray
                }
            }
        }

        // 构建请求体
        var body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": appState.temperature,
            "stream": true
        ]
        if maxTokens > 0 {
            body["max_tokens"] = maxTokens
        }

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的API地址"])))
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    onComplete(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无数据返回"])))
                }
                return
            }

            // 解析流式响应
            let decoder = JSONDecoder()
            let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []

            var fullContent = ""
            var reasoningContent = ""

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
                            DispatchQueue.main.async {
                                onChunk(fullContent, reasoningContent)
                            }
                        }
                        if let reasoning = delta["reasoning_content"] as? String {
                            reasoningContent += reasoning
                            DispatchQueue.main.async {
                                onChunk(fullContent, reasoningContent)
                            }
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                if !fullContent.isEmpty {
                    onComplete(.success(true))
                } else {
                    onComplete(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未能解析到有效内容"])))
                }
            }
        }

        task.resume()
        return AnyCancellable {
            task.cancel()
        }
    }

    func sendMessageStream(chatId: String, messages: [Message], model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let _ = self.sendMessage(chatId: chatId, messages: messages, model: model,
                onChunk: { content, reasoning in
                    continuation.yield(content)
                },
                onComplete: { result in
                    switch result {
                    case .success:
                        continuation.finish()
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                }
            )
        }
    }
}

// MARK: - WebView 消息渲染

struct MessageWebView: UIViewRepresentable {
    let content: String
    let isDark: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = buildHTML(content: content, isDark: isDark)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func buildHTML(content: String, isDark: Bool) -> String {
        let theme = isDark ? "github-dark" : "github"
        let bgColor = isDark ? "#1a1a1a" : "#ffffff"
        let textColor = isDark ? "#f0f0f0" : "#1f1f1f"

        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.5.0/github-markdown.min.css">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/\(theme).min.css">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.9/katex.min.css">
            <style>
                body {
                    background: \(bgColor);
                    color: \(textColor);
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    padding: 0;
                    margin: 0;
                    line-height: 1.6;
                    font-size: 15px;
                }
                .markdown-body {
                    background: \(bgColor);
                    color: \(textColor);
                    padding: 4px 0;
                    font-size: 15px;
                }
                .markdown-body pre {
                    background: \(isDark ? "#2d2d2d" : "#f6f8fa");
                    border-radius: 8px;
                    padding: 12px;
                    overflow-x: auto;
                }
                .markdown-body code {
                    font-family: "SF Mono", "JetBrains Mono", "Cascadia Code", monospace;
                    font-size: 13px;
                    background: \(isDark ? "#2d2d2d" : "#f6f8fa");
                    border-radius: 4px;
                    padding: 2px 6px;
                }
                .markdown-body pre code {
                    background: transparent;
                    padding: 0;
                    border-radius: 0;
                    font-size: 13px;
                }
                .markdown-body img {
                    max-width: 100%;
                    border-radius: 8px;
                    margin: 8px 0;
                }
                .markdown-body table {
                    border-collapse: collapse;
                    width: 100%;
                }
                .markdown-body table th,
                .markdown-body table td {
                    border: 1px solid \(isDark ? "#444" : "#ddd");
                    padding: 6px 10px;
                }
                .markdown-body blockquote {
                    border-left: 3px solid \(isDark ? "#555" : "#ddd");
                    padding-left: 16px;
                    color: \(isDark ? "#aaa" : "#666");
                    margin: 8px 0;
                }
                .katex-display {
                    margin: 12px 0 !important;
                    overflow-x: auto;
                    overflow-y: hidden;
                }
                .katex {
                    font-size: 1.05em !important;
                }
                .markdown-body .canvas-replace-notice {
                    color: #10b981;
                    font-weight: 600;
                    display: block;
                    margin: 8px 0;
                    padding: 6px 12px;
                    border-left: 3px solid #10b981;
                    background: \(isDark ? "rgba(16,185,129,0.1)" : "rgba(16,185,129,0.05)");
                    border-radius: 4px;
                }
                .markdown-body .thinking-text {
                    color: \(isDark ? "#9ca3af" : "#6b7280");
                    font-style: italic;
                    font-size: 0.85em;
                    white-space: pre-wrap;
                    padding-left: 12px;
                    margin-bottom: 4px;
                    opacity: 0.8;
                }
                .markdown-body hr {
                    border: none;
                    border-top: 1px solid \(isDark ? "#333" : "#ddd");
                    margin: 16px 0;
                }
                .markdown-body a {
                    color: #10b981;
                    text-decoration: none;
                }
                .markdown-body a:hover {
                    text-decoration: underline;
                }
            </style>
        </head>
        <body>
            <div class="markdown-body">
                <div id="content"></div>
            </div>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/marked/11.1.1/marked.min.js">
            </script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js">
            </script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.9/katex.min.js">
            </script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.9/contrib/auto-render.min.js">
            </script>
            <script>
                function renderMath(container) {
                    if (window.renderMathInElement) {
                        try {
                            window.renderMathInElement(container, {
                                delimiters: [
                                    {left: '$$', right: '$$', display: true},
                                    {left: '\\\\[', right: '\\\\]', display: true},
                                    {left: '$', right: '$', display: false},
                                    {left: '\\\\(', right: '\\\\)', display: false}
                                ],
                                throwOnError: false
                            });
                        } catch(e) {}
                    }
                }

                function renderContent() {
                    const raw = `\(escapedContent)`;
                    const container = document.getElementById('content');

                    let html = raw;

                    // 替换 canvas 标记
                    html = html.replace(/\\[replace\\]\\s*\\nstart:(\\d+)\\s*\\nend:(\\d+)\\s*\\n```\\n?([\\s\\S]*?)```/g,
                        function(match, start, end, code) {
                            const lines = code.split('\\n').filter(l => l.length > 0 || code.endsWith('\\n')).length;
                            return `<span class="canvas-replace-notice">修改了画布代码：canvas[replace]with[${lines}行]。</span>`;
                        }
                    );

                    // 渲染 Markdown
                    if (typeof marked !== 'undefined') {
                        html = marked.parse(html);
                    }

                    container.innerHTML = html;

                    // 高亮代码
                    if (typeof hljs !== 'undefined') {
                        container.querySelectorAll('pre code').forEach(el => {
                            hljs.highlightElement(el);
                        });
                    }

                    // 渲染数学公式
                    renderMath(container);

                    // 自动调整高度
                    const height = document.body.scrollHeight;
                    window.webkit.messageHandlers.heightChanged.postMessage(height);
                }

                document.addEventListener('DOMContentLoaded', renderContent);
                window.addEventListener('load', function() {
                    setTimeout(renderContent, 100);
                });

                // 监听高度变化
                const observer = new ResizeObserver(() => {
                    const height = document.body.scrollHeight;
                    window.webkit.messageHandlers.heightChanged.postMessage(height);
                });
                observer.observe(document.body);

                // 在内容变化后重新计算
                document.addEventListener('contentChange', function() {
                    setTimeout(renderContent, 50);
                });
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - 消息气泡视图

struct MessageBubbleView: View {
    let message: Message
    let isDark: Bool
    let onRetry: (() -> Void)?
    let onCopy: (() -> Void)?
    let onDownload: (() -> Void)?

    @State private var webViewHeight: CGFloat = 50
    @State private var isGenerating = false

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
                if message.content.isEmpty && isGenerating {
                    HStack(spacing: 4) {
                        Text("思考中")
                            .font(.footnote)
                            .foregroundColor(.gray)
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                } else {
                    // 使用WebView渲染内容
                    MessageWebView(content: message.content, isDark: isDark)
                        .frame(height: webViewHeight)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        webViewHeight = max(50, geo.size.height)
                                    }
                                    .onChange(of: message.content) { _ in
                                        webViewHeight = 50
                                    }
                            }
                        )
                        .onAppear {
                            // 等待WebView加载完成
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                webViewHeight = max(50, webViewHeight)
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WebViewHeightChanged"))) { notification in
                            if let height = notification.userInfo?["height"] as? CGFloat {
                                withAnimation(.none) {
                                    webViewHeight = max(50, height)
                                }
                            }
                        }
                }

                // 附件
                if let attachments = message.attachments, !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(attachments) { att in
                                if att.isImage, let url = att.fullDataUrl, let imageData = try? Data(contentsOf: URL(string: url)!) {
                                    if let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc")
                                            .font(.caption)
                                        Text(att.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // 生成的图片
                if let images = message.generatedImages, !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(images, id: \.self) { img in
                                if let imageData = try? Data(contentsOf: URL(string: img)!),
                                   let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                        .onTapGesture {
                                            // 查看大图
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
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
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 0.5)
            )

            // 操作按钮
            if !isUser && message.role == .assistant {
                HStack(spacing: 12) {
                    if let onRetry = onRetry {
                        Button(action: onRetry) {
                            Label("重试", systemImage: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    if let onCopy = onCopy {
                        Button(action: onCopy) {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    if let onDownload = onDownload {
                        Button(action: onDownload) {
                            Label("下载", systemImage: "square.and.arrow.down")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    if let model = message.model {
                        Text(model)
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.6))
                            .padding(.leading, 4)
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

    @FocusState private var isFocused: Bool
    @State private var height: CGFloat = 40

    var body: some View {
        VStack(spacing: 8) {
            // 附件预览
            if !appState.currentAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.currentAttachments.indices, id: \.self) { index in
                            let att = appState.currentAttachments[index]
                            HStack(spacing: 4) {
                                if att.isImage, let url = att.fullDataUrl, let imageData = try? Data(contentsOf: URL(string: url)!) {
                                    if let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                } else {
                                    Image(systemName: "doc")
                                        .font(.caption)
                                }
                                Text(att.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: 80)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                Button(action: {
                                    appState.currentAttachments.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .offset(x: 10, y: -10),
                                alignment: .topTrailing
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // 模型选择
            HStack(spacing: 8) {
                Menu {
                    ForEach(modelOptions, id: \.self) { model in
                        Button(action: {
                            appState.selectedModel = model
                        }) {
                            HStack {
                                Text(model)
                                if model == appState.selectedModel {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(appState.selectedModel)
                            .font(.caption)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Spacer()

                Text("预估 tokens: \(estimateTokens())")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 4)

            // 输入框
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onAttach) {
                    Image(systemName: "plus")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                TextEditor(text: $inputText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 36, maxHeight: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .focused($isFocused)
                    .onChange(of: inputText) { _ in
                        updateHeight()
                    }

                if isGenerating {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18))
                            .frame(width: 36, height: 36)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appState.currentAttachments.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func updateHeight() {
        // 自动调整高度
    }

    private func estimateTokens() -> Int {
        let text = inputText + appState.currentAttachments.map { $0.data ?? "" }.joined()
        if text.isEmpty { return 0 }
        let chinese = text.filter { $0 >= "\u{4e00}" && $0 <= "\u{9fff}" }.count
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        return chinese * 2 + words
    }

    private let modelOptions = [
        "gpt-5.5-2026-04-24",
        "gpt-5.5",
        "gemini-3.5-flash",
        "DeepSeek-V4-Flash",
        "DeepSeek-V4-Pro",
        "claude-opus-4-8",
        "claude-opus-4-7",
        "qwen3.6-plus",
        "qwen3.5-plus",
        "gpt-5.4",
        "gpt-5.4-pro",
        "gpt-5.2",
        "gpt-5.2-pro"
    ]
}

// MARK: - 对话列表

struct ChatListView: View {
    @ObservedObject var appState: AppState
    @Binding var showingSidebar: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 新建对话按钮
            Button(action: {
                appState.createNewChat()
                showingSidebar = false
            }) {
                HStack {
                    Image(systemName: "plus")
                    Text("新建对话")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 8)

            // 对话列表
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appState.chats) { chat in
                        Button(action: {
                            appState.activeChatId = chat.id
                            appState.currentAttachments = []
                            showingSidebar = false
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(chat.messages.last?.content ?? "空对话")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if chat.id == appState.activeChatId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                                Button(action: {
                                    appState.deleteChat(chat.id)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.6))
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
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
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            Spacer()

            // 设置按钮
            Button(action: {
                appState.showingSettings = true
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("设置")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            appState.isDarkMode ? Color.black.opacity(0.9) : Color.white.opacity(0.95)
        )
    }
}

// MARK: - 设置视图

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var tempSystemPrompt: String = ""
    @State private var tempTemperature: Double = 0.7
    @State private var tempApiKey: String = ""
    @State private var tempBaseURL: String = ""
    @State private var tempMaxTokens: String = "0"

    var body: some View {
        NavigationView {
            Form {
                Section("AI 对话设置") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("系统提示词")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextEditor(text: $tempSystemPrompt)
                            .frame(height: 80)
                            .scrollContentBackground(.hidden)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("回复随机性: \(String(format: "%.1f", tempTemperature))")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Slider(value: $tempTemperature, in: 0...2, step: 0.1)
                    }
                }

                Section("API 配置") {
                    SecureField("API Key", text: $tempApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Base URL", text: $tempBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("最大 Tokens (0=不限制)", text: $tempMaxTokens)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("外观") {
                    Toggle("深色模式", isOn: $appState.isDarkMode)
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
                        tempApiKey = ""
                        tempBaseURL = "https://api.vveai.com/v1"
                        tempMaxTokens = "0"
                        appState.systemPrompt = ""
                        appState.temperature = 0.7
                        appState.apiKey = ""
                        appState.baseURL = "https://api.vveai.com/v1"
                        appState.maxTokens = 0
                        UserDefaults.standard.removeObject(forKey: "systemPrompt")
                        UserDefaults.standard.removeObject(forKey: "temperature")
                        UserDefaults.standard.removeObject(forKey: "apiKey")
                        UserDefaults.standard.removeObject(forKey: "baseURL")
                        UserDefaults.standard.removeObject(forKey: "maxTokens")
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        appState.systemPrompt = tempSystemPrompt
                        appState.temperature = tempTemperature
                        appState.apiKey = tempApiKey
                        appState.baseURL = tempBaseURL
                        appState.maxTokens = Int(tempMaxTokens) ?? 0
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
            }
        }
    }
}

// MARK: - 图片选择器

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                (appState.isDarkMode ? Color.black : Color.white)
                    .ignoresSafeArea()

                // 主内容
                HStack(spacing: 0) {
                    // 侧边栏 (桌面)
                    if geometry.size.width > 768 {
                        ChatListView(appState: appState, showingSidebar: $showingSidebar)
                            .frame(width: 280)
                            .transition(.move(edge: .leading))
                    }

                    // 聊天区域
                    ChatView(
                        appState: appState,
                        inputText: $inputText,
                        isGenerating: $isGenerating,
                        onSend: sendMessage,
                        onStop: stopGeneration,
                        onAttach: { showingImagePicker = true },
                        onToggleSidebar: {
                            withAnimation(.spring()) {
                                showingSidebar.toggle()
                            }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // 侧边栏 (移动端)
                if geometry.size.width <= 768 && showingSidebar {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring()) {
                                showingSidebar = false
                            }
                        }

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
                    if let image = selectedImage {
                        addImageAttachment(image)
                        selectedImage = nil
                    }
                }
        }
        .onChange(of: appState.activeChatId) { _ in
            appState.currentAttachments = []
        }
    }

    private func addImageAttachment(_ image: UIImage) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return }
        let base64 = imageData.base64EncodedString()
        let dataUrl = "data:image/jpeg;base64,\(base64)"

        let attachment = Attachment(
            name: "图片 \(appState.currentAttachments.count + 1).jpg",
            type: "image/jpeg",
            data: base64,
            fullDataUrl: dataUrl,
            size: imageData.count,
            isImage: true,
            isText: false
        )
        appState.currentAttachments.append(attachment)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !appState.currentAttachments.isEmpty else { return }

        guard let chatId = appState.activeChatId else { return }

        // 创建用户消息
        let userMessage = Message(
            role: .user,
            content: text,
            attachments: appState.currentAttachments.isEmpty ? nil : appState.currentAttachments
        )

        appState.addMessage(userMessage, to: chatId)

        // 清除输入和附件
        inputText = ""
        let attachments = appState.currentAttachments
        appState.currentAttachments = []

        isGenerating = true
        appState.isGenerating = true

        // 创建AI占位消息
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            model: appState.selectedModel
        )
        appState.addMessage(assistantMessage, to: chatId)

        // 构建消息列表
        guard let chat = appState.getActiveChat() else {
            isGenerating = false
            appState.isGenerating = false
            return
        }

        // 准备API消息（包含附件）
        var apiMessages: [Message] = []
        for msg in chat.messages {
            if msg.id == assistantMessage.id {
                // 跳过占位消息
                continue
            }
            if msg.role == .user && msg.id == userMessage.id {
                // 当前用户消息，添加附件
                var msgWithAtts = msg
                msgWithAtts.attachments = attachments
                apiMessages.append(msgWithAtts)
            } else {
                apiMessages.append(msg)
            }
        }

        // 添加当前的user消息（如果还没在列表中）
        if !apiMessages.contains(where: { $0.id == userMessage.id }) {
            var msgWithAtts = userMessage
            msgWithAtts.attachments = attachments
            apiMessages.append(msgWithAtts)
        }

        // 确保最后一条消息是用户消息
        if let last = apiMessages.last, last.role != .user {
            // 如果最后不是用户消息，需要调整
        }

        // 发送请求
        let service = APIService(appState: appState)

        cancellable = service.sendMessage(
            chatId: chatId,
            messages: apiMessages,
            model: appState.selectedModel,
            onChunk: { content, reasoning in
                // 更新AI消息
                appState.updateLastMessage(content, reasoning: reasoning, in: chatId)
            },
            onComplete: { result in
                DispatchQueue.main.async {
                    isGenerating = false
                    appState.isGenerating = false
                    if case .failure(let error) = result {
                        // 更新错误消息
                        let errorMsg = "❌ 错误: \(error.localizedDescription)"
                        appState.updateLastMessage(errorMsg, in: chatId)
                    }
                }
            }
        )
    }

    private func stopGeneration() {
        cancellable?.cancel()
        cancellable = nil
        isGenerating = false
        appState.isGenerating = false
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
    let onToggleSidebar: () -> Void

    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航
            HStack {
                Button(action: onToggleSidebar) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20))
                        .foregroundColor(appState.isDarkMode ? .white : .black)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(appState.getActiveChat()?.title ?? "新对话")
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button(action: {
                    appState.showingSettings = true
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 20))
                        .foregroundColor(appState.isDarkMode ? .white : .black)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                (appState.isDarkMode ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                    .clipShape(Rectangle())
                    .shadow(color: Color.black.opacity(0.05), radius: 4, y: 1)
            )

            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        let messages = appState.getActiveChat()?.messages ?? []
                        ForEach(messages) { message in
                            MessageBubbleView(
                                message: message,
                                isDark: appState.isDarkMode,
                                onRetry: message.role == .assistant ? {
                                    handleRetry(message)
                                } : nil,
                                onCopy: message.role == .assistant ? {
                                    copyMessage(message)
                                } : nil,
                                onDownload: message.generatedImages?.isEmpty == false ? {
                                    downloadImage(message)
                                } : nil
                            )
                            .id(message.id)
                            .padding(.horizontal, 8)
                            .onAppear {
                                if message.id == messages.last?.id {
                                    proxy.scrollTo(message.id, anchor: .bottom)
                                }
                            }
                        }

                        // 生成动画指示
                        if isGenerating {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("AI 正在思考...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                            .id("loading")
                        }

                        // 底部占位
                        Color.clear
                            .frame(height: 8)
                            .id("bottom")
                    }
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: appState.getActiveChat()?.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isGenerating) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollProxy = proxy
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            // 输入区域
            InputAreaView(
                appState: appState,
                inputText: $inputText,
                isGenerating: $isGenerating,
                onSend: onSend,
                onStop: onStop,
                onAttach: onAttach
            )
            .padding(.vertical, 8)
        }
        .background(
            appState.isDarkMode ? Color.black : Color.white
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func handleRetry(_ message: Message) {
        guard let chat = appState.getActiveChat(),
              let index = chat.messages.firstIndex(where: { $0.id == message.id }),
              index > 0 else { return }

        // 移除当前AI消息
        var updatedChat = chat
        updatedChat.messages.remove(at: index)
        appState.updateChat(updatedChat)

        // 获取最后一条用户消息
        guard let lastUserMsg = updatedChat.messages.last,
              lastUserMsg.role == .user else { return }

        // 重新发送
        let text = lastUserMsg.content
        let attachments = lastUserMsg.attachments ?? []

        appState.currentAttachments = attachments
        inputText = text

        // 触发发送
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onSend()
        }
    }

    private func copyMessage(_ message: Message) {
        UIPasteboard.general.string = message.content
        // 显示提示
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func downloadImage(_ message: Message) {
        guard let images = message.generatedImages,
              let firstImage = images.first,
              let url = URL(string: firstImage) else { return }

        // 下载图片
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            DispatchQueue.main.async {
                // 保存到相册
                if let image = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        }.resume()
    }
}

// MARK: - App Entry Point

@main
struct AIChatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    static let webViewHeightChanged = Notification.Name("WebViewHeightChanged")
}

// MARK: - WebView 消息处理器

class WebViewMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "heightChanged",
           let height = message.body as? CGFloat {
            NotificationCenter.default.post(
                name: .webViewHeightChanged,
                object: nil,
                userInfo: ["height": height]
            )
        }
    }
}
