# .NET 10 dev container for Claude Code with skip-permissions

Companion code for the article [Never Run Claude Code with Skip-Permissions on Your Host](https://codewithmukesh.com/blog/claude-code-skip-permissions-devcontainer-dotnet/).

A dev container for .NET 10 work where Claude Code can run with `--dangerously-skip-permissions` and the blast radius stays inside the container:

- Runs as the non-root `vscode` user (the CLI refuses the flag as root).
- `sudo` is limited to one command, the firewall script. The base image's blanket `NOPASSWD: ALL` is removed.
- Default-deny outbound firewall. Only HTTPS to the Anthropic, NuGet and GitHub domains in `allowed-domains.txt` is allowed.
- DNS goes through a local dnsmasq that answers only for allowlisted domains and returns REFUSED for everything else, so DNS cannot be used to tunnel data out. Only root (dnsmasq) can reach the upstream DNS server.
- IPv6 is blocked entirely.
- No host `~/.ssh`, cloud credentials or Git credentials are mounted.
- Claude config and the NuGet cache live in named volumes, owned by the non-root user.

## Files

| File | What it does |
|------|--------------|
| `.devcontainer/devcontainer.json` | Image build, Node + Claude Code features, non-root user, capabilities, volumes, firewall on start |
| `.devcontainer/Dockerfile` | Firewall tools, sudo lockdown, volume ownership |
| `.devcontainer/sandbox-firewall.sh` | iptables + ipset default-deny, dnsmasq filtering DNS, IPv6 off |
| `.devcontainer/allowed-domains.txt` | The domains the container may reach |
| `src/Hello` | A console app with one NuGet package, to prove restore works behind the firewall |

## Run it

```bash
npx @devcontainers/cli up --workspace-folder .
npx @devcontainers/cli exec --workspace-folder . bash
```

Or open the folder in VS Code and choose **Reopen in Container**.

Inside the container:

```bash
cd src/Hello && dotnet run         # NuGet restore works
curl -m 8 https://example.com      # blocked
sudo iptables -F                   # sudo: a password is required
claude --dangerously-skip-permissions
```

## Gotchas this repo works around

1. The `claude-code` dev container feature (1.0.5) installs its own `/usr/local/bin/init-firewall.sh`. If your script has the same name, the feature overwrites it. In my test the feature's script then failed with `ERROR: Failed to resolve statsig.anthropic.com`. This repo names its script `sandbox-firewall.sh`.
3. Restricting port 53 to the container's resolver does not stop DNS tunneling, because the resolver Docker gives the container is public (1.1.1.1 and 8.8.8.8 in my test) and forwards a query for any domain. This repo filters DNS by name instead.
2. `mcr.microsoft.com/devcontainers/dotnet:10.0` gives `vscode` passwordless sudo for everything, so any process in the container can run `sudo iptables -F` and turn the firewall off. The Dockerfile deletes `/etc/sudoers.d/vscode`.

## Known limits

The allowlist is resolved to IPs when the container starts. CDN-backed hosts can change IPs, so rerun `sudo /usr/local/bin/sandbox-firewall.sh` if NuGet restore starts failing.

## What this does not protect

Anything inside the container, including your Claude credentials in `~/.claude` and your source code, can still be sent to an allowed domain. Use it with repositories you trust, review changes to `.devcontainer/` before you rebuild, and keep the allowlist short.
