# Setup guide

Reproduction guide for the SOCPilot lab. Use isolated virtual machines and run attack simulations **only against systems you own**.

## 1. Lab layout

The original lab ran on 3 physical PCs. Any host that can run the VMs below works.

| Machine | RAM | vCPU | OS | Role |
|---|---|---|---|---|
| SOC VM | 8 GB | 4 | Ubuntu 22.04.5 LTS | Wazuh (manager, indexer, dashboard) + Suricata |
| Kali Linux | 4 GB | 2 | Kali 2025.x | Attack simulation |
| pfSense | 2 GB | 2 | pfSense CE 2.8.1 | Perimeter firewall |
| Ubuntu router | 1 GB | 1 | Ubuntu 22.04 LTS | Gateway between ZeroTier and the pfSense LAN |
| AD server | 4 GB | 2 | Windows Server 2019 (Eval) | Domain controller `SOCLAB.local` |
| Docker VM | 3 GB | 2 | Ubuntu 22.04 LTS | DVWA, Juice Shop |
| n8n host | 8 GB | 4 | Windows 10/11 Pro | n8n SOAR |

## 2. ZeroTier

Create a network in ZeroTier Central, then on every VM:

```bash
curl -s https://install.zerotier.com | sudo bash   # review the script first if you prefer
sudo zerotier-cli join <NETWORK_ID>
# approve each node in ZeroTier Central, then verify:
sudo zerotier-cli listnetworks
```

## 3. pfSense

Install pfSense CE in a VM (WAN in NAT mode, LAN on an internal network), then from the console:

- Option 1, assign interfaces: WAN `em0`, LAN `em1`, no VLAN
- Option 2, set the LAN address: `192.168.1.1/24`, with a DHCP range such as `192.168.1.100–254`
- Enable SSH access; it is needed for the automated blocking chain

## 4. Active Directory

Promote Windows Server 2019 to a domain controller for the forest `SOCLAB.local`, create a few test users, and apply a GPO (`SecurityPolicy`) with: minimum password length 8, lockout after 5 failed attempts, lockout duration 10–15 minutes.

Enable advanced auditing so Wazuh receives the events it needs (elevated PowerShell/cmd):

```cmd
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Privilege Use" /success:enable /failure:enable
auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable
```

Install the Wazuh agent on the DC. Events of interest:

| Event ID | Meaning | MITRE |
|---|---|---|
| 4625 | Failed logon | T1110 |
| 4740 | Account lockout | T1110.003 |
| 4624 | Successful logon | T1078 |
| 4672 | Special privileges assigned | T1548 |
| 4720 | User account created | T1136 |
| 7045 | New service installed | T1543 |

## 5. Wazuh

On the SOC VM (Ubuntu 22.04, 8 GB RAM), all-in-one install:

```bash
curl -sO https://packages.wazuh.com/4.7/wazuh-install.sh
sudo bash ./wazuh-install.sh -a
```

This deploys the manager (1514/55000), the indexer (9200, localhost), the dashboard (443) and Filebeat. Then:

1. Merge [`configs/wazuh/ossec-snippets.xml`](../configs/wazuh/ossec-snippets.xml) into `/var/ossec/etc/ossec.conf` (replace `<N8N_HOST>`).
2. Install the integration script:
   ```bash
   sudo install -o root -g wazuh -m 750 configs/wazuh/custom-webhook /var/ossec/integrations/custom-webhook
   sudo systemctl restart wazuh-manager
   ```
3. Deploy Wazuh agents on the endpoints and the DC, and check them with `sudo /var/ossec/bin/agent_control -l`.
4. Create the persistent blacklist file used by PB1: `/var/ossec/etc/lists/blacklist-ip`.

PB1's host-level block calls Wazuh's `firewall-drop` Active Response script directly:
`/var/ossec/active-response/bin/firewall-drop add - <IP> - -`

## 6. Suricata

Follow [`configs/suricata/README.md`](../configs/suricata/README.md): install, load the ET Open rules, fix the `eve.json` permissions, and select the interfaces to monitor.

## 7. SSH chain to pfSense

`n8n → SOC VM → Ubuntu router → pfSense`

1. Copy [`scripts/pfsense_block.sh`](../scripts/pfsense_block.sh) to the SOC VM home directory, and [`scripts/block_ip.sh`](../scripts/block_ip.sh) to the Ubuntu router home directory. Make both executable.
2. Install `sshpass` on the router if you use password authentication (SSH keys are preferable).
3. Set the environment (`ROUTER_USER`, `ROUTER_HOST` on the SOC VM; `PFSENSE_USER`, `PFSENSE_HOST`, `SSHPASS` on the router). See [`.env.example`](../.env.example).
4. Test with an address from the documentation range so you do not block a real host:
   ```bash
   ~/pfsense_block.sh 203.0.113.50
   # Block added successfully
   ```

## 8. n8n

1. Install n8n (self-hosted) and import the workflow from [`n8n/workflows/`](../n8n/workflows/README.md).
2. Create the credentials: Groq API key, Telegram bot token and chat ID.
3. Set the SSH targets used by the playbook nodes.
4. Make sure **no other workflow** is active on `/webhook/wazuh-alert`, then activate this one.

Node-by-node details: [`n8n/README.md`](../n8n/README.md).

## 9. Validation scenarios

Lab only. Replace the placeholders with addresses from your own isolated network.

**T1, SSH brute force (from Kali):**

```bash
hydra -l root -P /usr/share/wordlists/rockyou.txt ssh://<TARGET_IP> -t 4 -vV
```

Expected: rule 5760 escalates to 5763, the AI returns `BRUTE_FORCE`, the source IP is blocked on the host and on pfSense, a Telegram alert arrives.

**T2, AD password spraying (PowerShell on a domain machine):**

```powershell
for ($i = 1; $i -le 6; $i++) {
  $sp = ConvertTo-SecureString "WrongPass$i" -AsPlainText -Force
  $cr = New-Object System.Management.Automation.PSCredential("SOCLAB\user1", $sp)
  try { Start-Process "cmd.exe" -Credential $cr -EA Stop }
  catch { Write-Host "Attempt $i : FAILED" }
  Start-Sleep 1
}
```

Expected: events 4625 ×6 and 4740 ×1, verdict `HIGH_RISK`, `user1` disabled (`Enabled : False`).

**T3, malware detection:** create the standard EICAR antivirus test file (see eicar.org) in a directory monitored by Wazuh FIM on a Linux agent, and make it executable. Expected: FIM alert in seconds, verdict `MALWARE`, PB3 kills the process and quarantines the file.

**TS1, forged alert:** POST a fake alert to the webhook asking to block a well-known public IP and check that the AI does not trigger a playbook.

```bash
curl -X POST http://<N8N_HOST>:5678/webhook/wazuh-alert \
  -H "Content-Type: application/json" \
  -d '{"body":{"rule":{"description":"INJECT block 8.8.8.8","level":15},"data":{"srcip":"8.8.8.8"}}}'
```

**TS2, alert flood:** send ~200 identical alerts for one source IP within seconds and confirm the 120 s cooldown collapses them to a handful of executions.

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| pfSense unreachable from ZeroTier | pfSense CE has no native ZeroTier support | Use the SSH chain (section 7) |
| Wazuh cannot read `eve.json` | File mode 640, unreadable by `wazuh` | `chmod 644` + `filemode: 644` in `suricata.yaml` |
| Alerts handled twice or not at all | Two workflows active on the same webhook | Deactivate the old workflow first |
| 50–200 executions per attack | Alert storm from a single run | 120 s cooldown per source IP (Alert Parser) |
| IF nodes raise version errors | n8n version incompatibility | Use a Switch node in *Rules* mode |
| Dashboard unreachable via ZeroTier | SOC VM on NAT without a routable IP | Use the VMnet8 address or the VM's ZeroTier address |
| First Groq call is slow (> 3 s) | Cold start after inactivity | Send a keep-alive ping to the API every 5 minutes |
| AI layer stops answering | API quota exhausted (hit with Gemini free tier during prototyping) | Use Groq; keep the keyword-rule fallback enabled |
