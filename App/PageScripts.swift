import Foundation

/// JavaScript injected into the game page before any of the game's own code runs.
enum PageScripts {
    /// Message handler names the page posts to (see `GameViewController`).
    static let savesHandler = "saves"
    static let downloadHandler = "download"

    /// - Parameter restore: a JSON object literal of saved localStorage, or `null`.
    static func bootstrap(restore: String) -> String {
        """
        (function () {
          "use strict";
          var ls;
          try { ls = window.localStorage; } catch (e) { return; }
          var native = window.webkit && window.webkit.messageHandlers;

          // 1. Put the app's saved copy back if iOS cleared the page's storage.
          var restore = \(restore);
          try {
            if (restore && ls.length === 0) {
              Object.keys(restore).forEach(function (k) { ls.setItem(k, restore[k]); });
            }
          } catch (e) {}

          // 2. Send every change to the app (batched), so the app always holds a copy of the saves.
          var timer = null;
          function snapshot() {
            var all = {};
            for (var i = 0; i < ls.length; i++) {
              var key = ls.key(i);
              all[key] = ls.getItem(key);
            }
            return JSON.stringify(all);
          }
          function flush() {
            if (timer) { clearTimeout(timer); timer = null; }
            try { native.\(savesHandler).postMessage(snapshot()); } catch (e) {}
          }
          function changed(store) {
            if (store === ls && !timer) { timer = setTimeout(flush, 1000); }
          }
          var proto = Storage.prototype;
          var setItem = proto.setItem, removeItem = proto.removeItem, clear = proto.clear;
          proto.setItem = function () { var r = setItem.apply(this, arguments); changed(this); return r; };
          proto.removeItem = function () { var r = removeItem.apply(this, arguments); changed(this); return r; };
          proto.clear = function () { var r = clear.apply(this, arguments); changed(this); return r; };
          window.__pokerogueFlushSaves = flush;
          document.addEventListener("visibilitychange", function () {
            if (document.visibilityState === "hidden") { flush(); }
          });
          window.addEventListener("pagehide", flush);

          // 3. "Export Data" / "Export Session" make a file link and click it. A web view cannot download, so hand
          //    the file to the app, which saves it and opens the share sheet.
          //    Remember only non-media blobs (the game loads images and sounds through blob URLs too), and forget
          //    each one when its URL is revoked, so nothing piles up in memory.
          var blobs = {};
          var createObjectURL = URL.createObjectURL, revokeObjectURL = URL.revokeObjectURL;
          URL.createObjectURL = function (obj) {
            var url = createObjectURL.apply(URL, arguments);
            if (obj instanceof Blob && !/^(image|audio|video|font)\\//.test(obj.type || "")) { blobs[url] = obj; }
            return url;
          };
          URL.revokeObjectURL = function (url) {
            delete blobs[url];
            return revokeObjectURL.apply(URL, arguments);
          };
          function sendFile(name, blob) {
            var reader = new FileReader();
            reader.onload = function () {
              var text = String(reader.result);
              try {
                native.\(downloadHandler).postMessage({ name: name, base64: text.slice(text.indexOf(",") + 1) });
              } catch (e) {}
            };
            reader.readAsDataURL(blob);
          }
          function tryDownload(a) {
            if (!a || !a.hasAttribute || !a.hasAttribute("download")) { return false; }
            var href = a.href || "";
            var name = a.getAttribute("download") || "pokerogue-export";
            if (blobs[href]) { sendFile(name, blobs[href]); return true; }
            if (href.indexOf("data:") === 0 || href.indexOf("blob:") === 0) {
              fetch(href).then(function (r) { return r.blob(); }).then(function (b) { sendFile(name, b); });
              return true;
            }
            return false;
          }
          var anchorClick = HTMLAnchorElement.prototype.click;
          HTMLAnchorElement.prototype.click = function () {
            if (tryDownload(this)) { return; }
            return anchorClick.apply(this, arguments);
          };
          document.addEventListener("click", function (ev) {
            var a = ev.target && ev.target.closest ? ev.target.closest("a[download]") : null;
            if (a && tryDownload(a)) { ev.preventDefault(); }
          }, true);

          // 4. "Import Data": let the file picker offer every file. iOS greys out ".prsv" files it has no type for.
          var inputClick = HTMLInputElement.prototype.click;
          HTMLInputElement.prototype.click = function () {
            if (this.type === "file") { this.removeAttribute("accept"); }
            return inputClick.apply(this, arguments);
          };

          // 5. No text selection, magnifier or link previews on long presses.
          var style = document.createElement("style");
          style.textContent = "html,body,canvas{-webkit-user-select:none;user-select:none;" +
            "-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent;}";
          (document.head || document.documentElement).appendChild(style);
        })();
        """
    }
}
