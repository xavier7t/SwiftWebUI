import Foundation

/// The page around the rendered markup: base styles, and the small runtime that handles `@State` and buttons.
public enum PageTemplate {
    /// Blocks everything except inline styles and scripts, and images. Pages can't make requests of their own.
    public static let contentSecurityPolicy =
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data: https: http:; font-src data:"

    /// A full page for `output`, working without any host: `@State` and buttons run from the inline script.
    /// With `livePath`, the page also polls that same-origin URL (JSON `{version, html, states}`) and updates itself
    /// in place when the version changes. Used when a browser views the preview from the local server.
    public static func document(_ output: RenderOutput, title: String = "SwiftWebUI",
                                livePath: String? = nil, liveVersion: Int = 0) -> String {
        var boot = "swui.update(null, \(scriptSafe(output.statesJSON)));"
        if let livePath {
            boot += "\nswui.live(\(livePath.debugDescription), \(liveVersion));"
        }
        return page(title: title, rootHTML: output.html, boot: boot, connect: livePath != nil)
    }

    /// An empty page for a preview host to fill with `swui.update(html, states)`.
    public static let shell: String = page(title: "Preview", rootHTML: "", boot: "", connect: false)

    private static func page(title: String, rootHTML: String, boot: String, connect: Bool) -> String {
        let csp = connect ? contentSecurityPolicy + "; connect-src 'self'" : contentSecurityPolicy
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <title>\(HTMLElement.escapeText(title))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <div id="root">\(rootHTML)</div>
        <script>
        \(runtime)
        \(boot)
        </script>
        </body>
        </html>
        """
    }

    /// JSON placed inside a `<script>` must not be able to close it.
    static func scriptSafe(_ json: String) -> String {
        json.replacingOccurrences(of: "</", with: "<\\/").replacingOccurrences(of: "<!--", with: "<\\!--")
    }

    static var css: String {
        var light = "", dark = ""
        for c in Palette.systemColors {
            light += "--c-\(c.name):\(c.light);"
            dark += "--c-\(c.name):\(c.dark);"
        }
        return """
        :root{color-scheme:light dark;\(light)--fg:#000;--fg-secondary:rgba(60,60,67,.6);--fg-tertiary:rgba(60,60,67,.3);--bg:#fff;--sep:rgba(60,60,67,.29)}
        @media (prefers-color-scheme:dark){:root{\(dark)--fg:#fff;--fg-secondary:rgba(235,235,245,.6);--fg-tertiary:rgba(235,235,245,.3);--bg:#000;--sep:rgba(84,84,88,.6)}}
        *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
        html,body{min-height:100%}
        body{font:17px/1.3 -apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',sans-serif;background:var(--bg);color:var(--fg);-webkit-font-smoothing:antialiased}
        #root{min-height:100vh;display:flex;align-items:center;justify-content:center}
        .text{white-space:pre-line}
        .image{display:block;max-width:100%}
        .sym{display:inline-block;line-height:1}
        .button{font:inherit;color:var(--c-blue);background:none;border:0;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:8px}
        .button:active{opacity:.5}
        .link{color:var(--c-blue);text-decoration:none;display:inline-flex;align-items:center;gap:8px}
        .link:hover{text-decoration:underline}
        .list{display:flex;flex-direction:column;overflow:auto}
        .list>.row{display:flex;align-items:center;justify-content:flex-start;padding:10px 16px;border-bottom:1px solid var(--sep)}
        .list>.row:last-child{border-bottom:0}
        """
    }

    static let runtime = #"""
    var swui = (function () {
      var S = {}, INIT = {};
      function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
      function show(v) { return v === undefined || v === null ? '' : String(v); }
      function val(v) { return v && typeof v === 'object' && 's' in v ? S[v.s] : v; }
      function refresh() {
        document.querySelectorAll('[data-t]').forEach(function (el) {
          var text = JSON.parse(el.getAttribute('data-t')).map(function (p) { return p[0] === 'l' ? p[1] : show(S[p[1]]); }).join('');
          if (el.textContent !== text) el.textContent = text;
        });
      }
      function run(actions) {
        actions.forEach(function (a) {
          if (a[0] === 'add') S[a[1]] = (Number(S[a[1]]) || 0) + a[2];
          else if (a[0] === 'set') S[a[1]] = val(a[2]);
          else if (a[0] === 'toggle') S[a[1]] = !S[a[1]];
        });
        refresh();
      }
      function attrs(from, to) {
        for (var i = from.attributes.length - 1; i >= 0; i--) {
          var n = from.attributes[i].name;
          if (!to.hasAttribute(n)) from.removeAttribute(n);
        }
        for (var j = 0; j < to.attributes.length; j++) {
          var a = to.attributes[j];
          if (from.getAttribute(a.name) !== a.value) from.setAttribute(a.name, a.value);
        }
      }
      function morph(from, to) {
        var a = from.childNodes, b = to.childNodes;
        for (var i = 0; i < b.length; i++) {
          var x = a[i], y = b[i];
          if (!x) { from.appendChild(y.cloneNode(true)); continue; }
          if (x.nodeType !== y.nodeType || x.nodeName !== y.nodeName) { from.replaceChild(y.cloneNode(true), x); continue; }
          if (x.nodeType === 3) { if (x.nodeValue !== y.nodeValue) x.nodeValue = y.nodeValue; continue; }
          attrs(x, y);
          morph(x, y);
        }
        while (from.childNodes.length > b.length) from.removeChild(from.lastChild);
      }
      document.addEventListener('click', function (e) {
        var el = e.target.closest ? e.target.closest('[data-a]') : null;
        if (el) run(JSON.parse(el.getAttribute('data-a')));
      });
      return {
        // Replaces the page content in place. A state keeps its current value unless its initial value changed.
        update: function (html, states) {
          var next = {};
          Object.keys(states || {}).forEach(function (id) {
            next[id] = (id in S && same(INIT[id], states[id])) ? S[id] : states[id];
          });
          S = next; INIT = JSON.parse(JSON.stringify(states || {}));
          if (html !== null) {
            var root = document.getElementById('root');
            var doc = new DOMParser().parseFromString('<body>' + html + '</body>', 'text/html');
            morph(root, doc.body);
          }
          refresh();
        },
        // Polls `path` and applies new renders from the local preview server.
        live: function (path, version) {
          var v = version;
          setInterval(function () {
            fetch(path + '?since=' + v, { cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (d) {
              if (d.version !== v) { v = d.version; swui.update(d.html, d.states); }
            }).catch(function () {});
          }, 300);
        },
        state: function () { return JSON.parse(JSON.stringify(S)); }
      };
    })();
    """#
}
