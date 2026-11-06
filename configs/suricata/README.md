# Suricata configuration notes

Suricata runs on the SOC VM next to Wazuh. Its alerts are written as EVE JSON and ingested by the Wazuh manager (see [`../wazuh/ossec-snippets.xml`](../wazuh/ossec-snippets.xml)).

## Install and load rules

```bash
sudo apt install suricata -y
sudo suricata-update          # Emerging Threats Open
# >> Total rules loaded: 41393
# >> Total rules failed: 0
```

## Let Wazuh read `eve.json`

By default `eve.json` is not readable by the `wazuh` user (mode 640). Fix:

```bash
sudo chmod 644 /var/log/suricata/eve.json
sudo chmod 755 /var/log/suricata/
```

and make the mode permanent in `/etc/suricata/suricata.yaml`:

```yaml
outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: eve.json
      filemode: 644
```

## Monitored interfaces

The lab inspects two interfaces at once so that attacks from either path are seen:

- the local VMware network (VMnet8) interface: traffic with n8n and Kali
- the ZeroTier interface (`zt…`): inter-machine lab traffic

List yours with `ip -br link` and configure them under `af-packet:` in `suricata.yaml`.

## Update the rules

```bash
sudo suricata-update && sudo systemctl restart suricata
```
