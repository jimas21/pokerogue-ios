import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the bundled game (the `Game` folder inside the app) at `pokerogue://app/...`.
///
/// Everything the game loads (code, images, audio, translations) comes from the app itself, so it plays with no
/// network at all. A fixed origin (`pokerogue://app`) keeps the game's save storage in the same place across
/// launches and updates. Missing files answer 404 like a web server would, which the game already expects for
/// optional files.
final class GameSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "pokerogue"
    static let host = "app"
    static let startURL = URL(string: "\(scheme)://\(host)/index.html")!

    private let root: URL
    private let queue = DispatchQueue(label: "pokerogue.files", qos: .userInitiated, attributes: .concurrent)
    /// Tasks WebKit has cancelled. Only touched on the main thread (WebKit calls start/stop there).
    private var stopped = Set<ObjectIdentifier>()

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// The `Game` folder copied into the app bundle by the build.
    static var bundledGame: URL {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("Game", isDirectory: true)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        stopped.remove(id)
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        var path = url.path            // already percent-decoded; query (?t=...) is not part of it
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL

        // Never serve anything outside the game folder.
        guard file.path.hasPrefix(root.path + "/") else {
            respond(task, id: id, url: url, status: 403, body: Data(), type: "text/plain")
            return
        }

        queue.async { [weak self] in
            let data = try? Data(contentsOf: file, options: .mappedIfSafe)
            DispatchQueue.main.async {
                guard let self else { return }
                if let data {
                    self.respond(task, id: id, url: url, status: 200, body: data, type: Self.mimeType(for: file))
                } else {
                    self.respond(task, id: id, url: url, status: 404, body: Data(), type: "text/plain")
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        stopped.insert(ObjectIdentifier(task))
    }

    private func respond(_ task: WKURLSchemeTask, id: ObjectIdentifier, url: URL, status: Int, body: Data,
                         type: String) {
        // Calling a task after WebKit stopped it throws an Objective-C exception, so check first.
        guard !stopped.contains(id) else {
            stopped.remove(id)
            return
        }
        let headers = [
            "Content-Type": type,
            "Content-Length": String(body.count),
            "Cache-Control": "no-cache",
            "Access-Control-Allow-Origin": "*",
        ]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            ?? URLResponse(url: url, mimeType: type, expectedContentLength: body.count, textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    private static let knownTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "mjs": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "webmanifest": "application/manifest+json",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "svg": "image/svg+xml",
        "ico": "image/x-icon",
        "wav": "audio/wav",
        "mp3": "audio/mpeg",
        "ogg": "audio/ogg",
        "m4a": "audio/mp4",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "otf": "font/otf",
        "wasm": "application/wasm",
        "txt": "text/plain; charset=utf-8",
    ]

    private static func mimeType(for file: URL) -> String {
        let ext = file.pathExtension.lowercased()
        if let known = knownTypes[ext] { return known }
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }
}
