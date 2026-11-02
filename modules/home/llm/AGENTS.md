# Agents

## General

- delegate work to agents to avoid overwhelming your context
- always use skills that are appropriate for the task, they will help to guide you to a better result
- use `/council`, `/oracle` and a verifier agent whenever we are practically done with the task, need/want more assertion that we really are on the right path or simply be more thorough

## Plan

- use `/ask-matt` skill, if the task at hand is more complicated than simple change
- always try to understand the problem properly and in depth, use `/research` skill
- always gather knowledge/docs and test, to get proper understanding on the matter
- for the 2 points above, use `/grill-with-docs` skill

## Research

- use `/explorer` and `/librarien` agents

## Code/config

- seek, evaluate and follow dry, kiss, yagni and best coding principles
- have no need for backwards compatibility, unless the user asks for it
- focus on performance and memory usage
- code should be minimal and easy to read
- code should try to fit in reusable modules, that handle all the logic, so that code/logic is never duplicated or misused
- verify everything is unified and working together
- always fully refractor and cleanup
- always use one single source of truth
- always try to have broad, deterministic and intelligent tests
- use table driven tests if possible, to minimize code and do to not repeat
- acknowledge, analyze, evaluate and act all findings, reproduce if possible, no assumptions allowed. even for low impact ones
- for editing, use `/fixer agent`

## Prose/docs/code comments

- use `/writing-for-agents` skill
- they should always be concise, easy to understand and show examples if applicable
- never use em dashes or other standalone dashes
- never word wrap prose (eg. markdown, etc.)
- code comments should not be needed, unless the code does non-obvious things, and even then, they should be concise and describe/list the logic effecting it, callers, data or the underlying phenomenon

## MCP tools

Use tools:

- `godoc`: for Go/Golang docs
- `nixos`: Nix/NixOS docs
- `context7`: any other docs than the above 2
- `exa` or `webset`: get search results or query web
- `gh_grep`: search real code examples across public GitHub repositories
- `anymd`: read and convert PDF, Office, EPUB, HTML/URLs, images (OCR), and audio/video to Markdown
- `codebase-memory-mcp`: code knowledge graph, prefer search_graph/trace_path/get_architecture over grep for structural questions and always use it in codebases as it helps finding connections
- `docs-mcp-server`: whenever user tells you to use it

## CLI tools

- `browser-harness-js`: browser automation via CDP (use the `/cdp` skill). The CLI drives the user's Chrome; the REPL server auto-starts on first call and keeps one persistent session. When task is not one-shot, always reuse session to minimize startup time and churn. The user/or you start Chrome with `chromium --user-data-dir=/tmp/chrome-cdp --remote-debugging-port=9222`. Note that it will not be auto-detected, you will have to use the port directly.
- `gh`: GitHub CLI: Use `gh` subcommands or `gh api` for GitHub state instead of unauthenticated HTTP calls. For ssh protocol, use host based on `~/.ssh/config.d/keepass.conf`, not the default github.com, as we use ssh agent auth based on SSH host.
- `cf`: Cloudflare CLI: Profiles are bound per directory under `~/Projects` (work vs personal), so run `cf` from the project root and let the binding select the profile; pass `--profile <name>` only to override it for one command. Discover the command surface with `cf tools` and `cf <group> --help`, and search Cloudflare docs with `cf docs search "<query>"`. `cf` is beta and some Wrangler commands are not implemented yet.
- read-only for git, gh, cf, and netbird-manage: run only read operations. Write operations have to be specifically confirmed and authorized by user. Never run write actions by yourself. You may however stage files that need to be for you to test changes, eg. for Nix.

## Projects

- our projects should be using devenv and go-task
- project commands should be invoked with `task <subcommand> ...` from devenv, as all the tools, CLIs, and programming languages the project uses should be defined in it
