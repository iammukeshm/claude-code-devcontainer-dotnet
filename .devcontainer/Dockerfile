FROM mcr.microsoft.com/devcontainers/dotnet:10.0

# Tools for the outbound firewall.
RUN apt-get update \
    && apt-get install -y --no-install-recommends iptables ipset dnsutils jq \
    && rm -rf /var/lib/apt/lists/*

COPY sandbox-firewall.sh /usr/local/bin/sandbox-firewall.sh
COPY allowed-domains.txt /usr/local/etc/allowed-domains.txt

# The base image gives vscode passwordless sudo for everything. Remove it,
# then allow exactly one root command: the firewall script.
RUN rm -f /etc/sudoers.d/vscode \
    && chmod 755 /usr/local/bin/sandbox-firewall.sh \
    && echo "vscode ALL=(root) NOPASSWD: /usr/local/bin/sandbox-firewall.sh" > /etc/sudoers.d/firewall \
    && chmod 0440 /etc/sudoers.d/firewall

# Named volumes copy ownership from the image on first mount, so the
# non-root user owns its Claude config and NuGet cache without sudo.
RUN mkdir -p /home/vscode/.claude /home/vscode/.nuget/packages \
    && chown -R vscode:vscode /home/vscode/.claude /home/vscode/.nuget
