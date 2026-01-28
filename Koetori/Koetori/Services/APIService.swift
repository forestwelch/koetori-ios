import Foundation

actor APIService {
    static let shared = APIService()
    
    private let baseURL = "https://www.koetori.com/api/transcribe"
    private let username = "forest"
    
    private init() {}
    
    func uploadAudio(fileURL: URL) async throws -> APIResponse {
        // Create multipart/form-data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Read audio file data
        let audioData = try Data(contentsOf: fileURL)
        print("🔵 Uploading audio file: \(fileURL.lastPathComponent), size: \(audioData.count) bytes")
        
        // Build multipart body
        var body = Data()
        
        // Add username field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"username\"\r\n\r\n".data(using: .utf8)!)
        body.append(username.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add audio file (WAV from BLE or M4A from built-in mic)
        let ext = (fileURL.pathExtension as NSString).lowercased
        let (filename, contentType) = ext == "wav"
            ? ("recording.wav", "audio/wav")
            : ("recording.m4a", "audio/mp4")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Perform request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // Debug: Print status code and response
        print("🔵 API Response Status: \(httpResponse.statusCode)")
        print("🔵 Response Headers: \(httpResponse.allHeaderFields)")
        print("🔵 Response Data Size: \(data.count) bytes")
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔵 Response Body: \(responseString)")
        } else {
            print("🔵 Response Body: (not UTF-8 string)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unable to decode error body"
            throw APIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }
        
        // Check if data is empty
        guard !data.isEmpty else {
            throw APIError.emptyResponse
        }
        
        // Decode response (use static decode to avoid MainActor-isolated conformance in actor)
        do {
            return try APIResponse.decode(from: data)
        } catch {
            // Print the actual decoding error details
            print("🔴 Decoding Error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    print("🔴 Data corrupted: \(context)")
                case .keyNotFound(let key, let context):
                    print("🔴 Key '\(key.stringValue)' not found: \(context)")
                case .typeMismatch(let type, let context):
                    print("🔴 Type mismatch for \(type): \(context)")
                case .valueNotFound(let type, let context):
                    print("🔴 Value not found for \(type): \(context)")
                @unknown default:
                    print("🔴 Unknown decoding error")
                }
            }
            throw APIError.decodingError(error)
        }
    }
    
    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(statusCode: Int, body: String)
        case decodingError(Error)
        case networkError(Error)
        case emptyResponse
        
        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from server."
            case .httpError(let statusCode, let body):
                return "Server error \(statusCode): \(body)"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .emptyResponse:
                return "Server returned empty response"
            }
        }
    }
}
