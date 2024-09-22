import SwiftUI

// MARK: - Models

// Define the message sender types
enum MessageSender {
    case user
    case assistant
}

// Define the message struct
struct ChatMessage: Identifiable {
    let id = UUID()
    let sender: MessageSender
    let content: String
}

// Assistant model
struct Assistant: Codable {
    let id: String
    let object: String
    let created_at: Int
    let name: String?
    let description: String?
    let model: String
    let instructions: String?
    let tools: [Tool]?
    let metadata: [String: String]?
    let top_p: Double?
    let temperature: Double?
    let response_format: String?
}

struct Tool: Codable {
    let type: String
}

struct Thread: Codable {
    let id: String
    let object: String
    let created_at: Int
    let metadata: [String: String]?
    let tool_resources: [String: AnyCodable]?
}

struct Message: Codable {
    let id: String
    let object: String
    let created_at: Int
    let assistant_id: String?
    let thread_id: String
    let run_id: String?
    let role: String
    let content: [ContentItem]
    let attachments: [Attachment]?
    let metadata: [String: String]?
}

struct ContentItem: Codable {
    let type: String
    let text: MessageText?

    // Custom initializer to handle decoding 'text' as either a String or an object
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        if let textValue = try? container.decode(String.self, forKey: .text) {
            text = MessageText(value: textValue, annotations: nil)
        } else if let textObject = try? container.decode(MessageText.self, forKey: .text) {
            text = textObject
        } else {
            text = nil
        }
    }
}

struct MessageText: Codable {
    let value: String
    let annotations: [String]?
}

struct Attachment: Codable {
    let file_id: String
    let tool: Tool
}

struct Run: Codable {
    let id: String
    let object: String
    let created_at: Int
    let assistant_id: String
    let thread_id: String
    let status: String
    let model: String?
    // Add other properties as needed
}

struct MessageList: Codable {
    let object: String
    let data: [Message]
    let first_id: String?
    let last_id: String?
    let has_more: Bool
}

// Error response model
struct ErrorResponse: Codable {
    let error: APIError
}

struct APIError: Codable {
    let message: String
    let type: String
    let param: String?
    let code: String?
}

// MARK: - AnyCodable for dynamic types

struct AnyCodable: Codable {
    let value: Any

    init<T>(_ value: T?) {
        self.value = value ?? ()
    }

    init(from decoder: Decoder) throws {
        self.value = ()
    }

    func encode(to encoder: Encoder) throws {
    }
}

// MARK: - ViewModel

final class ViewModel: ObservableObject {
    private let apiKey = "" // Replace with API key
    private let assistantID = "" // Replace with Assistant ID
    private var threadID = ""

    // Function to create a thread
    func createThread(completion: @escaping (String?) -> Void) {
        let url = URL(string: "https://api.openai.com/v1/threads")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)

        let threadSettings = [String: Any]()

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: threadSettings)
        } catch {
            print("Failed to encode thread settings: \(error)")
            completion(nil)
            return
        }

        performRequest(request) { (thread: Thread?) in
            if let thread = thread {
                self.threadID = thread.id
                completion(thread.id)
            } else {
                print("Failed to create thread: No thread data received.")
                completion(nil)
            }
        }
    }

    // Function to send a message
    func sendMessage(content: String, completion: @escaping (Bool) -> Void) {
        guard !assistantID.isEmpty, !threadID.isEmpty else {
            print("Assistant ID or Thread ID is missing.")
            completion(false)
            return
        }

        let url = URL(string: "https://api.openai.com/v1/threads/\(threadID)/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)

        let messagePayload: [String: Any] = [
            "role": "user",
            "content": [
                [
                    "type": "text",
                    "text": content
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: messagePayload)
        } catch {
            print("Failed to encode message payload: \(error)")
            completion(false)
            return
        }

        performRequest(request) { (message: Message?) in
            if let _ = message {
                completion(true)
            } else {
                print("Failed to send message: No message data received.")
                completion(false)
            }
        }
    }

    // Function to create a run
    func createRun(completion: @escaping (Bool) -> Void) {
        guard !assistantID.isEmpty, !threadID.isEmpty else {
            print("Assistant ID or Thread ID is missing.")
            completion(false)
            return
        }

        let url = URL(string: "https://api.openai.com/v1/threads/\(threadID)/runs")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)

        let runPayload: [String: Any] = [
            "assistant_id": assistantID,
            "stream": false
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: runPayload)
        } catch {
            print("Failed to encode run payload: \(error)")
            completion(false)
            return
        }

        performRequest(request) { (run: Run?) in
            if let _ = run {
                completion(true)
            } else {
                print("Failed to create run: No run data received.")
                completion(false)
            }
        }
    }

    // Function to fetch messages
    func fetchMessages(completion: @escaping (String?) -> Void) {
        guard !threadID.isEmpty else {
            print("Thread ID is missing.")
            completion(nil)
            return
        }

        let url = URL(string: "https://api.openai.com/v1/threads/\(threadID)/messages?order=asc")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(to: &request)

        performRequest(request) { (messageList: MessageList?) in
            if let messages = messageList?.data {
                // Find the latest assistant message
                if let assistantMessage = messages.last(where: { $0.role == "assistant" }) {
                    let content = assistantMessage.content.compactMap { $0.text?.value }.joined(separator: "\n")
                    completion(content)
                } else {
                    print("No assistant response found in messages.")
                    completion("No response from assistant.")
                }
            } else {
                print("Failed to fetch messages: No message list data received.")
                completion(nil)
            }
        }
    }

    // Helper function to add headers to the request
    private func addHeaders(to request: inout URLRequest) {
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
    }

    // Generic function to perform API requests
    private func performRequest<T: Decodable>(_ request: URLRequest, completion: @escaping (T?) -> Void) {
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error making request: \(error)")
                completion(nil)
                return
            }

            guard let data = data else {
                print("No data received.")
                completion(nil)
                return
            }

            do {
                // Check for API error
                if let apiError = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    print("API Error: \(apiError.error.message)")
                    print("Error Type: \(apiError.error.type)")
                    completion(nil)
                    return
                }

                let decodedData = try JSONDecoder().decode(T.self, from: data)
                completion(decodedData)
            } catch {
                print("Failed to decode response: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Response data: \(jsonString)")
                }
                completion(nil)
            }
        }
        task.resume()
    }
}

// MARK: - SwiftUI View

struct ContentView: View {
    @StateObject var viewModel = ViewModel()
    @State private var text = ""
    @State private var messages = [ChatMessage]()
    @State private var assistantReady = false
    @State private var isAssistantTyping = false
    @State private var disclaimerAccepted: Bool = false


    var body: some View {
        VStack {
            if assistantReady {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(messages) { message in
                                if message.sender == .user {
                                    HStack {
                                        Spacer()
                                        Text(message.content)
                                            .padding(10)
                                            .background(Color(red: 59/255, green: 209/255, blue: 199/255).opacity(0.4))
                                            .cornerRadius(10)
                                    }
                                    .padding(.horizontal)
                                } else {
                                    HStack {
                                        Image("TSLogo")
                                            .resizable()
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())

                                        if let attributedString = detectLinks(in: message.content) {
                                            Text(attributedString)
                                                .padding(10)
                                                .background(Color.gray.opacity(0.2))
                                                .cornerRadius(10)
                                        } else {
                                            Text(message.content)
                                                .padding(10)
                                                .background(Color.gray.opacity(0.2))
                                                .cornerRadius(10)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            if isAssistantTyping {
                                HStack {
                                    Image("TSLogo")
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())

                                    Text("...")
                                        .padding(10)
                                        .background(Color.gray.opacity(0.2))
                                        .cornerRadius(10)

                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                            if let lastMessage = messages.last {
                                Color.clear
                                    .frame(height: 1)
                                    .id(lastMessage.id)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: messages.count) { newValue, oldValue in
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Spacer()

                HStack {
                    TextField("Type here...", text: $text)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button(action: {
                        send()
                    }) {
                        Text("Send")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(red: 59/255, green: 209/255, blue: 199/255))
                            .cornerRadius(8)
                    }
                }
                .padding()
            } else {
                Text("Setting up thread...")
                    .padding()
                    .onAppear {
                        setupThread()
                    }
            }
        }
        // Present the disclaimer as a full-screen modal when the user hasn't accepted it yet
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { !disclaimerAccepted },
            set: { _ in }
        )) {
            DisclaimerView(disclaimerAccepted: $disclaimerAccepted)
                .interactiveDismissDisabled(true) // Prevent dismissal without acceptance
        }
    }

    func setupThread() {
        viewModel.createThread { threadID in
            if let _ = threadID {
                DispatchQueue.main.async {
                    assistantReady = true
                    messages.append(ChatMessage(sender: .assistant, content: "Hi! How can I assist you today? I can provide information about Tourette’s Syndrome, explain CBIT, give advice on competing behaviors for tics, and help with school, work, friends, or anything else TS-related."))
                }
            } else {
                DispatchQueue.main.async {
                    messages.append(ChatMessage(sender: .assistant, content: "Failed to create thread."))
                }
            }
        }
    }

    func send() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        let userInput = text
        text = "" // Clear the text field after sending

        DispatchQueue.main.async {
            messages.append(ChatMessage(sender: .user, content: userInput))
        }

        DispatchQueue.main.async {
            isAssistantTyping = true // Start typing indicator
        }

        viewModel.sendMessage(content: userInput) { success in
            if success {
                viewModel.createRun { runSuccess in
                    if runSuccess {
                        // Wait before fetching messages
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            viewModel.fetchMessages { response in
                                DispatchQueue.main.async {
                                    isAssistantTyping = false // Stop typing indicator

                                    if let response = response, !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        messages.append(ChatMessage(sender: .assistant, content: response))
                                    } else {
                                        messages.append(ChatMessage(sender: .assistant, content: "I'm sorry, I didn't catch that. Could you please rephrase?"))
                                    }
                                }
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            isAssistantTyping = false // Stop typing indicator
                            messages.append(ChatMessage(sender: .assistant, content: "Failed to process the message."))
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    isAssistantTyping = false // Stop typing indicator
                    messages.append(ChatMessage(sender: .assistant, content: "Failed to send the message."))
                }
            }
        }
    }

    // Detects URLs in a string and creates a clickable link if found
    func detectLinks(in text: String) -> AttributedString? {
        var attributedString = AttributedString(text)
        let pattern = "(https?://[\\w-]+(\\.[\\w-]+)+(/[\\w\\-./?%&=]*)?)"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.matches(in: text, options: [], range: nsrange)

            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }

                let start = AttributedString.Index(range.lowerBound, within: attributedString)
                let end = AttributedString.Index(range.upperBound, within: attributedString)
                if let start = start, let end = end {
                    let attributedRange = start..<end
                    let urlString = String(text[range])
                    if let url = URL(string: urlString) {
                        attributedString[attributedRange].link = url
                    }
                }
            }
            return attributedString
        } catch {
            print("Error detecting links: \(error)")
            return nil
        }
    }
}

// Create the DisclaimerView
struct DisclaimerView: View {
    @Binding var disclaimerAccepted: Bool

    var body: some View {
        VStack {
            Spacer()
            ScrollView {
                Text("""
                **Disclaimer**

                This application provides information about Tourette’s Syndrome for educational purposes only. It is not intended to be a substitute for professional medical advice, diagnosis, or treatment. Always seek the advice of your physician or other qualified health provider with any questions you may have regarding a medical condition.
                """)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()
            }
            Spacer()
            Button(action: {
                disclaimerAccepted = true
            }) {
                Text("I Understand and Accept")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 59/255, green: 209/255, blue: 199/255))
                    .cornerRadius(10)
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Preview Provider

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
