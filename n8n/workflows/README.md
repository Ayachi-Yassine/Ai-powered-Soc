# Workflow export

Put the exported workflow here as `SOCPilot_Groq_v4.3.json` (n8n → workflow menu → *Download*).

## Sanitize before committing

An n8n export can contain secrets or private details. Check it first:

```bash
# Look for anything that smells like a secret, token, password or private host
grep -nEi 'api[_-]?key|token|password|bearer|gsk_|authorization|sshpass' SOCPilot_Groq_v4.3.json
```

- Credentials referenced through n8n's credential store appear only as IDs/names. That is fine.
- Anything hard-coded in an HTTP Request header or in a Code node (API keys, the Telegram bot token, the pfSense password, chat IDs) must be removed and moved to n8n credentials or environment variables.
- If a secret was ever committed by mistake, **rotate it**. Deleting the file in a later commit does not remove it from git history.

Keep the unsanitized export out of the repo; files named `*.raw.json` in this folder are git-ignored.
