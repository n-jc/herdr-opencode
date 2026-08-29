# Security Notes

## Trust Model

This tool runs OpenCode with write access to the target repository. Treat the
target repository and its prompts as trusted when using the default workflow.
The Apple container VM does not protect data deliberately exposed through the
repository mount, named state volume, forwarded environment variables, or any
future socket or SSH mounts.

The Herdr control socket and host SSH agent are not mounted by default. Do not
add either for untrusted workloads.

## Credentials

API keys are not forwarded by default. `HERDR_OPENCODE_FORWARD_API_KEYS=1` is
an explicit opt-in for trusted repositories only. OpenCode login credentials are
stored in a per-repository named volume by default. Use
`HERDR_OPENCODE_STATE_VOLUME` only when sharing that state is intentional.

Never put credentials, device codes, private keys, or host configuration files
in this repository or in the target repository.

## Before Publishing

Before pushing changes, check both the worktree and history:

```bash
git status --short --ignored
git grep -n -I -E 'BEGIN .*PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_|sk-' $(git rev-list --all)
git log --all --format='%h %an <%ae> %s'
```

Git author and committer metadata is public when the repository is pushed. Use
a privacy-preserving Git identity before creating commits if that is required.
