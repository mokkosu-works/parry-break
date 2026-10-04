import Foundation
import WebKit

// アプリに同梱した www/ フォルダを ricochet://localhost/ として配信する。
// file:// ではなく独自のオリジンにすることで、localStorage (ハイスコア・設定) が安定して保存される。
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "ricochet"
    static let startURL = URL(string: "\(scheme)://localhost/index.html")!

    private let root = Bundle.main.resourceURL!.appendingPathComponent("www", isDirectory: true).standardizedFileURL

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let path = url.path.isEmpty || url.path == "/" ? "index.html" : String(url.path.dropFirst())
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), var data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        if file.pathExtension == "html" { data = Self.useBundledFont(data) }

        let headers = [
            "Content-Type": Self.mimeTypes[file.pathExtension.lowercased()] ?? "application/octet-stream",
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static let mimeTypes = [
        "html": "text/html; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json",
        "png": "image/png",
        "svg": "image/svg+xml",
        "ttf": "font/ttf",
        "woff2": "font/woff2",
    ]

    // Google Fonts の読み込みを同梱の Orbitron に差し替えて、オフラインでも同じ見た目にする
    private static func useBundledFont(_ data: Data) -> Data {
        guard var html = String(data: data, encoding: .utf8) else { return data }
        html = html.replacingOccurrences(
            of: #"<link[^>]+fonts\.(googleapis|gstatic)\.com[^>]*>\n?"#, with: "", options: .regularExpression)
        let fontFace = """
        <style>@font-face { font-family: Orbitron; src: url(fonts/Orbitron.ttf) format("truetype"); font-weight: 400 900; }</style>
        <script>document.fonts && document.fonts.load('900 16px Orbitron');</script>

        """
        if let head = html.range(of: "</head>") { html.insert(contentsOf: fontFace, at: head.lowerBound) }
        return Data(html.utf8)
    }
}
