import Foundation

enum GoogleTranslate {
    enum TranslationError: LocalizedError {
        case invalidResponse
        var errorDescription: String? { "Google 翻譯服務暫時沒有回應" }
    }

    /// Free Google Translate website endpoint. Unofficial and subject to rate limits.
    static func translate(_ text: String) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/t")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "dict-chrome-ex"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "zh-TW"),
            URLQueryItem(name: "q", value: text)
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as! HTTPURLResponse).statusCode == 200,
           let entries = try JSONSerialization.jsonObject(with: data) as? [[String]],
           let translated = entries.first?.first,
           !translated.isEmpty {
            return translated
        }

        var fallback = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        fallback.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "zh-TW"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        let (secondData, secondResponse) = try await URLSession.shared.data(from: fallback.url!)
        guard (secondResponse as! HTTPURLResponse).statusCode == 200,
              let payload = try JSONSerialization.jsonObject(with: secondData) as? [Any],
              let segments = payload.first as? [[Any]]
        else { throw TranslationError.invalidResponse }

        let translated = segments.compactMap { $0.first as? String }.joined()
        guard !translated.isEmpty else { throw TranslationError.invalidResponse }
        return translated
    }
}
