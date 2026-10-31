import Foundation

struct VideoLink: Equatable, Sendable {
    let id: String
    let isShort: Bool

    var url: URL {
        URL(string: isShort ? "https://m.youtube.com/shorts/\(id)" : "https://m.youtube.com/watch?v=\(id)")!
    }

    static func validID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }

    static func isYouTubeHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be" || host == "www.youtu.be"
    }

    static func parse(_ value: String) -> VideoLink? {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), isYouTubeHost(host) else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        let id: String?
        let isShort = parts.first == "shorts"
        if host == "youtu.be" || host == "www.youtu.be" {
            id = parts.count == 1 ? parts.first : nil
        } else if components.path == "/watch" {
            id = components.queryItems?.first(where: { $0.name == "v" })?.value
        } else if ["shorts", "embed", "live"].contains(parts.first ?? ""), parts.count == 2 {
            id = parts.last
        } else {
            id = nil
        }
        guard let id, validID(id) else { return nil }
        return VideoLink(id: id, isShort: isShort)
    }
}

struct SavedVideo: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var channel: String
    var isShort: Bool
    let savedAt: Date

    var url: URL { VideoLink(id: id, isShort: isShort).url }
    var thumbnailURL: URL { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")! }

    init(link: VideoLink, title: String = "", channel: String = "", savedAt: Date = Date()) {
        self.id = link.id
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = String((cleanedTitle.isEmpty ? "Video YouTube" : cleanedTitle).prefix(300))
        self.channel = String(channel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        self.isShort = link.isShort
        self.savedAt = savedAt
    }
}
