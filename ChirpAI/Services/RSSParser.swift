import Foundation

struct RSSItem {
    let title: String
    let link: String
    let description: String
    let pubDate: Date?
    let source: String
}

class RSSParser: NSObject, XMLParserDelegate {
    private var items: [RSSItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var sourceName = ""

    func parse(data: Data, sourceName: String) -> [RSSItem] {
        items = []
        currentElement = ""
        currentTitle = ""
        currentLink = ""
        currentDescription = ""
        currentPubDate = ""
        self.sourceName = sourceName

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" || currentElement == "entry" {
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "description", "summary", "content":
            currentDescription += string
        case "pubdate", "published", "updated":
            currentPubDate += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let el = elementName.lowercased()
        guard el == "item" || el == "entry" else { return }

        let trimmedTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDate = currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty, !trimmedLink.isEmpty else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        var pubDate: Date? = nil
        let dateFormats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss"
        ]
        for format in dateFormats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: trimmedDate) {
                pubDate = date
                break
            }
        }

        let cleanDesc = trimmedDesc
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        items.append(RSSItem(
            title: trimmedTitle,
            link: trimmedLink,
            description: String(cleanDesc.prefix(500)),
            pubDate: pubDate ?? Date(),
            source: sourceName
        ))
    }

    static func testRSS(url urlString: String) async throws -> Int {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if !(200...299).contains(httpResponse.statusCode) {
            struct HTTPError: Error, LocalizedError {
                let code: Int
                var errorDescription: String? { "HTTP 错误: \(code)" }
            }
            throw HTTPError(code: httpResponse.statusCode)
        }
        
        let parser = RSSParser()
        let items = parser.parse(data: data, sourceName: "Test")
        if items.isEmpty {
            struct ParseError: Error, LocalizedError {
                var errorDescription: String? { "成功连接，但无法解析出任何文章。请确认这是有效的 RSS/Atom 源。" }
            }
            throw ParseError()
        }
        return items.count
    }
}
