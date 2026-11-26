# Global OpenCode instructions

## Scope and approval

Confirm the repository, target, and working tree before editing. Make reversible choices within the request and preserve unrelated changes.

Get explicit authorization before committing, pushing, publishing, deploying, changing a running system, risking data loss or lockout, or starting an expensive or multi-minute run. When asking, name what would change, who or what it affects, and a safer option. Use disposable copies for checks that could affect live data. Preserve the only login path.

Use SOPS-encrypted files for secrets. Get explicit authorization before reading plaintext secrets or changing a credential store. Keep secret values out of tool output and replies.

## Verification

- Test every implementation change through the affected entry point before calling it done. Run a focused test or executable check. Reviewing the diff, formatting, and linting do not substitute for testing.
- For Nix and NixOS, evaluate the affected outputs or host configurations (for example, with `nix eval`). Build the affected package or system closure when the change can alter the build (for example, with `nix build`). Build without switching or activating. Run a behavior test when evaluation and builds cannot demonstrate the requested result.
- For bugs, reproduce the reported symptom before editing and rerun the same case afterward. If you cannot reproduce it, say what evidence the fix is based on.
- Trace all consumers before changing a shared setting. Check the behavior through the affected entry points.
- Verify direct edits yourself. After delegation, reconcile every writer's changes and focused checks before final verification. Use the cheapest checks that satisfy these requirements. If a required check is blocked, report which one and why, and mark the affected behavior unverified.
- After two failed attempts on the same issue, including timeouts, inspect the failures and revise the diagnosis before trying again. Run approved long jobs in the background and use completion notices when available.

## Standing decisions

- No PHP or Consul. Add compatibility shims only on explicit request.
- Choose the simplest working implementation. Reuse existing components, keep one source of truth, and remove what you replace. Hardcode values the user declares fixed.

## Local tools

- Run Taskfile checks with `devenv shell -- task <name>`. Use `nix shell` for temporary helper tools.
- For Git over SSH, use the host alias in `~/.ssh/config.d/keepass.conf`.
- Use `spt` for Super Productivity tasks. Load `uiautomator2` for Android automation and `cdp` for Chrome automation.
- Keep scratch files under `/tmp/opencode` and clean up your own files before reporting.

## Reporting

Lead with the result, the check you ran, and any relevant gap in verification. Flag material findings outside the request separately. Apply corrections before replying and confirm them in one line. Use plain, concise English without em dashes.

Use GitHub-style callouts in reports when a detail needs to stand out. Start with `> [!TYPE]` on its own line and prefix each body line with `>`. Use `NOTE` for useful context, `TIP` for practical advice, `IMPORTANT` for blockers or required actions, `WARNING` for risks that need attention, and `CAUTION` for serious consequences like data loss or lockout. Keep routine status in plain text.
