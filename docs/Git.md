# Git

Overwriting git history for usernames, passwords, and commit signatures:

```sh
git filter-repo --name-callback "return b'<username>'" --email-callback "return b'<email>'" --force

export FILTER_BRANCH_SQUELCH_WARNING=1
git filter-branch -f --commit-filter 'git commit-tree -S "$@"' HEAD

# After that add the origin and force push
git remote add origin git@github.com:<username>/<repo>.git
git push --set-upstream origin main --force
```
