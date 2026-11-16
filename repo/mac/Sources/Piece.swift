import AppKit
import WebKit

/// Hosts the piece and owns the camera relationship with it.
///
/// The HTML exposes `window.OCULUS_HOST` (start/stop/isRunning); everything here
/// drives that, so the camera is only ever held while the eye is actually on screen.
final class Piece: NSObject, WKUIDelegate, WKNavigationDelegate {

    let webView: WKWebView

    private let port: UInt16
    private var wantsCamera = false
    private var loaded = false
    private var retryTimer: Timer?

    /// Frames per second to draw at; 0 runs at whatever the display offers.
    /// A 144 Hz panel will happily repaint an ambient wallpaper 144 times a
    /// second forever, which buys nothing on a piece that turns this slowly.
    private(set) var frameCap: Int

    /// Whether the eye blinks. Off by default here — an occasional twitch is fine
    /// in a window you are looking at, and reads as a distraction on a desktop
    /// you are trying to work on.
    private(set) var blinks: Bool

    /// Filename of the piece currently loaded.
    private(set) var file: String

    /// Extra query items for the piece's temperament block: lexicon, paired
    /// eye, plate of the day and so on. Takes effect at the next load.
    var extras: [URLQueryItem] = []

    init(port: UInt16, file: String, frameCap: Int, blinks: Bool) {
        self.port = port
        self.file = file
        self.frameCap = frameCap
        self.blinks = blinks

        let config = WKWebViewConfiguration()
        // The <video> element carrying the camera feed has to start on its own.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController = WKUserContentController()

        webView = WKWebView(frame: .zero, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.underPageBackgroundColor = .black
        webView.allowsMagnification = false

        super.init()

        webView.uiDelegate = self
        webView.navigationDelegate = self
        installUserScripts()
    }

    // MARK: - Injected scripts

    /// Batches every `requestAnimationFrame` callback and releases them together
    /// at no more than `window.__oculusFPS`. Batching matters: the piece runs
    /// several independent rAF chains (the plate, the build, the detector), and
    /// throttling them separately would leave them beating against each other.
    ///
    /// Returning 0 as the handle is safe here — the piece never cancels a frame.
    private static let frameCapHarness = """
    (function(){
      "use strict";
      var native = window.requestAnimationFrame.bind(window);
      var pending = [], scheduled = false, last = -1e9;
      function flush(t){
        scheduled = false;
        var cap = window.__oculusFPS || 0;
        if(cap > 0 && (t - last) < (1000 / cap - 1)){ schedule(); return; }
        last = t;
        var due = pending; pending = [];
        for(var i = 0; i < due.length; i++){
          try { due[i](t); } catch(e){ setTimeout(function(){ throw e; }, 0); }
        }
      }
      function schedule(){ if(!scheduled){ scheduled = true; native(flush); } }
      window.requestAnimationFrame = function(cb){ pending.push(cb); schedule(); return 0; };
    })();
    """

    private func installUserScripts() {
        let scripts = webView.configuration.userContentController
        scripts.removeAllUserScripts()

        // Point the detector at the copy inside the bundle before the module
        // runs, so face tracking never waits on the CDN. The cap has to be in
        // place before the piece queues its first frame.
        let preamble = """
        window.OCULUS_ASSETS = "/vendor";
        window.__oculusFPS = \(frameCap);
        """
        for source in [preamble, Self.frameCapHarness] {
            scripts.addUserScript(WKUserScript(source: source,
                                               injectionTime: .atDocumentStart,
                                               forMainFrameOnly: true))
        }
    }

    /// Live — no reload needed. Drives the panel's own toggle so the flag and the
    /// button state cannot drift apart.
    func setBlinks(_ on: Bool) {
        guard on != blinks else { return }
        blinks = on
        guard loaded else { return }
        webView.evaluateJavaScript("""
        (function(){
          var b = document.getElementById("t-blink");
          if(b && b.classList.contains("on") !== \(on)) b.click();
        })();
        """, completionHandler: nil)
    }

    /// Live — no reload needed.
    func setFrameCap(_ fps: Int) {
        guard fps != frameCap else { return }
        frameCap = fps
        installUserScripts()
        webView.evaluateJavaScript("window.__oculusFPS = \(fps);", completionHandler: nil)
    }

    // MARK: - Loading

    func load(file: String? = nil) {
        if let file { self.file = file }
        loaded = false

        var url = URLComponents()
        url.scheme = "http"
        url.host = "127.0.0.1"
        url.port = Int(port)
        url.path = "/" + self.file
        url.queryItems = [URLQueryItem(name: "kiosk", value: "1")]
        // Let the host decide when the camera comes up rather than the page.
        if !wantsCamera { url.queryItems?.append(URLQueryItem(name: "face", value: "0")) }
        // Settle blink at load rather than after, so it cannot blink once on the
        // way up and then stop.
        if !blinks { url.queryItems?.append(URLQueryItem(name: "blink", value: "0")) }

        url.queryItems?.append(contentsOf: extras)

        guard let target = url.url else { return }
        webView.load(URLRequest(url: target))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        // The kiosk block arms the camera itself when it was wanted at load time;
        // this covers the case where it was switched on afterwards.
        if wantsCamera { pushCameraState() }
    }

    /// Calls one method on the piece's temperament bridge, such as
    /// `glance(0.4, -0.2, 1100)`. Does nothing until the page has loaded.
    func temperament(_ call: String) {
        guard loaded else { return }
        webView.evaluateJavaScript("if(window.OCULUS_T){ window.OCULUS_T.\(call); }", completionHandler: nil)
    }

    // MARK: - Camera

    /// Whether the eye should be watching. Idempotent; safe to call on every change.
    func setCameraWanted(_ on: Bool) {
        guard on != wantsCamera else { return }
        wantsCamera = on
        pushCameraState()

        retryTimer?.invalidate()
        retryTimer = nil
        if on {
            // Another app may hold the camera when we ask (a call, Photo Booth).
            // Keep asking quietly rather than falling back to a wandering eye forever.
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.retryIfStalled() }
            RunLoop.main.add(t, forMode: .common)
            retryTimer = t
        }
    }

    private func pushCameraState() {
        guard loaded else { return }
        let js = wantsCamera
            ? "window.OCULUS_HOST && window.OCULUS_HOST.start();"
            : "window.OCULUS_HOST && window.OCULUS_HOST.stop();"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func retryIfStalled() {
        guard wantsCamera, loaded else { return }
        webView.evaluateJavaScript("!!(window.OCULUS_HOST && window.OCULUS_HOST.isRunning());") { [weak self] result, _ in
            if (result as? Bool) != true { self?.pushCameraState() }
        }
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Our own loopback origin, camera only. The OS-level grant is still the
        // real gate; this just stops WebKit asking a question with no UI to answer it.
        let ours = origin.host == "127.0.0.1" && origin.protocol == "http"
        decisionHandler(ours && type == .camera ? .grant : .deny)
    }
}
