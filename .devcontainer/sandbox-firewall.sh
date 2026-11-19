#!/bin/bash
# Default-deny network sandbox for the dev container. Runs as root at start.
# - Outbound HTTPS only to the IPs of the domains in allowed-domains.txt.
# - DNS only through a local dnsmasq that answers for those domains and
#   refuses everything else, so DNS cannot be used to tunnel data out.
# - IPv6 blocked entirely.
set -euo pipefail

ALLOWLIST=/usr/local/etc/allowed-domains.txt
UPSTREAM_DNS=1.1.1.1

# Open up while we rebuild the rules, so this script can be re-run.
iptables -P OUTPUT ACCEPT
iptables -P INPUT ACCEPT
iptables -F
ipset destroy allowed 2>/dev/null || true
ipset create allowed hash:net

# Resolve the allowlist and write the dnsmasq config.
DNS_CONF=/etc/dnsmasq.d/sandbox.conf
mkdir -p /etc/dnsmasq.d
printf 'no-resolv\nlisten-address=127.0.0.1\nbind-interfaces\nuser=root\n' > "$DNS_CONF"

while read -r domain; do
    [[ -z "$domain" || "$domain" == \#* ]] && continue
    echo "server=/$domain/$UPSTREAM_DNS" >> "$DNS_CONF"
    for ip in $(dig +short A "$domain" @"$UPSTREAM_DNS" | grep -E '^[0-9.]+$'); do
        ipset add allowed "$ip" -exist
    done
    echo "allowed: $domain"
done < "$ALLOWLIST"

pkill dnsmasq 2>/dev/null || true
dnsmasq --conf-file="$DNS_CONF"

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
# Only root (dnsmasq) may talk to the upstream DNS server.
iptables -A OUTPUT -p udp -d "$UPSTREAM_DNS" --dport 53 -m owner --uid-owner 0 -j ACCEPT
iptables -A OUTPUT -p tcp -d "$UPSTREAM_DNS" --dport 53 -m owner --uid-owner 0 -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p tcp -m set --match-set allowed dst --dport 443 -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# No IPv6 at all, so nothing can go around the IPv4 rules.
ip6tables -F
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

echo "Firewall ready. Outbound traffic is limited to the allowlist."
