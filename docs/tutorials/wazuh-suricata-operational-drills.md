# Wazuh & Suricata — incident notebook and operational drills

This companion to [the deployment tutorial](./wazuh-suricata-deployment.md) captures why the September 2026 sprint required multiple acceptance gates. It is intentionally additive to the main installation guide and distinguishes **observed historical evidence** from present-day live health.

## Gate-oriented troubleshooting sequence

1. **Network before packages:** OpenStack SG → route → edge nftables → listening socket. The edge alone carries nftables; the other OpenStack hosts depend on Terraform security groups. Verify access from each authorized network; public access to the Indexer or Dashboard is never a diagnostic requirement.
2. **Manager before agents:** `systemctl status wazuh-manager`, `agent_control -l`, Manager `ossec.log`, then each agent's `ossec.log`. A local Manager identity is not a remote host. Enrollment and post-enrollment event forwarding are separate connections.
3. **Raw events before search:** verify Manager `alerts.json` *before* debugging Filebeat, Indexer or Dashboard. Inspect one known benign event rather than spraying network probes.
4. **Private Indexer before Filebeat enablement:** provision Cinder PVC, security bootstrap, TLS and credentials; validate authenticated Indexer health; only then set the private Filebeat enable/configure variables and run its config/output tests. Confirm a real document in the expected date-based index.
5. **Sensor capture before Wazuh decoder:** Suricata `-T`, effective interface and HOME_NET, EVE JSON and ownership, then `wazuh-logcollector -t`, Manager alert and indexed document. A Suricata `stats` EVE record is not an IDS signature hit.
6. **Metrics provenance before visualization:** current dashboard family has measured Traefik and Kubernetes/Indexer-container state; Manager, Filebeat and Suricata sensor counters require separately verified exporters. Missing target ≠ zero incidents.

## Safely replayable exercises

**Exercise A — missing agent:** in an isolated exercise project, deliberately withhold an *authorized* enrollment flow with a temporary SG rule; document the failed gate and revert the rule. Do not strand the edge administrative session. **Exercise B — JSON pipeline:** generate one benign detection with the tracked SID 9900001 on an approved HTTP endpoint; show the difference between EVE, Manager alert and searchable Indexer record. **Exercise C — resilience:** recycle a disposable Indexer Pod and verify the PVC and indexed test document survive; restore from a documented snapshot into an isolated environment when backup infrastructure exists. **Exercise D — monitoring truth:** inspect a Grafana panel's PromQL and its actual Prometheus series, and explicitly mark unavailable exporters rather than charting hypothetical packet drops.

## Evidence template

Capture exercise ID/date, repo commit and deployed Argo targetRevision; cloud project, host inventory **with sensitive addresses redacted in public submissions**; service versions; traffic/sensor placement; exact benign test stimulus; EVE SID/time; Wazuh alert ID and rule/time; target index and authorized query; measured metric names and job labels; recovery actions and rollback validation. Include a short account of one false assumption corrected by evidence.

## Boundaries and follow-up

This project currently describes **IDS detection**, not inline IPS drop enforcement. AF_PACKET on the edge's routed interface does not see arbitrary traffic between Kubernetes worker Pods. Recording attacker-controlled log payloads into an AI agent's prompt is unsafe; the agent-control-plane must restrict read-only evidence retrieval, avoid executing text from logs, and retain audit history. Before a student challenge, isolate credentials and targets, implement EVE/Wazuh rotation and Indexer snapshot/restore drills, assess retention/privacy and close the remaining public SSH path only after private recovery is proven.
