//
//  DashboardGeneratedWidgetView.swift
//  leanring-buddy
//
//  Renders an agent-authored interactive widget (`source == .generated`) — a
//  self-contained HTML/CSS/JS document — inside a sandboxed `WKWebView` that sits on the
//  dashboard card. The document is wrapped by `DashboardGeneratedWidgetChrome` in a fixed
//  shell (design tokens + a strict Content-Security-Policy) so it stays on-brand and can
//  never reach the network, load external resources, or talk back to the app. A timer /
//  calculator / checklist runs purely client-side in the page's own JS.
//
//  Two layers of sandboxing back each other up: the CSP in the document shell, and the
//  `WKWebView` configuration + navigation delegate below (ephemeral data store, no
//  message handlers, every off-document navigation cancelled). The Python generator also
//  sanitizes the HTML before it ever reaches Swift.
//

import AppKit
import SwiftUI
import WebKit

struct DashboardGeneratedWidgetView: View {
    let widget: DashboardWidget
    @ObservedObject var widgetStore: DashboardWidgetStore

    /// Resolve the live widget so an in-place regenerate (replacing the store record)
    /// re-renders without rebuilding the host.
    private var liveWidget: DashboardWidget {
        widgetStore.widget(for: widget.id) ?? widget
    }

    var body: some View {
        // Zero card padding: the generated document controls its own internal padding via
        // the chrome CSS, and the web view fills the card edge-to-edge (the card still
        // supplies the rounded-rect background, clip, and shadow).
        DashboardWidgetCard(horizontalPadding: 0, verticalPadding: 0) {
            if let document = liveWidget.generatedDocument,
               !document.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                GeneratedWidgetWebView(
                    documentHTML: DashboardGeneratedWidgetChrome.document(forBody: document.html)
                )
            } else {
                // No document yet (the applier stores it before placing, so this is only a
                // brief flash on a slow create) — a quiet placeholder, never a blank card.
                Text("Building…")
                    .font(DashboardTheme.Fonts.sans(size: 13))
                    .foregroundColor(DashboardTheme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(DashboardTheme.Metrics.cardCornerRadius)
            }
        }
    }
}

// MARK: - The sandboxed web view

/// A `WKWebView` wrapper that loads one in-memory HTML document and locks the widget into
/// its sandbox. It reloads only when the document string actually changes, so a SwiftUI
/// re-layout (drag, resize, hover) never resets a running timer.
private struct GeneratedWidgetWebView: NSViewRepresentable {
    let documentHTML: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Ephemeral store: no cookies/localStorage survive the widget, and nothing is
        // written to disk by generated JS.
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // The card paints the card background; the document body also paints it (matching
        // token), so the web view itself can be opaque without a flash.
        webView.allowsBackForwardNavigationGestures = false
        webView.loadHTMLString(documentHTML, baseURL: nil)
        context.coordinator.loadedHTML = documentHTML
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != documentHTML else { return }
        context.coordinator.loadedHTML = documentHTML
        webView.loadHTMLString(documentHTML, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// The document currently loaded, so `updateNSView` only reloads on a real change.
        var loadedHTML: String?

        /// Allow only the initial in-memory document load (`about:blank`); cancel every
        /// other navigation — a link click, a script redirect, any external URL — so the
        /// widget can never leave its sandbox or pull in remote content.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            if scheme == nil || scheme == "about" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
