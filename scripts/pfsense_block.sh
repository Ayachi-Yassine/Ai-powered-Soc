#!/usr/bin/env bash
# SSH chain, hop 1 (runs on the SOC VM): n8n -> SOC VM -> Ubuntu router -> pfSense
#
# Usage:   ROUTER_USER=<user> ROUTER_HOST=<zerotier-ip> ./pfsense_block.sh <ipv4>
# Effect:  asks the Ubuntu router to run block_ip.sh, which blocks <ipv4> on pfSense.
#
# pfSense CE cannot join ZeroTier natively, hence the chain.
set -euo pipefail

IP="${1:?usage: $0 <ipv4-address>}"
ROUTER_USER="${ROUTER_USER:?set ROUTER_USER (SSH user on the Ubuntu router)}"
ROUTER_HOST="${ROUTER_HOST:?set ROUTER_HOST (ZeroTier IP of the Ubuntu router)}"
LOG_FILE="${LOG_FILE:-$HOME/pfsense_blocks.log}"

# The value ends up inside a remote shell command: accept a plain IPv4 only.
OCTET='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
if ! [[ "$IP" =~ ^${OCTET}\.${OCTET}\.${OCTET}\.${OCTET}$ ]]; then
    echo "error: '$IP' is not a valid IPv4 address" >&2
    exit 2
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] pfSense block requested: $IP" >> "$LOG_FILE"

# accept-new: trust a host key on first contact, refuse if it later changes.
ssh -o StrictHostKeyChecking=accept-new "${ROUTER_USER}@${ROUTER_HOST}" "~/block_ip.sh $IP"
