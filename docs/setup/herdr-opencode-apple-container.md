# Herdr + OpenCode in Apple Container

This setup keeps Herdr native on macOS and runs OpenCode plus the project
toolchain inside an Apple Linux container. The reusable launcher and image
definition live in this repository; target repositories do not need copies of
those files. Herdr identifies the host-side container command as OpenCode
through `HERDR_AGENT=opencode` and uses its screen manifest for lifecycle
detection.

This is a conservative variant of Option B. It deliberately does not bridge
Herdr's control socket into the container. OpenCode remains visible and
interactive, but native OpenCode session restore and plugin-authored lifecycle
reports are not available across this VM boundary.

## Prerequisites

- Apple Silicon Mac. This procedure targets the arm64 architecture.
- macOS and Apple `container` installed.
- Herdr installed and running on the host.
- This repository checked out locally and installed with `./scripts/install`.
- API credentials available as environment variables, or login performed
  inside the persistent OpenCode volume.

Check the starting state:

```bash
uname -m
herdr --version
herdr status server
container --version
container system status
```

The Herdr server must report `status: running`. If Apple container services are
not running, start them:

```bash
container system start --disable-kernel-install
```

If the command reports that the default arm64 kernel is missing, install the
recommended kernel. `--force` is safe when a partially installed copy already
exists:

```bash
container system kernel set --recommended --arch arm64 --force
container system start --disable-kernel-install
```

## 1. Check OpenCode detection support

Herdr already has an OpenCode screen manifest. Do not install the Herdr
OpenCode plugin into the container: the plugin currently interferes with the
OpenCode TUI when run through this Apple container TTY path.

```bash
mkdir -p "$HOME/.config/opencode"
herdr integration status
```

The host integration may be installed for host-native OpenCode sessions, but it
is intentionally not copied into this container image.

## 2. Configure host service DNS

No host-service DNS entry is required for this variant. The container only
needs its normal outbound network for provider APIs and package registries.

## 3. Build the arm64 development image

The setup script builds a pinned OpenCode base image. The published OpenCode
image already contains the OpenCode runtime and ripgrep. The derived image also
includes a general build/dev baseline: Bash, CA certificates, curl, Git,
OpenSSH client, jq, less, file, patch, diffutils, findutils, tar, gzip, xz,
unzip, and OpenSSL. It intentionally excludes language-specific runtimes and
all Herdr OpenCode plugins:

From this repository, run `./scripts/install` once. Then build the image from
any Git repository:

```bash
herdr-opencode doctor
herdr-opencode build
```

The image is tagged `herdr-opencode:arm64`. The OpenCode base image is pinned
by OCI digest in `container/opencode/Dockerfile`; update that digest deliberately
when upgrading OpenCode.

Inspect the result:

```bash
container image inspect herdr-opencode:arm64
```

## 4. Launch from a Herdr pane

Open a Herdr pane whose working directory is the target repository, then run:

```bash
herdr-opencode run
```

The launcher requires `HERDR_ENV=1`, `HERDR_PANE_ID`, and an interactive
stdin/stdout TTY, so it cannot accidentally attach an ordinary
non-interactive process to a Herdr pane.

The launcher does the following:

1. Sets `HERDR_AGENT=opencode` for host-side Herdr process detection.
2. Mounts only the target repository at `/workspace/project`.
3. Persists OpenCode data in a stable per-repository named volume by default.
4. Starts OpenCode in the mounted repository with a TTY.
5. Forwards the host terminal capability variables so the OpenCode TUI can
   negotiate screen size, colors, and terminal features.

The image entrypoint also defaults `TERM` to `xterm-256color` and `LANG` to
`C.UTF-8` if a caller does not provide them.

The launcher sets `HERDR_AGENT=opencode` on the host-side foreground wrapper.
It intentionally does not mount the host home directory, forward the host SSH
agent, publish an OpenCode HTTP port, or expose the Herdr control socket. The
container uses `--rm`: the container is disposable, while the named OpenCode
state volume persists. The default state volume is derived from the absolute
target repository path. Set `HERDR_OPENCODE_STATE_VOLUME` explicitly when
sharing state across repositories is intentional.

Before starting OpenCode, the launcher checks that a fresh Apple container can
reach `https://api.github.com`. This catches a stale Apple NAT session before
provider authentication is attempted.

To pass a one-off OpenCode argument:

```bash
herdr-opencode run --continue
```

The wrapper does not forward API keys by default. For a trusted target
repository, set `HERDR_OPENCODE_FORWARD_API_KEYS=1` to forward the common
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and `GOOGLE_API_KEY` variables when they
are present in the Herdr pane environment. For other providers, use `opencode
auth login` inside the container; credentials will be stored in the
per-repository state volume rather than in the target repository.

### GitHub Copilot

GitHub Copilot authentication uses GitHub's device flow. The browser can stay
on the macOS host; it does not need to be opened inside the container.

1. In the running OpenCode TUI, enter `/connect`.
2. Select **GitHub Copilot**.
3. On the host, open the displayed URL:
   `https://github.com/login/device`.
4. Enter the one-time code shown by OpenCode.
5. Sign in to the GitHub account with the Copilot subscription and approve the
   request. If GitHub asks for organization SSO authorization, complete that
   step as well.
6. Return to OpenCode and wait for the authorization to complete.
7. Run `/models` and select a Copilot model.

OpenCode stores the resulting credential at
`/root/.local/share/opencode/auth.json` inside the container. That directory is
the persistent per-repository state volume, so the login survives container
recreation. It is not written to the host's OpenCode configuration.

To authenticate without the TUI, use the container's OpenCode CLI:

```bash
container run --rm --platform linux/arm64 --interactive --tty \
  --volume <repository-state-volume>:/root/.local/share/opencode \
  herdr-opencode:arm64 auth login --provider github-copilot
```

Use the TUI method first because it makes the device code and approval state
visible. Never paste the device code or resulting credential into the project
files or into a chat transcript.

## 5. Verify Herdr integration

With OpenCode running in the container, use another host terminal or Herdr pane:

```bash
herdr integration status
herdr agent list
```

Herdr should show the pane as an `opencode` agent based on the wrapper hint and
the OpenCode screen manifest. Lifecycle state comes from the visible TUI, not
from the OpenCode plugin. A native OpenCode session ID is not reported by this
variant, so do not rely on native OpenCode session restore after a Herdr server
restart.

If the agent is not reported, check the container-side inputs:

```bash
container exec herdr-opencode-<pane-id> env | grep '^HERDR_'
```

The container ID uses the pane ID with `:` replaced by `-`. The host-side
foreground process must have `HERDR_AGENT=opencode`. The container does not
need any `HERDR_*` variables for this fallback mode.

```text
HERDR_AGENT=opencode
```

## 6. Lifecycle and cleanup

Exit OpenCode or press `Ctrl-C` to stop the container. Because the launcher
uses `--rm`, Apple removes the container automatically. The named state volume
remains available. To start a new session with the same state, rerun the
launcher from a Herdr pane:

```bash
herdr-opencode run --continue
```

The host wrapper does not create a socket proxy. Rerunning the launcher creates
a fresh container while the named OpenCode state volume remains available.

List state volumes and delete one only when its OpenCode sessions and
credentials are no longer needed:

```bash
container volume list
container volume delete <repository-state-volume>
```

Do not run `container volume prune` casually; it permanently deletes unused
volume contents.

## Security model

- The container has no access to the Herdr socket or Herdr control plane.
- The repository bind mount is read-write, so use this setup only with trusted
  code and trusted OpenCode prompts.
- Do not add `--ssh` unless private Git access is required; it forwards the
  host SSH authentication socket.
- Do not mount `$HOME`, `~/.ssh`, `~/.config/herdr`, or unrelated credential
  directories into the container.
- Keep project-specific OpenCode permissions explicit. For untrusted work,
  prefer a container-local Herdr server.

## Troubleshooting

### `container system status` fails

Start the service and configure the arm64 kernel as shown in the prerequisites.
If macOS asks for approval during the first setup, complete that approval and
rerun the command.

### OpenCode starts but Herdr shows no state

Confirm that the launcher was run from a Herdr pane rather than a normal host
terminal and that the host-side wrapper exports `HERDR_AGENT=opencode`. Use
`herdr agent explain <pane-id>` to see which screen-manifest rule matched.

If Herdr still does not classify the pane, first run plain OpenCode on the host
in a test pane to confirm the installed Herdr OpenCode manifest works with the
current Herdr version.

### `/connect` provider selection does nothing

Test the Apple container network from the host:

```bash
container run --rm --platform linux/arm64 --entrypoint /bin/sh herdr-opencode:arm64 \
  -c 'curl -fS -o /dev/null --max-time 10 https://api.github.com'
```

If it times out while the same URL works on the Mac, restart the Apple
container services. This stops the current OpenCode container, so rerun the
launcher afterward:

```bash
container system stop
container system start --disable-kernel-install
herdr-opencode run
```

Once the network check succeeds, `/connect` -> **GitHub Copilot** -> **GitHub.com
(public)** should display GitHub's device URL and one-time code. Complete that
flow in the Mac browser at `https://github.com/login/device`. Enterprise uses
the same device-flow pattern but the Enterprise host selected in OpenCode.

### File writes fail or ownership is inconvenient

The initial image runs OpenCode as root so it works with ordinary host bind
mount permissions. If this becomes a concern, add a project-specific non-root
user and validate UID/GID mapping for the repository before tightening the
image.

## Primary references

- [Herdr agents and VM wrappers](https://herdr.dev/docs/agents/)
- [Herdr integrations](https://herdr.dev/docs/integrations/)
- [Herdr socket API](https://herdr.dev/docs/socket-api/)
- [OpenCode CLI](https://opencode.ai/docs/cli/)
- [OpenCode configuration](https://opencode.ai/docs/config/)
- [OpenCode permissions](https://opencode.ai/docs/permissions/)
- [Apple container command reference](https://github.com/apple/container/blob/main/docs/command-reference.md)
- [Apple host integration](https://github.com/apple/container/blob/main/docs/host-integration.md)
- [Apple mounts and volumes](https://github.com/apple/container/blob/main/docs/volumes.md)
- [Apple networking](https://github.com/apple/container/blob/main/docs/networking.md)
