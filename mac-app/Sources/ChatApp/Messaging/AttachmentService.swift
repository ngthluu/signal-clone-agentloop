import Foundation

protocol AttachmentService: Sendable {
    func upload(token: String, encryptedBlob: Data) async -> String?
    func download(token: String, attachmentId: String) async -> Data?
}

struct HTTPAttachmentService: AttachmentService {
    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "http://127.0.0.1:3000")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func upload(token: String, encryptedBlob: Data) async -> String? {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("attachments"))
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = encryptedBlob

            let (data, response) = try await session.data(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200 || httpResponse.statusCode == 201
            else {
                return nil
            }

            return try decoder.decode(UploadAttachmentResponse.self, from: data).attachmentId
        } catch {
            return nil
        }
    }

    func download(token: String, attachmentId: String) async -> Data? {
        do {
            var request = URLRequest(
                url: baseURL
                    .appendingPathComponent("attachments")
                    .appendingPathComponent(attachmentId)
            )
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
