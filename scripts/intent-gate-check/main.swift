//
//  intent-gate-check/main.swift
//  Standalone, no-Xcode verification of the Intent Gate.
//
//  Compiled by scripts/check-intent-gate.sh together with the real product
//  source (leanring-buddy/IntentGate.swift), so it exercises the actual
//  shipping classification logic — not a copy. The canonical tests live in
//  leanring-buddyTests/IntentGateTests.swift (run via Xcode ⌘U); this is the
//  CLI mirror for a machine with only Command Line Tools.
//

import Foundation

var failureCount = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "  ok  - \(label)" : "  FAIL- \(label)")
    if !condition { failureCount += 1 }
}

// ── Answer lane: anything without a [BACKGROUND_TASK:…] tag stays an answer ──

check(IntentGate.classify(claudeReply: "that's the search bar up top") == .answer,
      "plain reply routes to the answer lane")

check(IntentGate.classify(claudeReply: "tap right here [POINT:120,340:search bar]") == .answer,
      "reply with a [POINT:…] tag routes to the answer lane")

check(IntentGate.classify(claudeReply: "here you go [POINT:none]") == .answer,
      "reply with [POINT:none] routes to the answer lane")

check(IntentGate.classify(claudeReply: "on it [BACKGROUND_TASK:]") == .answer,
      "empty [BACKGROUND_TASK:] is not a valid act — stays an answer")

check(IntentGate.classify(claudeReply: "on it [BACKGROUND_TASK:   ]") == .answer,
      "whitespace-only [BACKGROUND_TASK:] is not a valid act — stays an answer")

// ── Act lane: a trailing [BACKGROUND_TASK:<task>] hands off to the brain ──

let bookingReply = "on it, booking that now [BACKGROUND_TASK:book a table for two at 7pm]"
switch IntentGate.classify(claudeReply: bookingReply) {
case .act(let task, let spokenConfirmation):
    check(task == "book a table for two at 7pm",
          "act lane extracts the task description")
    check(spokenConfirmation == "on it, booking that now",
          "act lane extracts the spoken confirmation (tag stripped, trimmed)")
default:
    check(false, "booking reply must route to the act lane")
}

// Trailing whitespace/newline after the tag must still match (anchored \s*$).
switch IntentGate.classify(claudeReply: "doing it [BACKGROUND_TASK:sign up for the newsletter]\n  ") {
case .act(let task, let spokenConfirmation):
    check(task == "sign up for the newsletter", "act lane matches with trailing whitespace after tag")
    check(spokenConfirmation == "doing it", "spoken confirmation trimmed with trailing whitespace after tag")
default:
    check(false, "reply with trailing whitespace after the tag must route to the act lane")
}

// ── Dashboard-widget lane: a trailing [DASHBOARD:<spec>] adds in-app ──

switch IntentGate.classify(claudeReply: "on it, adding that! [DASHBOARD:the user's top GitHub repositories]") {
case .dashboardWidget(let spec, let spokenConfirmation):
    check(spec == "the user's top GitHub repositories",
          "dashboard-widget lane extracts the widget spec")
    check(spokenConfirmation == "on it, adding that!",
          "dashboard-widget lane extracts the spoken confirmation (tag stripped, trimmed)")
default:
    check(false, "a [DASHBOARD:…] reply must route to the dashboard-widget lane")
}

check(IntentGate.classify(claudeReply: "hmm [DASHBOARD:]") == .answer,
      "empty [DASHBOARD:] is not a valid widget request — stays an answer")

// A dashboard widget must NOT be mistaken for a generic browser act.
if case .act = IntentGate.classify(claudeReply: "adding it [DASHBOARD:my unread email]") {
    check(false, "a dashboard widget must not route to the browser-subagent act lane")
} else {
    check(true, "a dashboard widget does not route to the act lane")
}

// ── Clarify lane: a trailing [CLARIFY:<question>] asks before acting ──

let clarifyReply = "want me to type it, or show you where? [CLARIFY:should i type it in, or just point at the cell?]"
switch IntentGate.classify(claudeReply: clarifyReply) {
case .clarify(let question):
    check(question == "should i type it in, or just point at the cell?",
          "clarify lane extracts the question")
default:
    check(false, "clarify reply must route to the clarify lane")
}

// Trailing whitespace after the tag must still match (anchored \s*$).
switch IntentGate.classify(claudeReply: "quick q [CLARIFY:which file did you mean?]\n  ") {
case .clarify(let question):
    check(question == "which file did you mean?", "clarify lane matches with trailing whitespace after tag")
default:
    check(false, "clarify reply with trailing whitespace must route to the clarify lane")
}

check(IntentGate.classify(claudeReply: "hmm [CLARIFY:]") == .answer,
      "empty [CLARIFY:] is not a valid clarify — stays an answer")

check(IntentGate.classify(claudeReply: "hmm [CLARIFY:   ]") == .answer,
      "whitespace-only [CLARIFY:] is not a valid clarify — stays an answer")

if failureCount == 0 {
    print("\nALL CHECKS PASSED")
} else {
    print("\n\(failureCount) CHECK(S) FAILED")
    exit(1)
}
