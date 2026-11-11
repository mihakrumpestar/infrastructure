# Agents

## General

- delegate work to agents to avoid overwhelming your context
- batch independent tool calls in one turn, and put related shell steps in one command; waiting call by call wastes wall clock
- agents are reached with `subagent` or `@name` (`@explorer`, `@oracle`, `@designer`, `@fixer`, `@council`), not slash commands
- subagents can load skills, so name the skill and let them read the method; council seats (`councillor-*`) cannot
- use skills appropriate to the task; every skill is model-invocable, so load them when the request matches and follow them literally when the user starts one
- use `/council`, `/oracle` and a verifier agent whenever we are practically done or want more assertion that we are on the right path
- oracle is also worth it mid-task when a change touches multiple files, when a claim enters a deliverable, or after a failed fix
- if topics diverge, start a new session with a short carried summary

## Plan

- restate the request as the checklist a reviewer would accept, and answer the sibling questions in the same turn or say why not
- when a reference file or "like before" is named, read it first and copy its layout, naming and task names, then diff
- use `/research` and parallel `explorer` lanes, then state the mechanism in two lines before writing code
- when the user states a fact or preference, record it and re-check it before every later edit to the same deliverable

## Scope

- implement the smallest change that satisfies the literal request; extras go into "proposed, not built"
- never add linting, validation, wrappers, scripts, docs or CI gates that were not asked for; when the user says minimal, delete instead of add
- decide reversible things yourself and note the assumption; ask only when the answer is irreversible or unknowable from here

## Verify

- verify the effect, not the mechanism: read the produced file, load the deployed page, measure the pixels
- never write Done, Fixed, Deployed or Verified without the command and its output, or the artifact you inspected; name what stayed unverified
- reproduce the user's exact input and symptom before fixing and after
- lanes run only the check for their own scope; `task ci` once at the end

## Code/config

- dry, kiss, yagni; no backwards compatibility unless asked
- one source of truth, no duplicated logic, no second path for the same job
- performance and memory matter on hot paths and boot or per-request code
- delete what the change replaced; no dead code
- comments only for the invariant, caller contract or phenomenon, one or two lines
- table driven tests where cases are data, deterministic, covering the contract
- act on every finding, including low impact ones; reproduce instead of assuming
- for editing, use `/fixer`

## Prose/docs/code comments

- concise and concrete, with an example where it helps
- write for the named audience, give every number its denominator
- delete what the audience cannot act on, then re-read once as a non-specialist
- no em dashes or standalone dashes
- no word wrapping
- use `writing-for-agents` for docs and specs, `archify` for diagrams

## MCP tools

- `godoc` Go, `nixos` Nix/NixOS, `context7` other libraries
- `keenable` search, `gh_grep` real code, `tweetapi` X/Twitter
- `anymd` PDF, Office, EPUB, HTML, images
- `codebase-memory-mcp` for structure before grep
- `docs-mcp-server` disabled by default, enable when asked

## CLI tools

- `browser-harness-js` for CDP (`/cdp`), Chrome on `--user-data-dir=/tmp/chrome-cdp --remote-debugging-port=9222`, reuse one session
- `gh` for GitHub state, ssh hosts from `~/.ssh/config.d/keepass.conf`
- `cf` from the project root; `cf tools`, `cf <group> --help`, `cf docs search "<query>"`
- read-only for git, gh, cf and netbird-manage: no commit, push, tag, reset, checkout, rm or mv without confirmation; staging only to test a Nix build
- never write to a credential store: KeePassXC, `secret-tool store`, `secretspec set` or `delete`, SOPS, a live `.env`
- never copy classified or personal data into a deliverable; report it and let the user decide
- no destructive or broad shell operation without listing and quoting the target set

## Files and shell

- read with `read`, search with `grep`, discover with `glob`; never `cat`, `head`, `tail`, `sed -n` for code
- project commands: `devenv shell -- task <name>`, or `./.devenv/profile/bin/task <name>`; bare `task` is not on PATH
- helper binaries are often absent: `nix shell nixpkgs#file nixpkgs#binutils -c ...`, not `nix run`
- keep the project root to tracked entrypoints; scratch goes in a named subdirectory and is cleaned before reporting

## Projects

- every repo uses devenv and go-task; languages, CLIs and checks live in `devenv.nix`, CI is `task ci`
