/**
 * Per-session git snapshot: the file-level undo that `checkpoint`/`rewind`
 * do NOT provide (those are conversation-only).
 *
 * At `session_start`, if the working directory is inside a git work tree,
 * build a tree from a throwaway index (`GIT_INDEX_FILE`) and commit it to
 * `refs/omp-snapshots/<YYYYMMDD-HHMMSS>`. This captures tracked changes AND
 * untracked, non-ignored files without touching the real index, the working
 * tree, or HEAD.
 *
 * Recover with:
 *   git for-each-ref --sort=-refname refs/omp-snapshots
 *   git restore --source=<ref> -- .          # bring files back
 *   git diff --stat HEAD <ref>               # see what the session changed
 *
 * Storage: refs are pruned after KEEP_DAYS. Snapshots share objects with
 * normal history, so repeated sessions cost little.
 *
 * Failure policy: every path is best-effort. A missing git, a huge repo, a
 * timeout, or a read-only checkout must never delay or break session start.
 */

import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

const KEEP_DAYS = 14;
const MAX_MS = 8000;
const PREFIX = "refs/omp-snapshots/";

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

  // GIT_INDEX_FILE redirects `git add` to a throwaway index in TMPDIR, so the
  // repository's real index is never written.
  const tmp = process.env.TMPDIR ?? "/tmp";
  const index = `${tmp.replace(/\/$/, "")}/omp-snapshot-${process.pid}-${Date.now()}.index`;
  const env = { GIT_INDEX_FILE: index };

  try {
    if (git(repo, ["add", "-A", "--", "."], env).code !== 0) return undefined;

    const tree = git(repo, ["write-tree"], env);
    if (tree.code !== 0 || !tree.out) return undefined;

    const head = git(repo, ["rev-parse", "--verify", "HEAD"]);
    const args = ["commit-tree", tree.out];
    if (head.code === 0 && head.out) args.push("-p", head.out);
    args.push("-m", `omp snapshot ${new Date().toISOString()}`);

    const commit = git(repo, args);
    if (commit.code !== 0 || !commit.out) return undefined;

    const ref = `${PREFIX}${stamp(new Date())}`;
    return git(repo, ["update-ref", ref, commit.out]).code === 0 ? ref : undefined;
  } finally {
    Bun.spawnSync({ cmd: ["rm", "-f", index], stdout: "ignore", stderr: "ignore" });
  }
}

function prune(repo: string) {
  const listed = git(repo, ["for-each-ref", "--format=%(refname)", PREFIX]);
  if (listed.code !== 0) return;
  const cutoff = stamp(new Date(Date.now() - KEEP_DAYS * 86_400_000));
  for (const raw of listed.out.split("\n")) {
    const name = raw.trim();
    if (!name.startsWith(PREFIX)) continue;
    const at = name.slice(PREFIX.length);
    if (/^\d{8}-\d{6}$/.test(at) && at < cutoff) git(repo, ["update-ref", "-d", name]);
  }
}

export default function snapshotHook(pi: ExtensionAPI) {
  pi.setLabel("Session snapshot");

  pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
    try {
      // Subagents share the parent's work tree; snapshotting each one would
      // duplicate the same work and add startup latency.
      if (ctx.agent?.kind === "sub") return;
      const cwd = ctx.cwd;
      if (!cwd) return;

      const ref = snapshot(cwd);
      if (ref) ctx.ui?.notify?.(`Snapshot: ${ref}`, "info");

      const top = git(cwd, ["rev-parse", "--show-toplevel"]);
      if (top.code === 0 && top.out) prune(top.out);
    } catch {
      // best effort only
    }
  });
}
