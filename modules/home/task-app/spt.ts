#!/usr/bin/env bun
/**
 * spt: Super Productivity from the shell.
 *
 * A thin, dependency-free wrapper over the desktop app's local REST API
 * (`http://127.0.0.1:3876`). The app's own docs live in its repo at
 * `docs/wiki/3.01-API.md`; this file is the agent-facing surface: `spt --help`
 * prints every command, field and exit code, and `spt get|post|patch|put|delete`
 * reaches the routes the named commands do not cover.
 *
 * Transport is `node:http` on purpose. Bun's `fetch` honours HTTP_PROXY /
 * HTTPS_PROXY, which would send the bearer token to a configured proxy even
 * for a loopback URL. `node:http` never does.
 *
 * Every command has a flag spec; unknown flags, extra positionals and
 * conflicting pairs are rejected rather than silently ignored.
 */
import { request, type ClientRequest } from "node:http";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DEFAULT_BASE = "http://127.0.0.1:3876";
const CLI_VERSION = "1.2.0";
const REQUEST_TIMEOUT_MS = 20_000;
const MAX_RESPONSE_BYTES = 16 * 1024 * 1024;
const TOKEN_PATTERN = /^[A-Za-z0-9]{32}$/;

const EXIT_OK = 0;
const EXIT_API = 1;
const EXIT_USAGE = 2;
const EXIT_OFFLINE = 3;

class UsageError extends Error {}
class ApiError extends Error {
  constructor(
    public code: string,
    message: string,
    public status = 0,
  ) {
    super(message);
  }
}

const HELP = `spt - Super Productivity from the shell. CLI ${CLI_VERSION}.

Talks to the desktop app's local REST API. The app must be running with
Settings > Misc > Enable local REST API switched on (desktop only, not the
web or Android build). After a home-manager switch, restart the app: it reads
the token and the switch only at startup.

Auth   SP_API_TOKEN, else $XDG_CONFIG_HOME/superProductivity/local-rest-api-token
Base   SP_API_URL, default ${DEFAULT_BASE}; http only, no path prefix
Output JSON on stdout, except "spt help" which prints this text.
Errors are {error,code} JSON on stderr.
Exit   0 ok, 1 API error, 2 usage, 3 app unreachable or not ready

TASKS
  spt tasks list [--query Q] [--project ID] [--tag ID] [--done]
                 [--archive] [--all]
                 short flags: -q, -p, -t for --query, --project, --tag
  spt tasks get ID [--issue-url]
  spt tasks add --title T [--notes N] [--project ID] [--tags ID,ID]
                [--due DATE] [--at ISO_TIMESTAMP] [--deadline DATE]
                [--estimate 90m] [--parent ID] [--literal]
  spt tasks edit ID [--title T] [--notes N] [--done|--undone]
                [--due DATE|--no-due] [--at ISO_TIMESTAMP|--no-at]
                [--deadline DATE|--no-deadline] [--project ID]
                [--tags ID,ID|--no-tags] [--estimate 90m|--no-estimate] [--literal]
  spt tasks rm ID --yes
  spt tasks start ID
  spt tasks stop
  spt tasks archive ID
  spt tasks restore ID
  spt tasks time ID --duration 90m [--day DATE]   add time on a day (POST)
  spt tasks time ID --set 90m|0 [--day DATE]      set that day's total (PUT)

NOTES
  spt notes list [--project ID]
  spt notes get ID
  spt notes add --content TEXT (--project ID | --pinned)
  spt notes edit ID [--content TEXT] [--project ID] [--pinned|--unpinned]
                 a project move must be its own request
  spt notes rm ID --yes

READ
  spt projects
  spt tags
  spt status
  spt version              CLI version, not the app's

RAW, for the routes the commands above do not cover
(/task-repeat-cfgs, /simple-counters, /focus):
  spt get PATH
  spt post PATH [--json JSON|@FILE]
  spt patch PATH [--json JSON|@FILE]
  spt put PATH [--json JSON|@FILE]
  spt delete PATH --yes
  --body is an alias for --json. Pass --flag=value when the value starts with --.
  /health needs no token and works as a liveness probe.
  /assistant/capture is not reachable over HTTP: the app only accepts it from MCP.

TASK FIELDS
  title, notes, isDone, timeEstimate, timeSpent, projectId, tagIds,
  dueDay, dueWithTime, plannedAt, deadlineDay, deadlineWithTime, deadlineRemindAt.
  parentId and subTaskIds are rejected by PATCH: create a subtask with --parent.
  API-shaped flag aliases are accepted: --due-day, --due-with-time, --deadline-day,
  --project-id, --tag-ids, --time-estimate, --is-done.
  Duration accepts 90m, 2h, 1h30m; a bare integer means minutes.
  DATE is YYYY-MM-DD, or today / tomorrow. --at needs a date and time.
  On list, --done includes completed tasks, --archive returns archived tasks
  (completed ones included), and --all returns active and archived together.
  --due clears the scheduled time, --at clears the due day; passing both is an
  error. --no-due clears both. --no-estimate writes 0, because the API rejects
  null there. --set 0 clears that day's logged time.
  --project and --tags are checked against /projects and /tags before a task is
  created, so a typo fails instead of creating an unseen task.
  20.0.0 reports its logical day; 19.3.1 does not. On 19.3.1, --due and
  --deadline today/tomorrow fail loudly unless SP_LOCAL_DAY=1 is set, which is
  only correct when start-of-next-day is 00:00. tasks time --day today retries
  against the local date, and --day tomorrow is refused. Explicit dates work.
  Titles go through the app's short syntax unless --literal, for example
  "milk #shopping @tomorrow 15m" sets a tag, a due day and an estimate.

EXAMPLES
  spt status
  spt tasks list --done --query invoice
  spt tasks list --archive
  spt tasks time 3fQ7 --set 0
  spt tasks add --title "milk #shopping 15m" --due tomorrow
  spt tasks edit 3fQ7 --notes "second aisle" --done
  spt tasks time 3fQ7 --duration 45m --day 2026-11-14
  spt get /task-repeat-cfgs
  spt put /simple-counters/abc/value --json '{"date":"2026-11-15","value":2}'
`;

function tokenFile(): string {
  const configHome = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
  return join(configHome, "superProductivity", "local-rest-api-token");
}

function resolveToken(): string {
  const fromEnv = process.env.SP_API_TOKEN;
  if (fromEnv !== undefined) {
    const token = fromEnv.trim();
    if (!TOKEN_PATTERN.test(token)) {
      throw new UsageError(
        "SP_API_TOKEN is not 32 alphanumeric characters; unset it to use the app's token file",
      );
    }
    return token;
  }
  const file = tokenFile();
  let token: string;
  try {
    token = readFileSync(file, "utf8").trim();
  } catch {
    throw new UsageError(
      `no API token: set SP_API_TOKEN, or switch on Settings > Misc > Enable local REST API and put the token in ${file}`,
    );
  }
  if (!TOKEN_PATTERN.test(token)) {
    throw new UsageError(
      `${file} does not hold 32 alphanumeric characters; regenerate the token in Settings > Misc > Access Token`,
    );
  }
  return token;
}

interface Reply {
  status: number;
  data: unknown;
}

function api(method: string, path: string, body?: unknown): Promise<Reply> {
  const base = process.env.SP_API_URL || DEFAULT_BASE;
  let baseUrl: URL;
  try {
    baseUrl = new URL(base);
  } catch {
    return Promise.reject(new UsageError(`SP_API_URL is not a URL: ${base}`));
  }
  if (baseUrl.protocol !== "http:") {
    return Promise.reject(
      new UsageError("SP_API_URL must start with http://; this client does not do TLS"),
    );
  }
  if (baseUrl.pathname !== "/" || baseUrl.search || baseUrl.hash) {
    return Promise.reject(
      new UsageError("SP_API_URL must not carry a path, query or fragment"),
    );
  }

  let target: URL;
  try {
    target = new URL(path, baseUrl);
  } catch {
    return Promise.reject(new UsageError(`bad path: ${path}`));
  }
  if (target.protocol !== baseUrl.protocol || target.host !== baseUrl.host) {
    return Promise.reject(
      new UsageError(`refusing to send the token outside ${baseUrl.host}: ${path}`),
    );
  }

  const payload = body === undefined ? undefined : JSON.stringify(body);
  const token = target.pathname === "/health" ? undefined : resolveToken();

  return new Promise((resolve, reject) => {
    let settled = false;
    let timer: ReturnType<typeof setTimeout>;
    let req: ClientRequest;

    const finish = (settle: () => void) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      settle();
    };

    timer = setTimeout(() => {
      finish(() => {
        req.destroy();
        reject(
          new ApiError(
            "TIMEOUT",
            `no reply from ${baseUrl.host} within ${REQUEST_TIMEOUT_MS}ms`,
            0,
          ),
        );
      });
    }, REQUEST_TIMEOUT_MS);

    try {
      req = request(
      {
        hostname: target.hostname.replace(/^\[|\]$/g, ""),
        port: target.port || 80,
        path: target.pathname + target.search,
        method,
        // No keep-alive: a pooled socket would hold the process open after the
        // reply, and the CLI exits on its own instead of calling process.exit,
        // which can truncate a piped stdout buffer.
        agent: false,
        headers: {
          Accept: "application/json",
          Connection: "close",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...(payload
            ? {
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(payload),
              }
            : {}),
        },
      },
      (res) => {
        let raw = "";
        let bytes = 0;
        res.setEncoding("utf8");
        res.on("data", (chunk: string) => {
          bytes += Buffer.byteLength(chunk);
          if (bytes > MAX_RESPONSE_BYTES) {
            finish(() => {
              req.destroy();
              reject(
                new ApiError(
                  "RESPONSE_TOO_LARGE",
                  `response exceeded ${MAX_RESPONSE_BYTES} bytes`,
                  0,
                ),
              );
            });
            return;
          }
          raw += chunk;
        });
        // A peer that dies mid-body emits aborted/error on the response, not on
        // the request. Without these the promise would never settle.
        res.on("aborted", () =>
          finish(() =>
            reject(new ApiError("RESPONSE_ABORTED", "the app closed the connection mid-reply", 0)),
          ),
        );
        res.on("error", (error: Error) =>
          finish(() =>
            reject(new ApiError("RESPONSE_ABORTED", error.message, 0)),
          ),
        );
        res.on("end", () =>
          finish(() => {
            const status = res.statusCode ?? 0;
            let parsed: any;
            let isJson = false;
            try {
              parsed = raw.trim() ? JSON.parse(raw) : undefined;
              isJson = raw.trim() !== "";
            } catch {
              isJson = false;
            }

            if (isJson && parsed && parsed.ok === false) {
              reject(
                new ApiError(
                  parsed.error?.code ?? "API_ERROR",
                  parsed.error?.message ?? "API error",
                  status,
                ),
              );
              return;
            }
            if (status < 200 || status >= 300) {
              reject(
                new ApiError(
                  `HTTP_${status}`,
                  raw.trim().slice(0, 200) || `HTTP ${status} from ${target.host}`,
                  status,
                ),
              );
              return;
            }
            if (!isJson) {
              if (!raw.trim()) {
                resolve({ status, data: null });
                return;
              }
              reject(
                new ApiError(
                  "NON_JSON_RESPONSE",
                  `expected JSON from ${target.host}, got: ${raw.slice(0, 200)}`,
                  status,
                ),
              );
              return;
            }
            const data =
              parsed &&
              typeof parsed === "object" &&
              Object.prototype.hasOwnProperty.call(parsed, "data")
                ? parsed.data
                : parsed;
            resolve({ status, data });
          }),
        );
      },
      );
    } catch (error) {
      finish(() =>
        reject(
          new ApiError(
            "OFFLINE",
            `cannot build the request: ${(error as Error).message}`,
            0,
          ),
        ),
      );
      return;
    }

    req.on("error", (error: NodeJS.ErrnoException) => {
      finish(() =>
        reject(
          new ApiError(
            "OFFLINE",
            `cannot reach ${baseUrl.host} (${error.code ?? error.message}); is Super Productivity running with the local REST API enabled?`,
            0,
          ),
        ),
      );
    });
    if (payload) req.write(payload);
    req.end();
  });
}

type Flags = Record<string, string | true>;
type FlagKind = "value" | "bool";

interface Spec {
  flags: Record<string, FlagKind>;
  positionals: number;
  conflicts?: [string, string][];
}

const FLAG_ALIASES: Record<string, string> = {
  "due-day": "due",
  "due-with-time": "at",
  "deadline-day": "deadline",
  "project-id": "project",
  "tag-ids": "tags",
  "time-estimate": "estimate",
  "is-done": "done",
};

const UNIVERSAL: Record<string, FlagKind> = {
  help: "bool",
  h: "bool",
  version: "bool",
};

const COMMON_PROJECT = { project: "value", p: "value" } as const;

const SPECS: Record<string, Spec> = {
  status: { flags: {}, positionals: 0 },
  projects: { flags: {}, positionals: 0 },
  tags: { flags: {}, positionals: 0 },
  version: { flags: {}, positionals: 0 },

  "tasks list": {
    flags: {
      query: "value",
      q: "value",
      ...COMMON_PROJECT,
      tag: "value",
      t: "value",
      done: "bool",
      archive: "bool",
      all: "bool",
    },
    positionals: 0,
    conflicts: [["archive", "all"]],
  },
  "tasks get": { flags: { "issue-url": "bool" }, positionals: 1 },
  "tasks add": {
    flags: {
      title: "value",
      notes: "value",
      ...COMMON_PROJECT,
      tags: "value",
      due: "value",
      at: "value",
      deadline: "value",
      estimate: "value",
      parent: "value",
      literal: "bool",
    },
    positionals: 0,
    conflicts: [["due", "at"]],
  },
  "tasks edit": {
    flags: {
      title: "value",
      notes: "value",
      done: "bool",
      undone: "bool",
      due: "value",
      "no-due": "bool",
      at: "value",
      "no-at": "bool",
      deadline: "value",
      "no-deadline": "bool",
      ...COMMON_PROJECT,
      tags: "value",
      "no-tags": "bool",
      estimate: "value",
      "no-estimate": "bool",
      literal: "bool",
    },
    positionals: 1,
    conflicts: [
      ["done", "undone"],
      ["due", "no-due"],
      ["at", "no-at"],
      ["deadline", "no-deadline"],
      ["tags", "no-tags"],
      ["estimate", "no-estimate"],
      ["due", "at"],
    ],
  },
  "tasks rm": { flags: { yes: "bool" }, positionals: 1 },
  "tasks start": { flags: {}, positionals: 1 },
  "tasks stop": { flags: {}, positionals: 0 },
  "tasks archive": { flags: {}, positionals: 1 },
  "tasks restore": { flags: {}, positionals: 1 },
  "tasks time": {
    flags: { duration: "value", set: "value", day: "value" },
    positionals: 1,
    conflicts: [["duration", "set"]],
  },

  "notes list": { flags: { ...COMMON_PROJECT }, positionals: 0 },
  "notes get": { flags: {}, positionals: 1 },
  "notes add": {
    flags: { content: "value", ...COMMON_PROJECT, pinned: "bool" },
    positionals: 0,
  },
  "notes edit": {
    flags: {
      content: "value",
      ...COMMON_PROJECT,
      pinned: "bool",
      unpinned: "bool",
    },
    positionals: 1,
    conflicts: [["pinned", "unpinned"]],
  },
  "notes rm": { flags: { yes: "bool" }, positionals: 1 },

  get: { flags: {}, positionals: 1 },
  post: { flags: { json: "value", body: "value" }, positionals: 1 },
  patch: { flags: { json: "value", body: "value" }, positionals: 1 },
  put: { flags: { json: "value", body: "value" }, positionals: 1 },
  delete: { flags: { json: "value", body: "value", yes: "bool" }, positionals: 1 },
};

const COMMAND_ALIASES: Record<string, string> = { task: "tasks", note: "notes" };
const SUB_ALIASES: Record<string, string> = {
  ls: "list",
  show: "get",
  create: "add",
  update: "edit",
  delete: "rm",
};

function parse(argv: string[], spec: Spec): { pos: string[]; flags: Flags } {
  const kinds: Record<string, FlagKind> = { ...UNIVERSAL, ...spec.flags };
  const pos: string[] = [];
  const flags: Flags = {};

  const setBoolean = (key: string, value: string | undefined) => {
    if (value === undefined || value === "true") {
      flags[key] = true;
      return;
    }
    if (value === "false") {
      delete flags[key];
      return;
    }
    throw new UsageError(`--${key} takes true or false`);
  };

  const takeValue = (key: string, index: number): number => {
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) {
      throw new UsageError(`missing value for --${key}`);
    }
    flags[key] = next;
    return index + 1;
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--") {
      pos.push(...argv.slice(i + 1));
      break;
    }
    if (arg.startsWith("--")) {
      const eq = arg.indexOf("=");
      if (eq > 0) {
        const key = FLAG_ALIASES[arg.slice(2, eq)] ?? arg.slice(2, eq);
        const value = arg.slice(eq + 1);
        if (kinds[key] === undefined) {
          throw new UsageError(`unknown flag --${key}; see spt --help`);
        }
        if (kinds[key] === "value") flags[key] = value;
        else setBoolean(key, value);
        continue;
      }
      const key = FLAG_ALIASES[arg.slice(2)] ?? arg.slice(2);
      if (kinds[key] === "value") i = takeValue(key, i);
      else flags[key] = true;
      continue;
    }
    if (arg.startsWith("-") && arg.length === 2) {
      const key = arg.slice(1);
      if (kinds[key] === "value") i = takeValue(key, i);
      else flags[key] = true;
      continue;
    }
    pos.push(arg);
  }
  return { pos, flags };
}

function validate(name: string, spec: Spec, flags: Flags, args: string[]): void {
  const allowed = new Set([...Object.keys(UNIVERSAL), ...Object.keys(spec.flags)]);
  for (const key of Object.keys(flags)) {
    if (!allowed.has(key)) {
      throw new UsageError(`unknown flag --${key} for ${name}; see spt --help`);
    }
  }
  if (args.length !== spec.positionals) {
    const plural = spec.positionals === 1 ? "" : "s";
    throw new UsageError(
      `${name} takes ${spec.positionals} argument${plural}, got ${args.length}`,
    );
  }
  for (const [left, right] of spec.conflicts ?? []) {
    if (flags[left] !== undefined && flags[right] !== undefined) {
      throw new UsageError(`--${left} and --${right} are mutually exclusive`);
    }
  }
}

function text(flags: Flags, ...keys: string[]): string | undefined {
  for (const key of keys) {
    const value = flags[key];
    if (typeof value === "string") return value;
  }
  return undefined;
}

function required(value: string | undefined, label: string): string {
  if (value === undefined || value === "") {
    throw new UsageError(`missing ${label}`);
  }
  return value;
}

function nonEmpty(value: string | undefined, label: string): string | undefined {
  if (value === undefined) return undefined;
  if (value.trim() === "") throw new UsageError(`${label} cannot be empty`);
  return value;
}

function list(value: string): string[] {
  return [...new Set(value.split(",").map((item) => item.trim()).filter(Boolean))];
}

function tagIds(value: string): string[] {
  const ids = list(value);
  if (ids.length === 0) {
    throw new UsageError("--tags needs at least one id; use --no-tags to clear");
  }
  if (ids.includes("TODAY")) {
    throw new UsageError("TODAY is a virtual tag; use --due today instead");
  }
  return ids;
}

function duration(value: string, allowZero = false): number {
  const trimmed = value.trim();
  if (/^\d+$/.test(trimmed)) {
    const ms = Number(trimmed) * 60_000;
    if (ms === 0 && !allowZero) {
      throw new UsageError(`bad duration "${value}": must be positive`);
    }
    return ms;
  }
  const pattern =
    /^(?:(\d+(?:\.\d+)?)h)?(?:(\d+(?:\.\d+)?)m)?(?:(\d+(?:\.\d+)?)s)?$/i;
  const match = pattern.exec(trimmed);
  if (!match || !trimmed) {
    throw new UsageError(`bad duration "${value}": use 90m, 2h or 1h30m`);
  }
  const [, h, m, s] = match;
  const ms = Math.round(
    Number(h ?? 0) * 3_600_000 +
      Number(m ?? 0) * 60_000 +
      Number(s ?? 0) * 1_000,
  );
  if (ms === 0 && allowZero) return 0;
  if (ms <= 0) throw new UsageError(`bad duration "${value}": must be positive`);
  return ms;
}

function localDay(): string {
  const date = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function addDays(day: string, offsetDays: number): string {
  const [year, month, date] = day.split("-").map(Number);
  const shifted = new Date(Date.UTC(year, month - 1, date + offsetDays));
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${shifted.getUTCFullYear()}-${pad(shifted.getUTCMonth() + 1)}-${pad(shifted.getUTCDate())}`;
}

/** Explicit dates only; `today` and `tomorrow` need the app's logical day. */
function parseDate(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
    throw new UsageError(`bad date "${value}": use YYYY-MM-DD, today or tomorrow`);
  }
  const [year, month, day] = normalized.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    throw new UsageError(`bad date "${value}": no such calendar day`);
  }
  return normalized;
}

let cachedToday: { day: string; fromApp: boolean } | undefined;

/**
 * The app's logical day. 20.0.0 reports `todayStr` from /status; 19.3.1 does
 * not, and no other endpoint exposes it.
 */
async function appToday(): Promise<{ day: string; fromApp: boolean }> {
  if (cachedToday) return cachedToday;
  const { data } = await api("GET", "/status");
  const today = (data as { todayStr?: unknown } | null)?.todayStr;
  if (typeof today === "string" && /^\d{4}-\d{2}-\d{2}$/.test(today)) {
    cachedToday = { day: today, fromApp: true };
    return cachedToday;
  }
  cachedToday = { day: localDay(), fromApp: false };
  return cachedToday;
}

async function resolveDate(value: string): Promise<string> {
  const normalized = value.trim().toLowerCase();
  if (normalized !== "today" && normalized !== "tomorrow") {
    return parseDate(value);
  }
  const today = await appToday();
  if (!today.fromApp && process.env.SP_LOCAL_DAY !== "1") {
    throw new UsageError(
      "the app does not report its logical day (19.3.1); pass YYYY-MM-DD, or set SP_LOCAL_DAY=1 if start-of-next-day is 00:00",
    );
  }
  return normalized === "today" ? today.day : addDays(today.day, 1);
}

function instant(value: string): number {
  const trimmed = value.trim();
  if (/^\d+$/.test(trimmed)) {
    const ms = Number(trimmed);
    if (ms <= 0) throw new UsageError("--at must be a positive timestamp");
    return ms;
  }
  if (!/^\d{4}-\d{2}-\d{2}T/.test(trimmed)) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
      throw new UsageError("--at needs a date and time; use --due for a day");
    }
    throw new UsageError(`bad instant "${value}": use ISO 8601 with a time or epoch ms`);
  }
  parseDate(trimmed.slice(0, 10));
  const ms = Date.parse(trimmed);
  if (!Number.isFinite(ms) || ms <= 0) {
    throw new UsageError(`bad instant "${value}"`);
  }
  return ms;
}

function jsonBody(flags: Flags): unknown {
  if (text(flags, "json") !== undefined && text(flags, "body") !== undefined) {
    throw new UsageError("--json and --body are the same field; use one");
  }
  const raw = text(flags, "json", "body");
  if (raw === undefined) return undefined;
  let source = raw;
  if (raw.startsWith("@")) {
    try {
      source = readFileSync(raw.slice(1), "utf8");
    } catch (error) {
      throw new UsageError(
        `cannot read ${raw.slice(1)}: ${(error as Error).message}`,
      );
    }
  }
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new UsageError(`--json is not valid JSON: ${(error as Error).message}`);
  }
}

async function assertProject(id: string): Promise<string> {
  const { data } = await api("GET", "/projects");
  if (!Array.isArray(data) || !data.some((project: any) => project?.id === id)) {
    throw new ApiError("PROJECT_NOT_FOUND", `no project with id ${id}`, 0);
  }
  return id;
}

async function assertTags(ids: string[]): Promise<string[]> {
  if (ids.length === 0) return ids;
  const { data } = await api("GET", "/tags");
  const known = new Set(
    Array.isArray(data) ? data.map((tag: any) => tag?.id) : [],
  );
  const missing = ids.filter((id) => !known.has(id));
  if (missing.length > 0) {
    throw new ApiError(
      "TAG_NOT_FOUND",
      `no tag with id ${missing.join(", ")}`,
      0,
    );
  }
  return ids;
}

async function taskList(flags: Flags): Promise<Reply> {
  const query = new URLSearchParams();
  const source =
    flags.archive === true ? "archived" : flags.all === true ? "all" : "active";
  query.set("source", source);
  const search = nonEmpty(text(flags, "query", "q"), "--query");
  if (search) query.set("query", search);
  const project = nonEmpty(text(flags, "project", "p"), "--project");
  if (project) query.set("projectId", project);
  const tag = nonEmpty(text(flags, "tag", "t"), "--tag");
  if (tag) query.set("tagId", (await assertTags([tag]))[0]);
  // Archived done tasks are filtered out unless includeDone is set, so
  // --archive and --all opt into them; --done does the same for active tasks.
  if (flags.done === true || source !== "active") {
    query.set("includeDone", "true");
  }
  return api("GET", `/tasks?${query.toString()}`);
}

async function taskAdd(flags: Flags): Promise<Reply> {
  const body: Record<string, unknown> = {
    title: required(text(flags, "title"), "--title"),
  };
  const notes = text(flags, "notes");
  if (notes !== undefined) body.notes = notes;
  const parent = nonEmpty(text(flags, "parent"), "--parent");
  const project = nonEmpty(text(flags, "project", "p"), "--project");
  const tags = nonEmpty(text(flags, "tags"), "--tags");
  if (parent) {
    if (project || tags) {
      throw new UsageError(
        "a subtask inherits project and tags from its parent; drop --project/--tags",
      );
    }
    body.parentId = parent;
  } else {
    if (project) body.projectId = await assertProject(project);
    if (tags) body.tagIds = await assertTags(tagIds(tags));
  }
  const due = nonEmpty(text(flags, "due"), "--due");
  if (due) body.dueDay = await resolveDate(due);
  const at = nonEmpty(text(flags, "at"), "--at");
  if (at) body.dueWithTime = instant(at);
  const deadline = nonEmpty(text(flags, "deadline"), "--deadline");
  if (deadline) body.deadlineDay = await resolveDate(deadline);
  const estimate = nonEmpty(text(flags, "estimate"), "--estimate");
  if (estimate) body.timeEstimate = duration(estimate);
  if (flags.literal === true) body.isIgnoreShortSyntax = true;
  return api("POST", "/tasks", body);
}

async function taskEdit(flags: Flags, id: string): Promise<Reply> {
  const body: Record<string, unknown> = {};
  const title = nonEmpty(text(flags, "title"), "--title");
  if (title !== undefined) body.title = title;
  const notes = text(flags, "notes");
  if (notes !== undefined) body.notes = notes;
  if (flags.done === true) body.isDone = true;
  if (flags.undone === true) body.isDone = false;
  if (flags["no-due"] === true) {
    // Clearing only dueDay would leave a scheduled task on the timeline.
    body.dueDay = null;
    body.dueWithTime = null;
  } else {
    const due = nonEmpty(text(flags, "due"), "--due");
    if (due) {
      // dueDay and dueWithTime are mutually exclusive in the app model.
      body.dueDay = await resolveDate(due);
      body.dueWithTime = null;
    }
  }
  if (flags["no-at"] === true) body.dueWithTime = null;
  else {
    const at = nonEmpty(text(flags, "at"), "--at");
    if (at) {
      body.dueWithTime = instant(at);
      body.dueDay = null;
    }
  }
  if (flags["no-deadline"] === true) {
    body.deadlineDay = null;
    body.deadlineWithTime = null;
  } else {
    const deadline = nonEmpty(text(flags, "deadline"), "--deadline");
    if (deadline) body.deadlineDay = await resolveDate(deadline);
  }
  const project = nonEmpty(text(flags, "project", "p"), "--project");
  if (project) body.projectId = project;
  if (flags["no-tags"] === true) body.tagIds = [];
  else {
    const tags = text(flags, "tags");
    if (tags !== undefined) body.tagIds = await assertTags(tagIds(tags));
  }
  if (flags["no-estimate"] === true) body.timeEstimate = 0;
  else {
    const estimate = nonEmpty(text(flags, "estimate"), "--estimate");
    if (estimate) body.timeEstimate = duration(estimate);
  }
  if (flags.literal === true) body.isIgnoreShortSyntax = true;
  const changed = Object.keys(body).filter((key) => key !== "isIgnoreShortSyntax");
  if (changed.length === 0) {
    throw new UsageError("nothing to change: pass at least one field");
  }
  return api("PATCH", `/tasks/${encodeURIComponent(id)}`, body);
}

async function taskTime(flags: Flags, id: string): Promise<Reply> {
  const set = text(flags, "set");
  const method = set !== undefined ? "PUT" : "POST";
  const amount =
    set !== undefined
      ? duration(set, true)
      : duration(required(text(flags, "duration"), "--duration or --set"));

  const day = nonEmpty(text(flags, "day"), "--day");
  const keyword = day?.trim().toLowerCase();
  let initial: string;
  let explicitDay: boolean;

  if (day === undefined) {
    initial = (await appToday()).day;
    explicitDay = false;
  } else if (keyword === "today") {
    initial = (await appToday()).day;
    explicitDay = false;
  } else if (keyword === "tomorrow") {
    const today = await appToday();
    if (!today.fromApp && process.env.SP_LOCAL_DAY !== "1") {
      throw new UsageError(
        "cannot resolve `tomorrow` without the app's logical day; pass YYYY-MM-DD",
      );
    }
    initial = addDays(today.day, 1);
    explicitDay = true;
  } else {
    initial = parseDate(day);
    explicitDay = true;
  }

  const send = (date: string) =>
    api(method, `/tasks/${encodeURIComponent(id)}/time`, {
      date,
      duration: amount,
    });

  try {
    return await send(initial);
  } catch (error) {
    // 19.3.1 does not expose the app's logical day, so a defaulted "today"
    // can be one day ahead of it. Retry once on that specific rejection.
    if (
      explicitDay ||
      !(error instanceof ApiError) ||
      error.code !== "INVALID_INPUT" ||
      !/after today/i.test(error.message)
    ) {
      throw error;
    }
    return send(addDays(initial, -1));
  }
}

async function noteEdit(flags: Flags, id: string): Promise<Reply> {
  const body: Record<string, unknown> = {};
  const content = text(flags, "content");
  const project = nonEmpty(text(flags, "project", "p"), "--project");
  if (
    project &&
    (content !== undefined || flags.pinned === true || flags.unpinned === true)
  ) {
    throw new UsageError(
      "a project move must be its own request: drop --content/--pinned/--unpinned",
    );
  }
  if (content !== undefined) body.content = content;
  if (project) body.projectId = project;
  if (flags.pinned === true) body.isPinnedToToday = true;
  if (flags.unpinned === true) body.isPinnedToToday = false;
  if (Object.keys(body).length === 0) {
    throw new UsageError(
      "nothing to change: pass --content, --project, --pinned or --unpinned",
    );
  }
  return api("PATCH", `/notes/${encodeURIComponent(id)}`, body);
}

async function run(argv: string[]): Promise<Reply> {
  if (argv.length === 0) return { status: 0, data: HELP };
  if (argv[0] === "help" || argv[0] === "--help" || argv[0] === "-h") {
    return { status: 0, data: HELP };
  }
  if (argv[0] === "version" || argv[0] === "--version") {
    return { status: 0, data: { cli: CLI_VERSION } };
  }

  const rawCommand = argv[0];
  const command = COMMAND_ALIASES[rawCommand] ?? rawCommand;
  const twoWord = command === "tasks" || command === "notes";
  const rawSub = twoWord ? argv[1] : undefined;
  const sub = rawSub ? (SUB_ALIASES[rawSub] ?? rawSub) : undefined;
  const name = twoWord ? `${command} ${sub ?? ""}`.trim() : command;
  const spec = SPECS[name];
  if (!spec) {
    if (argv.includes("--help") || argv.includes("-h")) {
      return { status: 0, data: HELP };
    }
    throw new UsageError(
      `unknown command "${[rawCommand, rawSub].filter(Boolean).join(" ")}"; see spt --help`,
    );
  }

  const { pos, flags } = parse(argv, spec);
  if (flags.help === true || flags.h === true) {
    return { status: 0, data: HELP };
  }
  if (flags.version === true) {
    return { status: 0, data: { cli: CLI_VERSION } };
  }
  const args = twoWord ? pos.slice(2) : pos.slice(1);
  validate(name, spec, flags, args);
  const id = () => required(args[0], "id");

  if (command === "status") return api("GET", "/status");
  if (command === "projects") return api("GET", "/projects");
  if (command === "tags") return api("GET", "/tags");
  if (command === "version") return { status: 0, data: { cli: CLI_VERSION } };

  if (command === "tasks") {
    switch (sub) {
      case "list":
        return taskList(flags);
      case "get": {
        const suffix = flags["issue-url"] === true ? "?include=issueUrl" : "";
        return api("GET", `/tasks/${encodeURIComponent(id())}${suffix}`);
      }
      case "add":
        return taskAdd(flags);
      case "edit":
        return taskEdit(flags, id());
      case "rm": {
        if (flags.yes !== true) {
          throw new UsageError("deleting is permanent; repeat with --yes");
        }
        return api("DELETE", `/tasks/${encodeURIComponent(id())}`);
      }
      case "start":
        return api("POST", `/tasks/${encodeURIComponent(id())}/start`);
      case "stop":
        return api("POST", "/task-control/stop");
      case "archive":
        return api("POST", `/tasks/${encodeURIComponent(id())}/archive`);
      case "restore":
        return api("POST", `/tasks/${encodeURIComponent(id())}/restore`);
      case "time":
        return taskTime(flags, id());
      default:
        throw new UsageError(`unknown tasks command "${sub ?? ""}"; see spt --help`);
    }
  }

  if (command === "notes") {
    switch (sub) {
      case "list": {
        const project = nonEmpty(text(flags, "project", "p"), "--project");
        if (project) {
          return api("GET", `/notes?projectId=${encodeURIComponent(project)}`);
        }
        return api("GET", "/notes");
      }
      case "get":
        return api("GET", `/notes/${encodeURIComponent(id())}`);
      case "add": {
        const body: Record<string, unknown> = {
          content: nonEmpty(required(text(flags, "content"), "--content"), "--content"),
        };
        const project = nonEmpty(text(flags, "project", "p"), "--project");
        if (project) body.projectId = project;
        if (flags.pinned === true) body.isPinnedToToday = true;
        if (!project && flags.pinned !== true) {
          throw new UsageError("a note needs --project or --pinned");
        }
        return api("POST", "/notes", body);
      }
      case "edit":
        return noteEdit(flags, id());
      case "rm": {
        if (flags.yes !== true) {
          throw new UsageError("deleting is permanent; repeat with --yes");
        }
        return api("DELETE", `/notes/${encodeURIComponent(id())}`);
      }
      default:
        throw new UsageError(`unknown notes command "${sub ?? ""}"; see spt --help`);
    }
  }

  const method = command.toUpperCase();
  if (method === "DELETE" && flags.yes !== true) {
    throw new UsageError("deleting is permanent; repeat with --yes");
  }
  return api(method, required(args[0], "path, for example /tasks"), jsonBody(flags));
}

function fail(error: unknown): number {
  if (error instanceof UsageError) {
    process.stderr.write(
      `${JSON.stringify({ error: error.message, code: "USAGE" }, null, 2)}\n`,
    );
    return EXIT_USAGE;
  }
  if (error instanceof ApiError) {
    process.stderr.write(
      `${JSON.stringify({ error: error.message, code: error.code, status: error.status }, null, 2)}\n`,
    );
    return ["OFFLINE", "TIMEOUT", "RESPONSE_ABORTED", "APP_NOT_READY"].includes(
      error.code,
    )
      ? EXIT_OFFLINE
      : EXIT_API;
  }
  process.stderr.write(
    `${JSON.stringify({ error: (error as Error).message, code: "INTERNAL" }, null, 2)}\n`,
  );
  return EXIT_API;
}

process.stdout.on("error", (error: NodeJS.ErrnoException) => {
  if (error.code === "EPIPE") process.exit(EXIT_OK);
  throw error;
});

try {
  const reply = await run(process.argv.slice(2));
  process.stdout.write(
    reply.data === HELP
      ? `${HELP}\n`
      : `${JSON.stringify(reply.data, null, 2)}\n`,
  );
  // Set the code and let the event loop drain: process.exit() can cut a piped
  // stdout buffer short when the reply is large.
  process.exitCode = EXIT_OK;
} catch (error) {
  process.exitCode = fail(error);
}
