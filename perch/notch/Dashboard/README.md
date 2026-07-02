# Dashboard — the Daily Dashboard subsystem

The user's **Daily Dashboard**: a pegboard of widgets they arrange, and that the act brain
can edit (the `dashboard` method routes here via `[DASHBOARD_WIDGET]` — see
`Input/IntentGate.swift` and the Python `loop/dashboard/dashboard_step.py`).

These files are **self-contained** — they don't pull in `ClaudeAPI` / `BrowserSubagentManager`
(the data seam is protocol-injected via `DashboardDataService`), so the window can be
previewed standalone with `swiftc` (see the preview recipe in the root `AGENTS.md`).

## Where things go

| Folder | Holds | Representative files |
|---|---|---|
| `Model/` | Plain data models (no views) | `DashboardCanvasModel`, `DashboardWidgetModel`, `DashboardWidgetKind`, `DashboardFocusModel`, `DashboardSettingsModels` |
| `Canvas/` | The pegboard canvas + layout solving | `DashboardCanvasView`, `DashboardCanvasItem`, `DashboardLayoutSolver`, `DashboardLayoutStore`, `DashboardPegboardBackground`, `DashboardContentFit` |
| `Widgets/` | Widget rendering + the widget catalog | `DashboardWidgets`, `DashboardWidgetHost`, `DashboardWidgetCard`, `DashboardWidgetComposeView`, `DashboardListWidgetView`, `DashboardGeneratedWidgetView` (sandboxed web view for agent-authored widgets), `DashboardGenericListRow`, `DashboardNewsRow` (publisher-kicker + headline row for web/news widgets), `DashboardWidgetStore` |
| `Settings/` | The settings panel + its controls | `DashboardSettingsView`, `DashboardSettingsPanels`, `DashboardSettingsSidebar`, `DashboardSettingsControls` |
| `Shell/` | Top-level views, window, header, intro | `DashboardView`, `DashboardWindowController`, `DashboardHeaderView`, `DashboardGreetingIntro`, `DashboardFocusNotesLauncher` |
| `State/` | Persistence + services | `DashboardLocalStore`, `DashboardDataService`, `DashboardRankingService`, `DashboardAgentApplier` |
| `Theme/` | Dashboard-local styling | `DashboardTheme`, `DashboardGeneratedWidgetChrome` (design-token + CSP shell for generated widgets) |

> The Xcode project uses **synchronized filesystem groups**, so adding a file here (or a new
> subfolder) needs no `.xcodeproj` edit — Xcode picks it up from disk. New dashboard code
> goes in the matching folder above; new widget kinds start in `Model/DashboardWidgetKind`
> + `Widgets/`.

All UI follows `DESIGN.md`; dashboard-local tokens live in `Theme/DashboardTheme.swift`
(intentionally separate from the app-wide `DS` tokens in `UI/DesignSystem/`).
