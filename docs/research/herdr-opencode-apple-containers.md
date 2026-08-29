# Herdr, OpenCode, and Apple Containers

**Research date:** 2026-08-24
**Scope:** Feasibility and setup options for Herdr-managed OpenCode sessions running in Linux development environments provided by Apple's `container` project on Apple silicon.

## Executive Summary

The integration is feasible, but the process boundary matters:

- **Best compatibility:** run Herdr and OpenCode in the same Apple Linux container. Herdr then sees OpenCode as an ordinary local process, and the official OpenCode integration can use Herdr's local Unix socket directly.
- **Best host UX with a strong boundary:** run Herdr on macOS and launch an interactive Apple container from a Herdr pane, but explicitly relay Herdr's Unix socket into the container. Also pass Herdr's pane identity into the container. Without this relay, Herdr sees the host-side `container` client rather than the OpenCode process inside the VM, so native status and session reporting do not work.
- **Best persistent Linux environment:** run Herdr inside an Apple `container machine`. This gives a persistent Linux environment and host home-directory integration, but it is a different topology from host Herdr plus a disposable development container. Running another VM/container runtime inside that machine requires nested virtualization, an M3-or-newer Mac, and a suitable Linux kernel.

These conclusions combine verified facts with recommendations. Claims marked **Verified** are directly stated or implemented by the cited primary source. Claims marked **Recommendation** or **Inference** are design conclusions from those facts.

## Terminology and Boundary

**Verified:** Herdr is a terminal workspace manager. Its server owns real terminal processes, while clients attach and detach from the server. A pane is a real terminal, and an agent is a process Herdr recognizes in that pane. [Herdr Concepts](https://herdr.dev/docs/concepts/) (accessed 2026-08-24).

**Verified:** Herdr supports OpenCode as a recognized agent. Its official OpenCode integration reports lifecycle state and native session identity, and Herdr can resume a reported OpenCode session with `opencode --session <id>`. [Herdr Integrations](https://herdr.dev/docs/integrations/) and [Herdr Session State](https://herdr.dev/docs/session-state/) (accessed 2026-08-24).

**Verified:** Herdr's VM and sandbox guidance says a host-visible wrapper can hide the real agent process. `HERDR_AGENT=<agent>` can identify the intended agent for a host-visible wrapper, but Herdr cannot see that hint if it is set only inside a VM or container. [Herdr Agents, "VMs and sandbox wrappers"](https://herdr.dev/docs/agents/#vms-and-sandbox-wrappers) (accessed 2026-08-24).

**Inference:** With host Herdr and OpenCode inside an Apple container, the host pane's foreground process is normally the host-side `container` CLI. The OpenCode process is inside the container's Linux VM and is not automatically visible to Herdr's host process detection. Therefore, merely typing `container run ... opencode` in a Herdr pane is insufficient for rich OpenCode detection.

## Feasibility

### Apple container runtime

**Verified:** Apple's `container` tool creates and runs Linux containers as lightweight VMs on Apple silicon, consumes and produces OCI-compatible images, and requires Apple silicon. The current project documentation says it is supported on macOS 26. [Apple `container` README](https://github.com/apple/container/blob/main/README.md) (accessed 2026-08-24).

**Verified:** The underlying Containerization package runs each Linux container in its own lightweight VM. It exposes APIs for OCI images, Linux processes, mounts, networking, and Unix-socket relays. [Apple Containerization README](https://github.com/apple/containerization/blob/main/README.md) (accessed 2026-08-24).

**Verified:** Apple's Virtualization framework provides the VM mechanisms, including VIRTIO network, storage, shared-directory, and socket devices. [Apple Virtualization framework documentation](https://developer.apple.com/documentation/virtualization.md) (accessed 2026-08-24).

**Recommendation:** Treat the Apple container VM as a meaningful security boundary, not as a transparent process namespace. Treat every bind mount and socket relay as an intentional exception to that boundary.

### OpenCode in Linux

**Verified:** OpenCode provides a Linux container image build based on Alpine. Its Dockerfile selects an architecture-specific Linux musl binary, including `opencode-linux-arm64-musl`, and uses `opencode` as the entrypoint. [OpenCode Dockerfile](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/Dockerfile) (accessed 2026-08-24).

**Verified:** Apple's `container` CLI defaults to the host architecture, which is `arm64` on the target Apple-silicon setup, and supports explicit `--platform`, `--arch`, and `--os` selection. [Apple `container` command reference](https://github.com/apple/container/blob/main/docs/command-reference.md) (accessed 2026-08-24).

**Recommendation:** Use an `arm64`/`linux` OpenCode image on Apple silicon. Use an explicit `linux/arm64` build or image tag when reproducibility matters. Use Rosetta or an `amd64` image only for a concrete compatibility requirement; it adds translation and should not be the default.

### Herdr integration mechanics

**Verified:** Herdr's OpenCode plugin is installed at `~/.config/opencode/plugins/herdr-agent-state.js`. The plugin activates only when `HERDR_ENV=1`, `HERDR_SOCKET_PATH`, and `HERDR_PANE_ID` are present. It uses Node's Unix socket client to send `pane.report_agent` and `pane.report_agent_session` requests to Herdr. [Herdr OpenCode integration source](https://github.com/herdrdev/herdr/blob/master/src/integration/assets/opencode/herdr-agent-state.js) (accessed 2026-08-24).

**Verified:** Herdr's terminal integration environment includes `HERDR_ENV`, `HERDR_PANE_ID`, `HERDR_TAB_ID`, `HERDR_WORKSPACE_ID`, `HERDR_SOCKET_PATH`, and `HERDR_BIN_PATH` for managed pane processes. [Herdr Integrations](https://herdr.dev/docs/integrations/) and [Herdr Socket API](https://herdr.dev/docs/socket-api/) (accessed 2026-08-24).

**Verified:** Herdr's socket API is newline-delimited JSON over a Unix domain socket on Unix systems. It supports pane and agent state reporting, session identity reporting, input, reads, waits, and event subscriptions. [Herdr Socket API](https://herdr.dev/docs/socket-api/) (accessed 2026-08-24).

**Verified:** OpenCode loads JavaScript or TypeScript plugins from `.opencode/plugins/` and `~/.config/opencode/plugins/` automatically. Its plugin API supplies lifecycle/event hooks, and plugins can use Node/Bun networking and shell facilities. [OpenCode Plugins](https://opencode.ai/docs/plugins/) (accessed 2026-08-24).

**Inference:** The official Herdr plugin can work across the Apple VM boundary if the container has the plugin file, the required environment variables, and a working socket path that reaches the host Herdr socket. This is an explicit transport integration, not automatic process detection.

## Architecture Options

### Option A: Herdr and OpenCode in one Apple container

**Shape**

```text
macOS terminal
    |
    +-- container run -it dev-image herdr
                              |
                              +-- Herdr server/client
                                      |
                                      +-- opencode
```

**Verified:** Herdr publishes Linux support and its remote-work documentation describes Herdr servers and agents running on Linux hosts. [Herdr README](https://github.com/herdrdev/herdr/blob/master/README.md) and [Herdr How to Work](https://herdr.dev/docs/how-to-work/) (accessed 2026-08-24).

**Verified:** Herdr can launch the `opencode` agent in a pane, and its normal server mode keeps pane processes running after the client detaches. [Herdr Agent Automation](https://herdr.dev/docs/agent-automation/) and [Herdr Persistence](https://herdr.dev/docs/persistence-remote/) (accessed 2026-08-24).

**Recommendation:** Build one Linux `arm64` development image containing Herdr, OpenCode, the project toolchain, and the Herdr OpenCode plugin. Start Herdr as the container's interactive command. Keep the project directory and any intended persistent agent data on named volumes or narrowly scoped bind mounts.

**Advantages**

- Herdr's process detection, PTYs, plugin socket, and OpenCode all share one Linux namespace.
- No cross-VM socket relay is required.
- Herdr's official OpenCode integration can report state and session identity normally.
- A container-local Herdr server does not expose the host Herdr control socket to the development workload.

**Costs and limits**

- The Herdr UI itself runs inside the Linux container rather than as a host-native process.
- Host desktop clipboard and host-local integrations are less direct; access is through the attached terminal or SSH-style workflows.
- A container stop destroys running Herdr/OpenCode processes. Herdr snapshot/native restore can reconstruct state only if the relevant Herdr state and OpenCode session data persist.
- Herdr's default server/client behavior is persistent within the container, not across a host reboot unless an outer supervisor recreates the container and the session data is persisted.

**Fit:** Best when correctness of agent detection and isolation matters more than a host-native Herdr UI.

### Option B: Host Herdr, OpenCode in an Apple container, relay Herdr's Unix socket

**Shape**

```text
macOS
  Herdr server
      |
      +-- host Unix socket
              |
              +-- Apple container Unix-socket relay
                      |
                      +-- /run/herdr.sock in Linux VM
                              |
                              +-- OpenCode + Herdr plugin
```

**Verified:** Apple's Containerization API defines `UnixSocketConfiguration` for relaying a host Unix socket into a guest/container. For direction `.into`, the host `source` is relayed to the guest `destination`. The relay uses a host Unix socket and a VM vsock connection. [Apple `UnixSocketConfiguration.swift`](https://github.com/apple/containerization/blob/main/Sources/Containerization/UnixSocketConfiguration.swift) and [Apple `UnixSocketRelay.swift`](https://github.com/apple/containerization/blob/main/Sources/Containerization/UnixSocketRelay.swift) (accessed 2026-08-24).

**Verified:** The `container run` and `container create` command references expose `--publish-socket <host_path:container_path>`. [Apple command reference, `container run`](https://github.com/apple/container/blob/main/docs/command-reference.md#container-run) (accessed 2026-08-24).

**Verified:** Apple bind mounts use `--volume` or `--mount`; mount types include host bind/virtiofs, named volume, and tmpfs, and bind mounts can be read-only. [Apple Mounts and Volumes](https://github.com/apple/container/blob/main/docs/volumes.md) (accessed 2026-08-24).

**Recommendation:** Use a small host wrapper command in the Herdr pane that:

1. Starts the container with the project directory mounted at a stable Linux path.
2. Publishes the current Herdr socket to a container-only path such as `/run/herdr.sock`.
3. Passes `HERDR_ENV=1`, the current `HERDR_PANE_ID`, and `HERDR_SOCKET_PATH=/run/herdr.sock` into the container.
4. Starts `opencode` in the mounted project directory.

The plugin must be installed in the container's OpenCode plugin directory, not only in the host user's plugin directory. Keep the Herdr socket relay scoped to the one container and do not publish it over TCP.

**Important limitation:** The official plugin reports to Herdr, but Herdr's host-side foreground-process detector still cannot inspect the OpenCode process inside the VM. The relay solves lifecycle/session reporting, not host process visibility. For agent-start automation, use the plugin's reports or drive the container's terminal as a pane process; do not assume host process detection will identify the nested `opencode` executable.

**Advantages**

- Host-native Herdr UI and host Herdr persistence remain available.
- The project and container toolchain are isolated in the Apple Linux VM.
- Official OpenCode lifecycle/session integration can be retained through the socket relay.

**Costs and limits**

- The socket relay grants the container workload access to Herdr's control plane. A compromised or malicious OpenCode workload could attempt to control the Herdr session according to the socket API's available operations.
- The host Herdr process tree still sees the wrapper/container client rather than the nested agent.
- The exact CLI relay behavior and permissions should be validated against the installed Apple `container` release; the command is documented, but the research sources do not document a Herdr-specific example.
- Recreating a stopped container requires an outer lifecycle command. Avoid `--rm` if the container filesystem or container identity must survive a stop; persist important state separately in a named volume or bind mount.

**Fit:** Best when host-native Herdr is required and the operator accepts an explicit control-socket trust boundary.

### Option C: Herdr inside a persistent Apple container machine

**Shape**

```text
macOS
  Apple container machine
      |
      +-- persistent Linux filesystem and home mount
              |
              +-- Herdr
                      |
                      +-- OpenCode
```

**Verified:** A container machine is an Apple-managed persistent Linux environment based on an OCI image. It runs the image's init system, automatically maps the host user's home directory by default, and can boot again when `container machine run` is used. [Apple Container Machine](https://github.com/apple/container/blob/main/docs/container-machine.md) (accessed 2026-08-24).

**Verified:** `container machine create` accepts CPU, memory, home-mount, custom-kernel, and optional nested-virtualization settings. [Apple `MachineCreate.swift`](https://github.com/apple/container/blob/main/Sources/ContainerCommands/Machine/MachineCreate.swift) (accessed 2026-08-24).

**Recommendation:** Use this option when the desired development environment is a long-lived Linux machine rather than a per-task disposable container. Install Herdr and OpenCode directly in the machine and let Herdr manage OpenCode as a same-machine process. Use the host home mount only when the trust model permits the Linux environment to access the host home directory; otherwise set `home-mount=none` or use a narrower project mount where supported.

**Advantages**

- Persistent Linux home, package caches, Herdr state, OpenCode state, and services.
- Same-namespace Herdr/OpenCode integration if both run directly in the machine.
- Container-machine lifecycle is simpler than rebuilding an application container for every session.

**Costs and limits**

- This is not the same as Herdr on macOS managing OpenCode in a separate disposable Apple container.
- The default home mount is broad and should be treated as a substantial host-data exposure.
- If the machine is stopped, live Herdr processes do not continue running; persistence is filesystem/session persistence, not process persistence.
- A second container runtime inside the machine is a nested-virtualization design, not a default feature.

**Fit:** Best for a persistent Linux workstation/server experience.

### Option D: Nested container runtime inside an Apple container machine

**Verified:** Apple documents nested virtualization for a container or container machine only on Apple Silicon M3 or newer with macOS 15 or newer and a Linux kernel with `CONFIG_KVM=y`. The default kernel does not support it. [Apple Runtime Configuration](https://github.com/apple/container/blob/main/docs/runtime-configuration.md#expose-virtualization-capabilities-to-a-container), [Apple Container Machine](https://github.com/apple/container/blob/main/docs/container-machine.md#nested-virtualization-and-custom-kernels), and [Apple Containerization README](https://github.com/apple/containerization/blob/main/README.md) (accessed 2026-08-24).

**Recommendation:** Do not choose this for the first implementation. It adds another VM/runtime/control-plane boundary without improving the Herdr/OpenCode integration compared with Option A. Choose it only if the development workload specifically requires a nested Docker/OCI/Kubernetes runtime and the hardware/kernel prerequisites are verified first.

## Filesystem and Workspace Mounting

### Project source

**Verified:** Apple supports host bind mounts through `--volume HOST:CONTAINER` or `--mount source=HOST,target=CONTAINER`; named volumes use an ext4 filesystem and are recommended when host sharing is not needed. [Apple Mounts and Volumes](https://github.com/apple/container/blob/main/docs/volumes.md) (accessed 2026-08-24).

**Recommendation:** Mount only the repository or an isolated worktree read-write, for example `/workspace/project`. Do not mount the entire host home directory into a disposable agent container. For multiple agents, prefer one Git worktree per Herdr workspace to avoid concurrent modifications; Herdr itself supports worktree-backed workspaces. [Herdr Configuration](https://herdr.dev/docs/configuration/#worktrees) and [Herdr Socket API](https://herdr.dev/docs/socket-api/#worktree-methods) (accessed 2026-08-24).

### Agent state and credentials

**Verified:** OpenCode's CLI stores authenticated provider credentials in `~/.local/share/opencode/auth.json`, and OpenCode also reads project and global configuration, plugins, and agent data from documented locations. [OpenCode CLI](https://opencode.ai/docs/cli/#auth) and [OpenCode Config](https://opencode.ai/docs/config/) (accessed 2026-08-24).

**Recommendation:** Persist OpenCode state in a dedicated named volume or a dedicated host directory, not the whole home directory. If host sharing is required, mount only the state directory and make all unrelated credential directories unavailable. Prefer provider environment injection through a secret-handling mechanism rather than baking credentials into an image or committing them to `opencode.json`.

**Verified:** Apple supports `--ssh` to forward the host SSH authentication socket into a container, and documents the equivalent socket mount and `SSH_AUTH_SOCK` environment variable. [Apple Host Integration](https://github.com/apple/container/blob/main/docs/host-integration.md#mount-your-host-ssh-authentication-socket-in-your-container) (accessed 2026-08-24).

**Recommendation:** Do not enable `--ssh` by default. It gives the container access to the host's SSH agent. Enable it only for tasks that need private Git access, and prefer read-only/delegated repository credentials where possible.

### Herdr/OpenCode plugin

**Verified:** Herdr's integration installer writes the OpenCode plugin to `~/.config/opencode/plugins/herdr-agent-state.js`, while OpenCode automatically loads plugins from that global directory. [Herdr Integrations](https://herdr.dev/docs/integrations/#opencode) and [OpenCode Plugins](https://opencode.ai/docs/plugins/#from-local-files) (accessed 2026-08-24).

**Recommendation:** For Option A, bake the pinned Herdr plugin into the image or install it during image build. For Option B, mount or bake the plugin into the container at the container user's OpenCode config path. Pin both Herdr and OpenCode versions and record the plugin source commit because Herdr's integration asset is managed by Herdr and may be overwritten on integration updates.

### Performance tradeoff

**Verified:** Apple states that named volumes provide better I/O performance than bind mounts when host sharing is unnecessary. [Apple Mounts and Volumes](https://github.com/apple/container/blob/main/docs/volumes.md#named-volumes) (accessed 2026-08-24).

**Recommendation:** Keep source code on a bind mount when host editors must see changes. Put dependency caches, build output, OpenCode session data, and temporary indexes on named volumes where practical. Validate file-watcher behavior and Git performance with the actual repository because the sources do not provide OpenCode-specific benchmarks for Apple virtiofs mounts.

## Networking

### Provider/API access

**Verified:** Apple containers attach to a `default` vmnet network by default and receive an IP address reachable from the host and same-network containers. Apple supports published TCP/UDP ports and isolated user-defined networks on macOS 26 or later. [Apple Networking](https://github.com/apple/container/blob/main/docs/networking.md) and [Apple Command Reference](https://github.com/apple/container/blob/main/docs/command-reference.md) (accessed 2026-08-24).

**Recommendation:** Allow outbound HTTPS from the OpenCode container for model-provider APIs, package registries, and Git hosting. Do not publish OpenCode's server port unless a second client is required. If a host-side OpenCode client is needed, bind it to loopback with `-p 127.0.0.1:HOST:CONTAINER` and protect it with OpenCode basic authentication.

### OpenCode server mode

**Verified:** `opencode serve` exposes an HTTP API, defaults to `127.0.0.1:4096`, and supports `--hostname`, `--port`, and HTTP basic authentication via `OPENCODE_SERVER_PASSWORD`. [OpenCode Server](https://opencode.ai/docs/server/) (accessed 2026-08-24).

**Recommendation:** Keep `opencode serve` on loopback inside the container unless remote API access is explicitly required. If publishing it to the host, use a loopback host bind, set `OPENCODE_SERVER_PASSWORD`, and do not expose it to the LAN. The OpenCode HTTP server is separate from the Herdr Unix socket integration; do not replace the Herdr socket relay with an unauthenticated OpenCode HTTP endpoint.

### Container-to-container and host access

**Verified:** Apple documents domain-qualified DNS names for containers on the default network, isolated custom networks, and a host-service DNS mechanism using `container system dns create ... --localhost`. [Apple Networking](https://github.com/apple/container/blob/main/docs/networking.md) and [Apple Host Integration](https://github.com/apple/container/blob/main/docs/host-integration.md#access-a-host-service-from-a-container) (accessed 2026-08-24).

**Recommendation:** Use the default network for ordinary outbound API access. Use a custom isolated network only when several containers must communicate. Prefer the Unix-socket relay for Herdr because it is narrower than exposing Herdr through a TCP service. If a host service must be reached, use Apple's documented host DNS mechanism and account for its macOS packet-filter and restart limitations.

## Security Boundaries

### Apple VM boundary

**Verified:** Apple describes per-container lightweight VMs as providing VM-like isolation properties and says only necessary host data is mounted into each VM. [Apple Technical Overview](https://github.com/apple/container/blob/main/docs/technical-overview.md#how-does-container-run-my-container) and [Apple Containerization README](https://github.com/apple/containerization/blob/main/README.md#design) (accessed 2026-08-24).

**Recommendation:** Use the VM boundary to constrain package installation, arbitrary shell commands, compiler/toolchain behavior, and filesystem access. Do not treat it as protection for data deliberately exposed through bind mounts, forwarded sockets, SSH agent forwarding, or published services.

### Linux runtime controls

**Verified:** Apple's runtime has a restricted default Linux capability set and supports `--cap-add`, `--cap-drop`, `--read-only`, `--read-only-path`, `--masked-path`, and `--tmpfs`. [Apple Runtime Configuration](https://github.com/apple/container/blob/main/docs/runtime-configuration.md) and [Apple Command Reference](https://github.com/apple/container/blob/main/docs/command-reference.md) (accessed 2026-08-24).

**Recommendation:** Start with the default capability set; for untrusted work, drop all capabilities and add only a tested minimum. Make the image root read-only where possible, mount only the workspace read-write, use tmpfs for disposable scratch space, and mask or keep read-only sensitive paths. Test the project toolchain before tightening controls because the primary sources define available controls but not the requirements of every language ecosystem.

### Herdr control socket

**Verified:** Herdr's socket API can create, close, split, focus, read, prompt, wait on, and send input to panes and agents, and supports custom agent state reporting. [Herdr Socket API](https://herdr.dev/docs/socket-api/#what-you-can-control) (accessed 2026-08-24).

**Inference:** Relaying the host Herdr socket into a container gives code in that container a control channel to the Herdr session. It is therefore more privileged than a normal project bind mount.

**Recommendation:**

- Relay the socket only for a trusted OpenCode workload.
- Use a dedicated Herdr named session/workspace for containerized agents.
- Avoid mounting the socket into arbitrary build/test helper containers.
- Do not relay the socket through a network listener.
- If the workload is untrusted, use Option A with a container-local Herdr server instead of granting it the host Herdr socket.

### OpenCode permissions

**Verified:** OpenCode permission rules support `allow`, `ask`, and `deny`; explicit deny remains enforced in `--auto` mode. OpenCode defaults are permissive for most operations, while `.env` files are denied by default in the documented permission example. [OpenCode Permissions](https://opencode.ai/docs/permissions/) (accessed 2026-08-24).

**Recommendation:** Configure project or managed OpenCode permissions deliberately. In particular, keep `bash` and `edit` at `ask` for untrusted tasks, deny destructive command patterns, and use a separate read-only/review agent when possible. Container isolation is a second boundary, not a replacement for OpenCode's action policy.

## Image and Build Requirements

**Verified:** `container build` builds OCI images from a Dockerfile or Containerfile using BuildKit and supports architecture/platform selection, build secrets, SSH forwarding, CPU, and memory controls. [Apple Command Reference, `container build`](https://github.com/apple/container/blob/main/docs/command-reference.md#container-build) (accessed 2026-08-24).

**Verified:** OCI image indexes identify platform-specific manifests using `os`, `architecture`, and optional variant fields; consumers should be prepared to process image indexes. [OCI Image Index Specification](https://github.com/opencontainers/image-spec/blob/main/image-index.md) (accessed 2026-08-24).

**Recommendation:** Build and publish a pinned `linux/arm64` development image. Include:

- Herdr's Linux binary at a pinned release.
- OpenCode's Linux arm64 binary or a pinned OpenCode image.
- The project compiler/runtime and Git tooling.
- The pinned Herdr OpenCode integration plugin.
- A non-root user whose UID/GID matches the mounted workspace policy.
- An init process where the image launches multiple processes or needs signal forwarding and zombie reaping.

Apple documents `--init` for a lightweight init that forwards signals and reaps orphaned children. [Apple Runtime Configuration](https://github.com/apple/container/blob/main/docs/runtime-configuration.md#run-a-container-with-a-provided-init-process) (accessed 2026-08-24).

**Recommendation:** Do not install OpenCode with a floating `latest` URL at every container start. Build-time installation or a pinned release image makes startup and rollback predictable. OpenCode's own image disables the Bun runtime transpiler cache by default because ephemeral containers do not benefit from it; that is a useful baseline for disposable images. [OpenCode Dockerfile](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/Dockerfile) (accessed 2026-08-24).

## Lifecycle and Orchestration

### Recommended host-supervised flow for Option B

**Recommendation:** Keep the lifecycle deliberately simple:

1. `container system start` once per host boot or service installation.
2. Build/pull the pinned arm64 image.
3. Create a named Apple container without `--rm` when restart/debug inspection is needed.
4. Start it from a Herdr pane with TTY and interactive stdin enabled.
5. Pass the project mount, OpenCode state volume, Herdr environment, and Herdr socket publication at creation time.
6. Let Herdr keep the attached container client process alive while detached.
7. On normal shutdown, stop the Herdr session or container gracefully; delete the container only after state has been verified and any named volumes are retained.
8. On host reboot, explicitly restart the Apple container and reattach/recreate the Herdr workspace. Do not assume a running VM survives host shutdown.

**Verified:** Apple exposes separate `create`, `start`, `stop`, `kill`, `delete`, `list`, `exec`, `logs`, and `inspect` operations. `container create` leaves a stopped container, `container start` starts it, and `container stop` performs graceful signal-based shutdown before its timeout. [Apple Command Reference](https://github.com/apple/container/blob/main/docs/command-reference.md) (accessed 2026-08-24).

**Verified:** Herdr's live persistence keeps panes and processes alive on client detach, but a Herdr server restart does not preserve arbitrary running processes. Snapshot restore reconstructs layout and shells; native agent restore applies only where an official integration reported a valid session reference. [Herdr Session State](https://herdr.dev/docs/session-state/) (accessed 2026-08-24).

**Recommendation:** For OpenCode, install the current Herdr integration and verify `herdr integration status`. Verify the plugin has successfully reported a session before relying on native restore. If the container itself is recreated, persist OpenCode session data and use a stable project/state path; otherwise expect a new OpenCode session.

### Resource sizing

**Verified:** Apple supports per-container CPU and memory limits, and `container stats` reports resource usage. [Apple Command Reference](https://github.com/apple/container/blob/main/docs/command-reference.md#container-run) and [Apple Resource Usage](https://github.com/apple/container/blob/main/docs/resource-usage.md) (accessed 2026-08-24).

**Recommendation:** Start with 4 CPUs and 4-8 GiB memory for a single moderate agent plus language tooling, then measure. Allocate additional memory for large repositories, TypeScript/Rust builds, LSP servers, and multiple concurrent agents. Keep a separate named volume for dependency caches so container recreation does not force cold installs.

## Concrete Setup Recommendation

### Default choice

Choose **Option B** when the operator wants macOS-native Herdr and accepts the host Herdr socket as a trusted control-plane capability. Choose **Option A** instead when the workload may be untrusted or when the simplest reliable detection model is more important than host-native UI.

### Host-native Herdr plus containerized OpenCode checklist

**Recommendation:** Implement the following in a versioned setup document or wrapper, using real paths and IDs from the local machine rather than hard-coding them:

```text
Prerequisites:
- Apple silicon Mac
- Supported macOS/container release
- container system start
- Herdr installed and running on the host
- Pinned linux/arm64 development image

Container inputs:
- repository/worktree -> /workspace/project (rw)
- OpenCode state -> dedicated named volume or narrow host directory
- Herdr socket -> /run/herdr.sock via --publish-socket
- HERDR_ENV=1
- HERDR_PANE_ID=<current Herdr pane id>
- HERDR_SOCKET_PATH=/run/herdr.sock

Process:
- interactive TTY
- working directory /workspace/project
- opencode

Security defaults:
- no --ssh unless required
- no host-home mount
- no published OpenCode HTTP port unless required
- read-only image root where the toolchain permits
- narrow rw project mount
- explicit OpenCode bash/edit permissions
```

The exact `container run`/`container create` argument spelling must be tested with the installed release, especially `--publish-socket`, mount permissions, and the container image's runtime user. The primary Apple sources document the socket publication option and lower-level relay API, but do not document an end-to-end Herdr example.

### Verification test

**Recommendation:** Before using real credentials or important repositories, verify:

1. Herdr reports the pane as an OpenCode agent, or the official plugin reports its state through `herdr agent get <pane-or-name>`.
2. OpenCode transitions from working to idle and blocked states and those transitions appear in Herdr.
3. `herdr agent wait <target> --until blocked` returns when OpenCode requests approval/question input.
4. A session ID appears in Herdr's pane/agent information after OpenCode creates a session.
5. A container stop/restart preserves only the state intentionally mounted or volume-backed.
6. A client detach leaves both the Herdr pane and container process alive.
7. The container cannot read unrelated host files or use the Herdr socket when the relay is omitted.
8. Provider HTTPS, Git access, file watching, LSPs, and large builds work under the selected mounts and resource limits.

## Unknowns and Unresolved Compatibility Questions

The following should remain explicit test or upstream-tracking items rather than assumptions:

- **End-to-end socket publication:** Apple documents `--publish-socket` and the lower-level relay implementation, but the reviewed primary sources do not show a Herdr-specific invocation or confirm all permission behavior for a Herdr socket path.
- **Host Herdr detection through the Apple VM:** Herdr documents that it cannot see an agent when the relevant hint exists only inside a VM/container. Whether any particular `container` client version exposes enough foreground-process metadata for improved detection is not established by the reviewed sources.
- **OpenCode integration under a relayed socket:** The official plugin is implemented with a Unix socket client and should be transport-compatible with a relay, but the reviewed sources do not provide an integration test across Apple's VM boundary.
- **Plugin and state ownership:** The correct OpenCode config directory depends on the image's runtime user and `HOME`. The Herdr installer path and OpenCode plugin search paths are documented, but an image-specific user/home convention must be chosen and tested.
- **Filesystem watcher performance:** Apple documents virtiofs/bind mounts and named-volume performance characteristics, but no primary source reviewed here establishes acceptable OpenCode watcher/indexing performance for a particular repository.
- **Signal and PTY behavior:** Apple exposes TTY, interactive, init, and stop controls, and Herdr owns PTYs, but the exact behavior during nested container stop, host sleep, and host reboot needs an integration test.
- **macOS version drift:** Apple's current docs distinguish current-branch behavior and release-tag behavior, while the project is active and pre-1.0. Pin the Apple `container` release and validate the command reference against that tag before production use.
- **Nested runtime support:** Nested virtualization has explicit hardware/kernel requirements and is not needed for Options A-C. Do not infer that an arbitrary Docker daemon or nested OCI runtime will work inside an Apple container machine.

## Primary Sources

- [Herdr repository](https://github.com/herdrdev/herdr) — runtime, integration assets, and source; accessed 2026-08-24.
- [Herdr Concepts](https://herdr.dev/docs/concepts/) — server/client, workspace, pane, and agent model; accessed 2026-08-24.
- [Herdr Agents](https://herdr.dev/docs/agents/) — VM/sandbox visibility and detection authority; accessed 2026-08-24.
- [Herdr Integrations](https://herdr.dev/docs/integrations/) — OpenCode plugin installation and behavior; accessed 2026-08-24.
- [Herdr Agent Automation](https://herdr.dev/docs/agent-automation/) — pane and agent orchestration; accessed 2026-08-24.
- [Herdr Session State](https://herdr.dev/docs/session-state/) — detach, restart, and native session restore; accessed 2026-08-24.
- [Herdr Socket API](https://herdr.dev/docs/socket-api/) — Unix socket protocol and control surface; accessed 2026-08-24.
- [OpenCode documentation](https://opencode.ai/docs/) — installation and operation; accessed 2026-08-24.
- [OpenCode CLI](https://opencode.ai/docs/cli/) — run, serve, auth, attach, and environment variables; accessed 2026-08-24.
- [OpenCode Server](https://opencode.ai/docs/server/) — HTTP server and authentication; accessed 2026-08-24.
- [OpenCode Plugins](https://opencode.ai/docs/plugins/) — plugin locations and hooks; accessed 2026-08-24.
- [OpenCode Permissions](https://opencode.ai/docs/permissions/) — action policy and defaults; accessed 2026-08-24.
- [OpenCode Dockerfile](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/Dockerfile) — Alpine and arm64 image build; accessed 2026-08-24.
- [Apple `container` repository](https://github.com/apple/container) — CLI and runtime; accessed 2026-08-24.
- [Apple `container` command reference](https://github.com/apple/container/blob/main/docs/command-reference.md) — run/create/build/lifecycle flags; accessed 2026-08-24.
- [Apple Mounts and Volumes](https://github.com/apple/container/blob/main/docs/volumes.md) — bind mounts, named volumes, and tmpfs; accessed 2026-08-24.
- [Apple Networking](https://github.com/apple/container/blob/main/docs/networking.md) — vmnet, DNS, publishing, and isolated networks; accessed 2026-08-24.
- [Apple Host Integration](https://github.com/apple/container/blob/main/docs/host-integration.md) — SSH agent and host-service access; accessed 2026-08-24.
- [Apple Runtime Configuration](https://github.com/apple/container/blob/main/docs/runtime-configuration.md) — capabilities, masks, read-only paths, init, and nested virtualization; accessed 2026-08-24.
- [Apple Container Machine](https://github.com/apple/container/blob/main/docs/container-machine.md) — persistent Linux machine model; accessed 2026-08-24.
- [Apple Technical Overview](https://github.com/apple/container/blob/main/docs/technical-overview.md) — per-container VM architecture; accessed 2026-08-24.
- [Apple Containerization repository](https://github.com/apple/containerization) — low-level VM/container APIs; accessed 2026-08-24.
- [Apple `UnixSocketConfiguration.swift`](https://github.com/apple/containerization/blob/main/Sources/Containerization/UnixSocketConfiguration.swift) — socket relay configuration; accessed 2026-08-24.
- [Apple `UnixSocketRelay.swift`](https://github.com/apple/containerization/blob/main/Sources/Containerization/UnixSocketRelay.swift) — host/guest Unix socket relay implementation; accessed 2026-08-24.
- [Apple Virtualization framework](https://developer.apple.com/documentation/virtualization.md) — official VM and device APIs; accessed 2026-08-24.
- [OCI Image Index Specification](https://github.com/opencontainers/image-spec/blob/main/image-index.md) — platform-specific OCI manifests; accessed 2026-08-24.
- [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec/blob/main/config.md) — process, mounts, capabilities, and runtime configuration; accessed 2026-08-24.
