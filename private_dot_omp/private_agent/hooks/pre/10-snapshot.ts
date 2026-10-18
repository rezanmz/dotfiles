/**
 * File-level undo for omp — the gap that `checkpoint`/`rewind` do not cover
 * (those are conversation-only, per `omp://tools/checkpoint.md`).
 *
 * Two layers:
 *
 * 1. Session snapshot (coarse, covers bash damage). At `session_start` in a
 *    git work tree, build a tree from a throwaway index and commit it to
 *    `refs/omp-snapshots/<stamp>-<pid>-<seq>`. Captures tracked changes and
 *    untracked, non-ignored files. The real index, HEAD, and working tree are
 *    never touched. Skipped when the tree equals HEAD's tree (no change).
 *
 * 2. Pre-images (fine, covers edit/write damage). On every `write`/`edit`
 *    tool call, copy the target file's current bytes to
 *    `~/.omp/agent/cache/preimages/<stamp>-<pid>/files/<abs path>` and append
 *    a line to `manifest.jsonl` beside it. A create records `existed: false`;
 *    files over 2 MB are recorded as skipped.
 *
 * Recovery:
 *   git for-each-ref --sort=-refname refs/omp-snapshots
 *   git restore --source=<ref> -- .
 *   cat ~/.omp/agent/cache/preimages/<stamp>/manifest.jsonl
 *   cp ~/.omp/agent/cache/preimages/<stamp>/files/Users/you/repo/a.txt a.txt
 *
 * Retention: refs 14 days, pre-images 7 days, pruned at session start.
 * Failure policy: best effort everywhere; a snapshot must never delay or
 * break a session.
 */

import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { appendFileSync, copyFileSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { dirname } from "node:path";

const KEEP_DAYS = 14;
const PREIMAGE_KEEP_DAYS = 7;
const PREIMAGE_MAX_BYTES = 2 * 1024 * 1024;
const MAX_MS = 8000;
const PREFIX = "refs/omp-snapshots/";
const CACHE_ROOT = `${process.env.PI_CODING_AGENT_DIR ?? `${process.env.HOME ?? ""}/.omp/agent`}/cache/preimages`;

/** Per-session pre-image directory; set at session_start, null for subagents. */
let captureDir: string | null = null;
let refSeq = 0;

type Run = { code: number | null; out: string };

function git(cwd: string, args: string[], env?: Record<string, string>): Run {
  try {
    const proc = Bun.spawnSync({
      cmd: ["git", ...args],
      cwd,
      env: { ...process.env, ...env },
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
      timeout: MAX_MS,
    });
    return { code: proc.exitCode, out: proc.stdout.toString().trim() };
  } catch {
    return { code: null, out: "" };
  }
}

function stamp(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return (
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-` +
    `${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`
  );
}

function snapshot(cwd: string): string | undefined {
  const top = git(cwd, ["rev-parse", "--show-toplevel"]);
  if (top.code !== 0 || !top.out) return undefined;
  const repo = top.out;

  // GIT_INDEX_FILE redirects `git add` to a throwaway index, so the real
  // repository index is never written.
  const tmp = process.env.TMPDIR ?? "/tmp";
  const index = `${tmp.replace(/\/$/, "")}/omp-snapshot-${process.pid}-${Date.now()}.index`;
  const env = { GIT_INDEX_FILE: index };

  try {
    if (git(repo, ["add", "-A", "--", "."], env).code !== 0) return undefined;

    const tree = git(repo, ["write-tree"], env);
    if (tree.code !== 0 || !tree.out) return undefined;

    // Nothing changed since HEAD: an empty ref would only add noise.
    const head = git(repo, ["rev-parse", "--verify", "HEAD"]);
    if (head.code === 0 && head.out) {
      const headTree = git(repo, ["rev-parse", `${head.out}^{tree}`]);
      if (headTree.code === 0 && headTree.out === tree.out) return undefined;
    }

    const args = ["commit-tree", tree.out];
    if (head.code === 0 && head.out) args.push("-p", head.out);
    args.push("-m", `omp snapshot ${new Date().toISOString()}`);

    const commit = git(repo, args);
    if (commit.code !== 0 || !commit.out) return undefined;

    // pid + sequence make the ref unique even for two sessions in one second.
    const ref = `${PREFIX}${stamp(new Date())}-${process.pid}-${refSeq++}`;
    return git(repo, ["update-ref", ref, commit.out]).code === 0 ? ref : undefined;
  } finally {
    Bun.spawnSync({ cmd: ["rm", "-f", index], stdout: "ignore", stderr: "ignore" });
  }
}

function pruneRefs(repo: string) {
  const listed = git(repo, ["for-each-ref", "--format=%(refname)", PREFIX]);
  if (listed.code !== 0) return;
  const cutoff = stamp(new Date(Date.now() - KEEP_DAYS * 86_400_000));
  for (const raw of listed.out.split("\n")) {
    const name = raw.trim();
    // Format: refs/omp-snapshots/YYYYMMDD-HHMMSS-pid-seq
    const m = /^refs\/omp-snapshots\/(\d{8}-\d{6})-\d+-\d+$/.exec(name);
    if (m && m[1] < cutoff) git(repo, ["update-ref", "-d", name]);
  }
}

function prunePreimages() {
  const cutoff = Date.now() - PREIMAGE_KEEP_DAYS * 86_400_000;
  for (const entry of readdirSync(CACHE_ROOT)) {
    try {
      const dir = `${CACHE_ROOT}/${entry}`;
      if (statSync(dir).mtimeMs < cutoff) {
        Bun.spawnSync({ cmd: ["rm", "-rf", dir], stdout: "ignore", stderr: "ignore" });
      }
    } catch {
      // a vanished entry is fine
    }
  }
}

/** Paths an edit/write call is about to change. Internal URLs are not files. */
function targetPaths(tool: string, input: Record<string, unknown>): string[] {
  const found: string[] = [];
  if (typeof input.path === "string" && input.path) found.push(input.path);

  // Hashline edit payload: `[PATH#TAG]` section headers or `*** Edit File: PATH`.
  if (tool === "edit" && typeof input.input === "string") {
    for (const match of input.input.matchAll(/^(?:\[([^#\]]+)#|\*\*\* Edit File: (.+))$/gm)) {
      const path = (match[1] ?? match[2] ?? "").trim();
      if (path) found.push(path);
    }
  }

  return found
    .filter((path, index) => found.indexOf(path) === index)
    .filter(
      (path) => !path.includes("://") && !path.startsWith("db.sqlite:") && !path.startsWith("archive."),
    );
}

function capturePreimage(cwd: string, tool: string, input: Record<string, unknown>) {
  if (!captureDir) return;
  for (const raw of targetPaths(tool, input)) {
    const abs = raw.startsWith("/") ? raw : `${cwd}/${raw}`;
    let existed = false;
    let size = 0;
    let skipped: string | undefined;
    try {
      const info = statSync(abs);
      existed = info.isFile();
      size = info.size;
      if (!existed) skipped = "not-a-file";
      else if (size > PREIMAGE_MAX_BYTES) skipped = "size";
    } catch {
      existed = false; // a create: remember it so recovery can delete the file
    }

    if (existed && !skipped) {
      const dest = `${captureDir}/files${abs}`;
      mkdirSync(dirname(dest), { recursive: true });
      copyFileSync(abs, dest);
    }
    appendFileSync(
      `${captureDir}/manifest.jsonl`,
      `${JSON.stringify({ at: new Date().toISOString(), tool, path: abs, existed, size, skipped })}\n`,
    );
  }
}

type ToolCallEvent = {
  toolName: string;
  input: Record<string, unknown>;
};

export default function snapshotHook(pi: ExtensionAPI) {
  pi.setLabel("Session snapshot");

  pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
    try {
      // Subagents share the parent's work tree; snapshotting each one would
      // duplicate the same work and add startup latency.
      if (ctx.agent?.kind === "sub") return;
      const cwd = ctx.cwd;
      if (!cwd) return;

      captureDir = `${CACHE_ROOT}/${stamp(new Date())}-${process.pid}`;
      mkdirSync(captureDir, { recursive: true });

      const ref = snapshot(cwd);
      if (ref) ctx.ui?.notify?.(`Snapshot: ${ref}`, "info");

      const top = git(cwd, ["rev-parse", "--show-toplevel"]);
      if (top.code === 0 && top.out) pruneRefs(top.out);
      prunePreimages();
    } catch {
      // best effort only
    }
  });

  pi.on("tool_call", (event: ToolCallEvent, ctx: ExtensionContext) => {
    try {
      if (event.toolName !== "write" && event.toolName !== "edit") return;
      if (!ctx.cwd) return;
      capturePreimage(ctx.cwd, event.toolName, event.input);
    } catch {
      // Never block an edit because the safety net failed.
    }
  });
}
