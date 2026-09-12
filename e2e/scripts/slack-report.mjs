#!/usr/bin/env node
/**
 * The run's result, as a Slack message and as the workflow's job summary.
 *
 * Reads Playwright's JSON report (test-results/results.json) and what the
 * journey itself recorded (test-results/e2e-summary.json): each step passed,
 * failed or skipped; the match, both innings and the result; which accounts
 * were made or reused; the Step 18 checklist; and, for a failure, the step,
 * what it was doing, the account it was using, the error and the evidence.
 *
 *   SLACK_WEBHOOK      incoming webhook — the message is posted when set
 *   SLACK_BOT_TOKEN    optional, with SLACK_CHANNEL: failure screenshots are
 *                      uploaded into the channel too
 *   E2E_TARGET_LABEL   "int", "PR #48 (CI stack)" … shown in the header
 *   RUN_URL            link to the run: report, screenshots and videos
 *
 * Prints the same summary when nothing is configured, so a local run shows it.
 * Exits 0 always: reporting must never be the thing that fails a run.
 */
import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { basename } from "node:path";

const RESULTS = "test-results/results.json";
const SUMMARY = "test-results/e2e-summary.json";
const read = (f) => (existsSync(f) ? JSON.parse(readFileSync(f, "utf8")) : null);
const results = read(RESULTS);
const summary = read(SUMMARY) ?? {};
const env = process.env;
const target = env.E2E_TARGET_LABEL || summary.base_url || "unknown";
const runUrl = env.RUN_URL || "";
const strip = (s = "") => s.replace(/\[[0-9;]*m/g, "");
/// Slack reads &, < and > as markup; Playwright call logs are full of them.
const esc = (t = "") => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
/// Slack's one-asterisk bold into markdown's two — pairs only, so the lone
/// asterisk that means "not out" is left alone.
const toMarkdown = (line) =>
  line.replace(/\*([^*\n]+)\*/g, "**$1**").replace(/<([^|>]+)\|([^>]+)>/g, "[$2]($1)");

const dur = (ms) => (ms >= 60000 ? `${Math.floor(ms / 60000)}m ${Math.round((ms % 60000) / 1000)}s` : `${(ms / 1000).toFixed(1)}s`);

// ---- steps, from Playwright's report ---------------------------------------
const steps = [];
(function walk(suites = []) {
  for (const suite of suites) {
    for (const spec of suite.specs ?? []) {
      for (const t of spec.tests ?? []) {
        const r = t.results?.at(-1);
        const status = !r ? "skipped" : r.status === "passed" ? "passed" : r.status === "skipped" ? "skipped" : "failed";
        steps.push({
          title: spec.title,
          status,
          ms: r?.duration ?? 0,
          account: (t.annotations ?? []).find((a) => a.type === "account")?.description,
          error: r?.errors?.map((e) => strip(e.message)).find(Boolean) ?? "",
          evidence: (r?.attachments ?? []).filter((a) => a.path).map((a) => ({ name: a.name, path: a.path, type: a.contentType })),
        });
      }
    }
    walk(suite.suites);
  }
})(results?.suites);

// Playwright's own errors — a spec that will not compile, a global setup
// that threw — are not steps, and without them the report reads "0/0" and
// says nothing about why.
const topErrors = (results?.errors ?? []).map((e) => strip(e.message ?? String(e))).filter(Boolean);
const passed = steps.filter((s) => s.status === "passed").length;
const failedSteps = steps.filter((s) => s.status === "failed");
const ok =
  !!results && steps.length > 0 && failedSteps.length === 0 && passed === steps.length && topErrors.length === 0;
const total = steps.reduce((n, s) => n + s.ms, 0);
const icon = { passed: "✅", failed: "❌", skipped: "⏩" };

const stepLines = steps.map((s) => `${icon[s.status]} ${s.title}${s.status === "skipped" ? "" : ` — ${dur(s.ms)}`}`);

// ---- the match --------------------------------------------------------------
const inn = summary.innings ?? [];
const matchLines = [];
if (inn.length) {
  matchLines.push(inn.map((i) => `*${i.team}* ${i.score} (${i.overs} ov)`).join("  v  "));
  if (summary.result) matchLines.push(`🏆 *${summary.result}*`);
  if (summary.toss) matchLines.push(`🪙 ${summary.toss}`);
  for (const i of inn) matchLines.push(`• ${i.team}: top score ${i.top}; best bowling ${i.best}; extras ${i.extras}`);
}
// A link is only worth giving when the reader can open it — on the CI target
// the app lived on a runner that is already gone.
if (summary.match?.url && !/localhost|127\.0\.0\.1/.test(summary.match.url)) {
  matchLines.push(`<${summary.match.url}|Open the scorecard>`);
}

const created = summary.accounts?.created?.length ?? 0;
const reused = summary.accounts?.reused?.length ?? 0;
const clubs = Object.values(summary.clubs ?? {})
  .map((c) => `${c.name}: ${c.players} players`)
  .join(" · ");

// ---- the checklist ------------------------------------------------------------
const byArea = {};
for (const c of summary.checks ?? []) (byArea[c.area] ??= []).push(c);
const checklist = Object.entries(byArea).map(
  ([area, list]) => `*${area}* ${list.filter((c) => c.ok).length}/${list.length}  ${list.map((c) => `${c.ok ? "✅" : "❌"} ${c.check}`).join(" · ")}`
);

// ---- the failure, as the plan asks for it -------------------------------------
const failure = failedSteps[0];
const failureText = failure
  ? [
      `*Step:* ${esc(failure.title)}`,
      `*Account:* ${esc(failure.account ?? "—")}`,
      "*What happened:*",
      "```",
      esc(
        failure.error
          .split("\n")
          .filter((l) => l.trim() && !/^\s+at /.test(l))
          .slice(0, 12)
          .join("\n")
          .slice(0, 1400)
      ),
      "```",
      `*Evidence:* ${failure.evidence.length} file(s) — screenshots, video and trace in the run's artifacts.`,
    ].join("\n")
  : "";

// ---- as text: the job summary and the console ----------------------------------
const heading = !results
  ? "Fishers E2E — no results (Playwright did not run)"
  : ok
    ? "Fishers E2E — full match ✅ all steps passed"
    : failure
      ? `Fishers E2E — ❌ failed at ${failure.title.split(" — ")[0]}`
      : topErrors.length
        ? "Fishers E2E — ❌ Playwright could not run the suite"
        : "Fishers E2E — ❌ failed";
const md = [
  `## ${heading}`,
  `Target: **${target}** · ${passed}/${steps.length} steps · ${dur(total)} · accounts: ${created} created, ${reused} reused`,
  "",
  ...stepLines.map((l) => `- ${l}`),
  "",
  ...(topErrors.length ? ["### Playwright errors", "```", ...topErrors.map((e) => e.slice(0, 600)), "```", ""] : []),
  ...(matchLines.length ? ["### Match", ...matchLines.map((l) => `- ${toMarkdown(l)}`), ""] : []),
  ...(failure ? ["### Failure", toMarkdown(failureText), ""] : []),
  ...(checklist.length ? ["### Step 18 checklist", ...checklist.map((l) => `- ${toMarkdown(l)}`)] : []),
].join("\n");
console.log(md);
if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, md + "\n");

// ---- to Slack ------------------------------------------------------------------
const section = (text) => ({ type: "section", text: { type: "mrkdwn", text: text.slice(0, 2900) } });
const blocks = [
  { type: "header", text: { type: "plain_text", text: heading.slice(0, 150), emoji: true } },
  section(
    `*${passed}/${steps.length} steps passed* · ⏱️ ${dur(total)} · 🎯 ${target}\n` +
      `👥 Accounts: ${created} created, ${reused} reused${clubs ? ` · ${clubs}` : ""}`
  ),
  { type: "divider" },
  section(stepLines.join("\n") || "No steps ran."),
];
if (topErrors.length)
  blocks.push({ type: "divider" }, section(`*Playwright errors*\n\`\`\`\n${esc(topErrors.join("\n").slice(0, 2000))}\n\`\`\``));
if (matchLines.length) blocks.push({ type: "divider" }, section(`*Match*\n${matchLines.join("\n")}`));
if (failure) blocks.push({ type: "divider" }, section(`*Failure*\n${failureText}`));
if (checklist.length) blocks.push({ type: "divider" }, section(`*Step 18 checklist*\n${checklist.join("\n")}`));
blocks.push({
  type: "context",
  elements: [
    {
      type: "mrkdwn",
      text: [
        env.GITHUB_REF_NAME && `🌿 \`${env.GITHUB_REF_NAME}\` (\`${(env.GITHUB_SHA ?? "").slice(0, 8)}\`)`,
        env.GITHUB_EVENT_NAME && `⚡ ${env.GITHUB_EVENT_NAME}${env.GITHUB_ACTOR ? ` (${env.GITHUB_ACTOR})` : ""}`,
      ]
        .filter(Boolean)
        .join("  |  ") || "local run",
    },
  ],
});
if (runUrl) {
  blocks.push({
    type: "actions",
    elements: [
      { type: "button", text: { type: "plain_text", text: "📊 Report, screenshots & videos", emoji: true }, url: runUrl, ...(ok ? {} : { style: "danger" }) },
    ],
  });
}

async function post() {
  if (!env.SLACK_WEBHOOK) {
    console.log("\nSLACK_WEBHOOK not set — Slack message not sent.");
    return;
  }
  const r = await fetch(env.SLACK_WEBHOOK, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ text: heading, blocks }),
  });
  console.log(`\nSlack: ${r.status} ${await r.text()}`);
}

/// Failure screenshots into the channel, with Slack's current upload API
/// (files.upload was retired): get an upload URL, send the bytes, complete.
async function uploadEvidence() {
  const token = env.SLACK_BOT_TOKEN;
  const channel = env.SLACK_CHANNEL;
  if (!token || !channel || !failure) return;
  const shots = failure.evidence.filter((e) => e.type === "image/png" && existsSync(e.path)).slice(0, 5);
  for (const shot of shots) {
    const bytes = readFileSync(shot.path);
    const filename = `${basename(shot.path)}`;
    const q = new URLSearchParams({ filename, length: String(bytes.length) });
    const a = await fetch(`https://slack.com/api/files.getUploadURLExternal?${q}`, {
      headers: { Authorization: `Bearer ${token}` },
    }).then((r) => r.json());
    if (!a.ok) {
      console.log(`Slack upload refused: ${a.error}`);
      return;
    }
    await fetch(a.upload_url, { method: "POST", body: bytes });
    const done = await fetch("https://slack.com/api/files.completeUploadExternal", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({
        files: [{ id: a.file_id, title: `${failure.title.split(" — ")[0]}: ${shot.name}` }],
        channel_id: channel,
        initial_comment: `📸 ${failure.title} — ${shot.name}`,
      }),
    }).then((r) => r.json());
    console.log(`Slack upload ${shot.name}: ${done.ok ? "ok" : done.error}`);
  }
}

try {
  await post();
  await uploadEvidence();
} catch (e) {
  console.log(`Slack reporting failed: ${e.message}`);
}
