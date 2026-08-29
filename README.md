# Herdr OpenCode Sandbox

Reusable Apple Container tooling for running OpenCode against a Git repository
from a Herdr-managed pane. The project repository is mounted into a disposable
Linux arm64 container; the sandbox scripts and image definition live here and
do not need to be copied into every project.

## Prerequisites

- Apple Silicon Mac
- macOS with Apple's `container` command installed
- Herdr installed and running
- Git
- A checked-out copy of this repository

Install Apple's container tool using the [official installation
instructions](https://github.com/apple/container/blob/main/README.md), and
install Herdr using its [official documentation](https://herdr.dev/docs/).

Start the Apple container services if necessary:

```bash
container system start --disable-kernel-install
```

If the arm64 kernel is missing, install Apple's recommended kernel:

```bash
container system kernel set --recommended --arch arm64 --force
container system start --disable-kernel-install
```

## Install Once

After cloning this repository:

```bash
git clone <this-repository-url> ~/Dev/herdr-opencode
cd ~/Dev/herdr-opencode
./scripts/install
```

This creates `~/.local/bin/herdr-opencode` as a symlink to this checkout. It
does not copy files into target repositories. Add `~/.local/bin` to `PATH` if
the installer says it is not already there.

The checkout can live anywhere on the host. Keep it available because the
launcher uses its Dockerfile and entrypoint when building the image.

## Build And Check

Build the reusable image once:

```bash
herdr-opencode doctor
herdr-opencode build
```

The image is tagged `herdr-opencode:arm64` and the OpenCode base image is
pinned by OCI digest. Rebuild after updating this repository or when changing
the pinned image.

## Run From Any Repository

Open a Herdr pane, change to the target Git repository, and run:

```bash
herdr-opencode run
```

Pass normal OpenCode arguments after `run`:

```bash
herdr-opencode run --continue
```

The launcher discovers the target repository from the current directory and:

- Mounts only that repository at `/workspace/project`.
- Starts OpenCode with an interactive TTY in that directory.
- Persists OpenCode sessions and credentials in a stable per-repository named
  volume by default.
- Does not pass host API keys by default; use `HERDR_OPENCODE_FORWARD_API_KEYS=1`
  when that is explicitly desired.
- Sets the host-side `HERDR_AGENT=opencode` hint for Herdr detection.
- Checks Apple container services and outbound GitHub connectivity before launch.

The target repository needs no `container/`, `scripts/`, or configuration files
from this project.

## Configuration

Use environment variables for local machine or workload differences:

```bash
HERDR_OPENCODE_CPUS=6 \
HERDR_OPENCODE_MEMORY=8G \
herdr-opencode run
```

Supported variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `HERDR_OPENCODE_IMAGE` | `herdr-opencode:arm64` | Image tag to run/build |
| `HERDR_OPENCODE_STATE_VOLUME` | Per-repository volume | Named OpenCode state volume |
| `HERDR_OPENCODE_CPUS` | `4` | Container CPU limit |
| `HERDR_OPENCODE_MEMORY` | `6G` | Container memory limit |
| `HERDR_OPENCODE_PLATFORM` | `linux/arm64` | Container platform |
| `HERDR_OPENCODE_FORWARD_API_KEYS` | unset | Opt in to forwarding common provider API keys |
| `HERDR_OPENCODE_SKIP_NETWORK` | unset | Set to `1` to skip the preflight network check |

Use an explicit state volume when sharing sessions or credentials is intentional:

```bash
HERDR_OPENCODE_STATE_VOLUME=herdr-opencode-client-a herdr-opencode run
```

The default state volume is derived from the absolute repository path, so moving
a checkout creates a new state volume. This avoids cross-project credential and
session sharing; use the explicit override only when that tradeoff is
intentional.

## Authentication

Provider API keys are not forwarded by default. Set
`HERDR_OPENCODE_FORWARD_API_KEYS=1` only for a trusted target repository when
the keys already exist in the Herdr pane environment. Other providers can be
authenticated inside OpenCode; credentials are stored in the state volume
rather than the target repository.

For GitHub Copilot, use OpenCode's `/connect` flow and complete the device
authorization in the host browser. Do not commit credentials or device codes.

## Lifecycle And Cleanup

Exiting OpenCode removes the disposable container but retains the state volume.
List state volumes, then delete one only when its credentials and saved sessions
are no longer needed:

```bash
container volume list
container volume delete <repository-state-volume>
```

Do not run `container volume prune` casually.

## Security Model

The container can read and write the mounted target repository. It does not
mount the host home directory, SSH agent, or Herdr control socket. Do not add
those mounts unless the workload and trust model require them. Use a separate
state volume for untrusted or unrelated projects.

The current setup provides host-native Herdr with containerized OpenCode. The
host wrapper can identify the intended OpenCode agent, but native OpenCode
session reporting across the Apple VM boundary is intentionally not enabled.
See [`docs/setup/herdr-opencode-apple-container.md`](docs/setup/herdr-opencode-apple-container.md)
for the detailed behavior and troubleshooting notes.

## Updating

Because the installed command is a symlink, pull updates into this checkout and
run the build command again when the image definition changes:

```bash
git pull
herdr-opencode build
```

## Compatibility Scripts

The original repository-local commands remain as thin wrappers:

```bash
./scripts/setup-opencode-container
./scripts/run-opencode-container --continue
```

New installations should use `herdr-opencode build` and
`herdr-opencode run` so the same commands work from any repository.
