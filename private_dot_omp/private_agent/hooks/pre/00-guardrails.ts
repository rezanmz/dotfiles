/**
 * Deny-only workflow guardrails for omp.
 *
 * Why this exists: `tools.approvalMode` is `yolo` (no prompt per tool call),
 * so the only cheap, automation-safe gate is a hard refusal that returns a
 * reason the model can adapt to. `prompt` is deliberately avoided: in print /
 * headless runs nobody can answer it, so it would fail closed on every match.
 *
 * Scope: this is an approval/pattern gate, NOT a sandbox. Allowed commands
 * keep the full filesystem, network, and subprocess access of the shell.
 * `bash.patterns` in config.yml covers literal commands; this hook adds
 * whole-command regexes for the shapes globs cannot express (e.g. `rm -rf /`
 * with any flag order) and covers the `eval` escape hatch that
 * `bash.patterns` documents as out of scope.
 *
 * Fail-closed by design: a handler throw blocks the tool (omp contract).
 */

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

type Rule = { re: RegExp; reason: string };

/** Destructive or irreversible command shapes, matched against the whole command. */
const BASH_RULES: Rule[] = [
  {
    re: /\bgit\s+push\b[^\n;&|]*(?:--force(?!-with-lease)\b|(?:^|\s)-f(?:\s|$|&|\|))/i,
    reason: "force push is denied; use --force-with-lease or push a branch",
  },
  {
    // rm -rf / , rm -rf ~ , rm -rf $HOME , rm -rf *  (working-tree wipe)
    re: /\brm\s+(?:-[A-Za-z]*[rR][A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*[rR])\s+(?:\/|~|\$HOME|\*)\s*(?:$|;|&&|\|)/,
    reason: "refuses rm -rf of /, ~, $HOME, or the working tree",
  },
  {
    re: /\brm\b[^\n]*--no-preserve-root/,
    reason: "refuses rm --no-preserve-root",
  },
  {
    // `git push origin +main` is a force push written as a refspec.
    re: /\bgit\s+push\b[^\n;&|]*\s\+[^\s]+/,
    reason: "force-push refspec (+) is denied; use --force-with-lease",
  },
  {
    re: /\b(?:curl|wget)\b[^\n]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh|dash)\b/i,
    reason: "refuses piping a remote download into a shell",
  },
  {
    re: /\bdd\b[^\n]*\bof=\/dev\//,
    reason: "refuses raw writes to a block device",
  },
  {
    re: /\bmkfs(?:\.[A-Za-z0-9]+)?\b/,
    reason: "refuses filesystem creation",
  },
  {
    re: /\bdiskutil\s+(?:erase|zeroDisk|randomDisk|secureErase)\b/i,
    reason: "refuses disk erase",
  },
  {
    // Protect the config sources of truth from recursive removal. Requires an
    // -r flag so deleting a single file under those trees stays allowed.
    re: /\brm\s+-[A-Za-z]*[rR][A-Za-z]*[^\n]*(?:~\/\.(?:omp|ssh|gnupg)|~\/\.local\/share\/chezmoi)/,
    reason: "refuses recursive removal of omp/chezmoi/ssh state",
  },
];

/**
 * Narrower set for `eval` code. A code string legitimately contains command
 * text (tests, guardrail definitions), so only unambiguous exec surfaces are
 * matched here: nothing that merely mentions a pattern in a literal.
 */
const EVAL_RULES: Rule[] = [
  {
    re: /\bsubprocess\.(?:run|call|Popen)\s*\([^)]*(?:shell\s*=\s*True)/,
    reason: "eval code spawns a shell; use the bash tool instead",
  },
  {
    re: /\bBun\.\$\s*`[^`]*(?:rm\s+-rf\s+\/|mkfs|dd\s+[^`]*of=\/dev\/)/,
    reason: "eval code runs a destructive shell command",
  },
];

/** The documented `tool_call` payload: omp constructs it, so assert at the boundary. */
type ToolCallEvent = {
  toolName: string;
  input: Record<string, unknown>;
};

export default function guardrails(pi: ExtensionAPI) {
  pi.setLabel("Workstation guardrails");

  pi.on("tool_call", (event: ToolCallEvent) => {
    try {
      const text =
        event.toolName === "bash"
          ? String(event.input.command ?? "")
          : event.toolName === "eval"
            ? String(event.input.code ?? "")
            : "";
      if (!text) return;

      const rules = event.toolName === "bash" ? BASH_RULES : EVAL_RULES;
      const hit = rules.find((rule) => rule.re.test(text));
      if (hit) return { block: true, reason: `Blocked by guardrails: ${hit.reason}.` };
    } catch {
      // tool_call handling is fail-closed, so a throw here would block the
      // tool silently; return an explicit refusal instead.
      return { block: true, reason: "Blocked: guardrail hook failed to evaluate this call." };
    }
  });
}
