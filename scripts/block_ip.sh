#!/usr/bin/env bash
# SSH chain, hop 2 (runs on the Ubuntu router): reaches pfSense on its LAN.
#
# Usage:   SSHPASS=<password> ./block_ip.sh <ipv4>
# Output:  "Block added successfully" or "Block entry already exists." (dedup)
#
# The lab used sshpass. SSH key authentication is preferable: drop `sshpass -e`
# and install the router's public key on the pfSense admin account.
set -euo pipefail

IP="${1:?usage: $0 <ipv4-address>}"
PFSENSE_USER="${PFSENSE_USER:-admin}"
PFSENSE_HOST="${PFSENSE_HOST:-192.168.1.1}"
: "${SSHPASS:?export SSHPASS (pfSense password), or switch this script to key-based auth}"

OCTET='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
if ! [[ "$IP" =~ ^${OCTET}\.${OCTET}\.${OCTET}\.${OCTET}$ ]]; then
    echo "error: '$IP' is not a valid IPv4 address" >&2
    exit 2
fi

sshpass -e ssh -o StrictHostKeyChecking=accept-new \
    "${PFSENSE_USER}@${PFSENSE_HOST}" "easyrule block wan $IP"
