// n8n Code node (JavaScript): "Alert Parser & Router"
// Normalises the Wazuh alert and de-duplicates alert storms.

const body = $input.first().json.body || $input.first().json;
const rule = body.rule || {};
const data = body.data || {};

// === Extract the key fields of the Wazuh alert ===
const srcip = data.srcip || data.src_ip || 'Unknown';
const description = rule.description || 'No description';
const level = parseInt(rule.level) || 0;
const ruleGroups = rule.groups || [];
const agentName = (body.agent || {}).name || 'Unknown';
const fullLog = body.full_log || '';

// === Anti-spam: 120 second cooldown per source IP ===
// A single Hydra run can generate 200+ alerts. Without this, 200 executions
// would hammer the SSH chain to pfSense.
const cacheKey = 'blk_' + srcip.replace(/\./g, '_');
const now = Date.now();
if (typeof global[cacheKey] !== 'undefined' &&
    (now - global[cacheKey]) < 120000) {
  return []; // duplicate: the pipeline stops here
}
global[cacheKey] = now;

// === Normalised risk score (0.0 - 1.0) ===
const riskScore = Math.min(level / 15, 1.0).toFixed(2);
const ticketId = 'SOC-' + now;

return [{ json: { srcip, description, level, ruleGroups,
                  agentName, fullLog, riskScore, ticketId } }];
