#!/bin/bash
# Default-deny outbound firewall for the dev container.
# Only DNS, loopback, the Docker host network and the IPs of the domains in
# /usr/local/etc/allowed-domains.txt are reachable.
set -euo pipefail

ALLOWLIST=/usr/local/etc/allowed-domains.txt

# Keep Docker's embedded DNS (127.0.0.11) working after the flush.
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

iptables -F
iptables -t nat -F
ipset destroy allowed 2>/dev/null || true

if [ -n "$DOCKER_DNS_RULES" ]; then
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
fi

ipset create allowed hash:net

while read -r domain; do
    [[ -z "$domain" || "$domain" == \#* ]] && continue
    for ip in $(dig +short A "$domain" | grep -E '^[0-9.]+$'); do
        ipset add allowed "$ip" -exist
    done
    echo "allowed: $domain"
done < "$ALLOWLIST"

HOST_NETWORK=$(ip route | awk '/default/ {print $3}' | sed 's/\.[0-9]*$/.0\/24/')

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

echo "Firewall ready. Outbound traffic is limited to the allowlist."
