//
//  DashboardGeneratedWidgetChrome.swift
//  leanring-buddy
//
//  The fixed document shell every agent-authored (`source == .generated`) widget is
//  rendered inside. It does two jobs:
//
//   1. DESIGN FIDELITY — it exposes the dashboard's design tokens (the same OKLCH colors
//      and serif/sans families as `DashboardTheme`) as CSS custom properties plus a base
//      reset, so a generated widget matches the board's look even when the generator is
//      sloppy. The widget generator is instructed to use ONLY these tokens; this shell is
//      what makes that promise real.
//
//   2. SANDBOXING — it injects a strict Content-Security-Policy that keeps the widget
//      fully self-contained: inline CSS/JS only, no network, no external resources, no
//      navigation. This is the first of two defenses (the second is the WKWebView config
//      + navigation delegate in `DashboardGeneratedWidgetView`); the Python side also
//      sanitizes before the HTML ever reaches Swift.
//
//  The token values are kept in sync by hand with `DashboardTheme.Colors`. CSS `oklch()`
//  takes the same (L C H) triples the Swift `Color(oklch:chroma:hue:)` initializer uses,
//  so the mapping is a direct transcription.
//

import Foundation

enum DashboardGeneratedWidgetChrome {

    /// Wrap an agent-authored body (its own `<style>`/`<script>`/markup) in the full
    /// document shell — design tokens, base reset, and the sandboxing CSP.
    static func document(forBody bodyHTML: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <style>\(baseCSS)</style>
        </head>
        <body>\(bodyHTML)</body>
        </html>
        """
    }

    /// Inline-only, no-network CSP. `default-src 'none'` blocks every fetch/connect/frame;
    /// inline CSS and inline JS are explicitly allowed (the widget needs client-side JS
    /// for interactivity), and `img-src data:` permits inline data-URI images only. There
    /// is no `connect-src`, so `fetch`/`XMLHttpRequest`/WebSocket are all denied.
    static let contentSecurityPolicy =
        "default-src 'none'; "
        + "style-src 'unsafe-inline'; "
        + "script-src 'unsafe-inline'; "
        + "img-src data:; "
        + "base-uri 'none'; "
        + "form-action 'none'"

    /// The design-token `:root` block + a base reset. Mirrors `DashboardTheme.Colors`
    /// (the light-card palette) and the serif/sans type pairing.
    static let baseCSS = """
    :root {
      --ds-card-bg: oklch(0.995 0.004 80);
      --ds-text-primary: oklch(0.34 0.02 52);
      --ds-text-body: oklch(0.40 0.02 52);
      --ds-text-secondary: oklch(0.55 0.018 55);
      --ds-text-tertiary: oklch(0.68 0.018 55);
      --ds-text-label: oklch(0.62 0.022 58);
      --ds-accent: oklch(0.56 0.05 150);
      --ds-accent-strong: oklch(0.55 0.07 150);
      --ds-divider: oklch(0.93 0.008 80);
      --ds-radius: 16px;
      --ds-pad: 26px;
      --ds-gap: 14px;
      --ds-font-serif: ui-serif, 'New York', Georgia, serif;
      --ds-font-sans: ui-sans-serif, -apple-system, 'SF Pro Text', system-ui, sans-serif;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%; height: 100%;
      background: var(--ds-card-bg);
      color: var(--ds-text-body);
      font-family: var(--ds-font-sans);
      font-size: 14px;
      line-height: 1.4;
      -webkit-font-smoothing: antialiased;
      overflow: hidden;
      user-select: none;
      cursor: default;
    }
    body { padding: var(--ds-pad); }
    h1, h2, h3 {
      font-family: var(--ds-font-serif);
      color: var(--ds-text-primary);
      font-weight: 400;
      line-height: 1.1;
    }
    .ds-label {
      font-family: var(--ds-font-sans);
      font-size: 12px;
      font-weight: 500;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      color: var(--ds-text-label);
    }
    button {
      font-family: var(--ds-font-sans);
      font-size: 13px;
      font-weight: 600;
      color: #fff;
      background: var(--ds-accent-strong);
      border: none;
      border-radius: 999px;
      padding: 7px 16px;
      cursor: pointer;
    }
    button.secondary {
      color: var(--ds-text-secondary);
      background: transparent;
      border: 1px solid var(--ds-divider);
    }
    button:active { transform: translateY(0.5px); }
    """
}
