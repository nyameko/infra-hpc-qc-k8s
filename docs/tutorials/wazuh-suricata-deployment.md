# Wazuh & Suricata — deployment and verification

> Reference deployment: 23 September 2026. This is a reproducible **teaching runbook**, not a claim that every future environment is already configured. Use the tracked Ansible, Terraform and Argo CD resources as the source of truth; never paste live credentials or private keys into issues, transcripts or student submissions.

## Learning objectives and architecture

By the end, a participant can explain and verify the complete evidence path: remote host → Wazuh agent → edge Wazuh Manager → alerts.json → Filebeat over authenticated TLS → Kubernetes Wazuh Indexer on Cinder → private Wazuh Dashboard. A second path is edge AF_PACKET → Suricata 8 EVE JSON → Wazuh logcollector/decoder/rules → the **same** indexed security investigation. Prometheus/Grafana exposes *operational metrics* separately; Wazuh is the event-evidence system, not a Prometheus substitute.

Ownership is deliberate: Terraform manages OpenStack ports, routes and security groups; Ansible configures the edge Manager, Filebeat, Suricata and host agents; Argo CD reconciles the Indexer and Dashboard in Kubernetes; Cinder CSI supplies persistent Indexer storage; Traefik/HAProxy and WireGuard provide controlled private access. Do **not** install host firewalls on api-lb, control-plane or worker VMs: this deployment uses OpenStack security groups for those nodes, and **nftables only on edge**. The Manager is intentionally outside Kubernetes so the management-plane sensor continues to work if the cluster is unavailable.

### Reference topology and trust boundaries

```text
OpenStack VMs (edge / api-lb / k8s / login / Slurm / Hermes)
    └── Wazuh agents → permitted 1514/TCP; enrollment 1515/TCP → edge Manager
edge routed interface → Suricata 8 → /var/log/suricata/eve.json
                                          ↓ Wazuh logcollector (JSON)
edge Manager → /var/ossec/logs/alerts/alerts.json → Filebeat
                                                    ↓ TLS client certificate
                    private indexer transport / 9200 → Wazuh Indexer (Cinder PVC)
                                                           ↓
                                            private Wazuh Dashboard
Operational plane: verified exporters → Prometheus → Git-managed Grafana dashboards
```

In the reference network, management is `10.50.0.0/24`, Kubernetes is `10.51.0.0/24`, WireGuard is `10.60.0.0/24` and the API VIP is `10.51.0.100:6443`. Treat these as example allocations, not portable constants. Do not open 9200, Dashboard, or 55000 publicly. Wazuh 1516/TCP is for **Manager clustering**, not agents; leave it closed for this single-Manager deployment. Restrict 1514/1515 to enrolled host networks, 55000 to explicitly approved administrative or Dashboard paths. Verify both OpenStack SGs and edge nftables, *from the actual source network*. Test the WireGuard recovery path before tightening public SSH.

## 0. Preflight and inventory

From the repository root, inspect `ansible/inventories/private/hosts.yml`, private/group variables and the effective `wazuh_version`, `wazuh_base`, `wazuh_manager_address`, `suricata_home_net` and Filebeat TLS sources. Use an approved Ansible Vault / local-secret workflow: the CA, client certificates, passwords, bootstrap admin material and unsealed Secrets must never enter Git. Ensure time synchronization, usable Cinder storage and adequate Indexer memory; agree a volume/backup policy before ingesting real research events. Do not share example cloud addresses or hostnames as a blanket access policy.

```bash
cd ansible
ansible-inventory -i inventories/private/hosts.yml --graph
ansible -i inventories/private/hosts.yml edge_nodes -m ping
ansible -i inventories/private/hosts.yml wazuh_agents -m ping
```

**Gate 0:** routes, DNS, WireGuard, time, host permissions and recovery console all work. If enrollment fails, inspect packet reachability before modifying Wazuh configuration.

## 1. Bring up Wazuh Manager on edge

The tracked `ansible/playbooks/edge.yml` applies `wazuh_manager`; the role installs the versioned package from the Wazuh RPM repository and starts the systemd service. The Manager is **not** the Indexer. Check service, listening sockets and log output on edge:

```bash
cd ansible
ansible-playbook -i inventories/private/hosts.yml playbooks/edge.yml --limit edge_nodes
# On edge:
sudo systemctl status wazuh-manager --no-pager
sudo /var/ossec/bin/agent_control -l
sudo tail -n 50 /var/ossec/logs/ossec.log
sudo test -s /var/ossec/logs/alerts/alerts.json && echo 'alerts.json has events'
sudo ss -lntp | grep -E ':1514|:1515|:55000'
```

Verify the configured listener and firewall rather than assuming a port appears merely because the package installed. For each enrollment source, test the OpenStack SG **and** the edge nftables allow rule; do not loosen all interfaces or allow the whole internet just to make an enrollment succeed. If the Manager is up but alerts are missing, check agent and decoder/rule paths before deploying the Dashboard.

## 2. Enroll the persistent hosts

The tracked `playbooks/wazuh-agents.yml` uses the `wazuh_agents` inventory group, serial enrollment and the `wazuh_agent` role; it configures the versioned package with `WAZUH_MANAGER`, `WAZUH_REGISTRATION_SERVER` and inventory-derived `WAZUH_AGENT_NAME`. Enrollment is distinct from event transport. Configure only the hosts actually listed in inventory; Kubernetes workloads are **not** one Wazuh agent per Pod.

```bash
cd ansible
ansible-playbook -i inventories/private/hosts.yml playbooks/wazuh-agents.yml
# On edge:
sudo /var/ossec/bin/agent_control -l
# On one enrolled remote host:
sudo systemctl is-active wazuh-agent
sudo tail -n 50 /var/ossec/logs/ossec.log
```

**Gate 1:** every intended inventory host has exactly one stable agent identity, the expected address and an Active/connected state; distinguish remote agents from the Manager's local `000` identity. At the 2026-09-23 verification checkpoint the installation had **14 Active identities: 13 connected remote agents plus the local Manager, zero inactive and no duplicate names**. This is dated acceptance evidence, not a live metric or a guaranteed future host count. For reimaged hosts, resolve duplicate keys/identities deliberately and recheck the Manager list; do not blindly delete another host's identity.

## 3. Deploy Indexer and Dashboard through Argo CD

The tracked `argocd/applications/wazuh.yml` points at `argocd/resources/wazuh/` with namespace `wazuh`. Its kustomization includes sealed Indexer TLS/security credentials, Indexer config/services/StatefulSet/IngressRouteTCP and private Dashboard config/service/deployment/Ingress. Confirm your **intended environment branch**: this Application currently has `targetRevision: main`; merging tutorial changes into `dev` does **not** deploy them. Never silently retarget production during a workshop.

```bash
kubectl -n argocd get application wazuh -o wide
kubectl -n wazuh get statefulset,deploy,pod,svc,pvc
kubectl -n wazuh get events --sort-by=.lastTimestamp | tail -n 25
kubectl -n wazuh describe pvc
```

**Gate 2:** the Indexer StatefulSet is ready, its intended Cinder PVC is Bound, its TLS/authentication has been tested by an authorized client, and the Dashboard can authenticate over the private access path. `Pod Running`, TCP-open and `PVC Bound` are *not* proof of usable search, healthy shards or durable restore. Test indexer health, security plugin bootstrap and disk headroom with a credentialed client; never paste returned secret material into logs. Exercise a Pod restart and prove persistence before real event retention is assumed. Keep Indexer transport private and confirm Dashboard/API network paths rather than bypassing TLS validation.

## 4. Configure Filebeat only after Indexer readiness

The edge `wazuh_filebeat` role is deliberately two-stage: it installs Filebeat **7.10.2-2** and Wazuh 4.14.7 module/template while `wazuh_filebeat_configure: false` and `wazuh_filebeat_enabled: false`; only after a reachable private Indexer, Root CA, client certificate/key and Indexer credentials are available should the approved private variables enable configuration and delivery. The role stores the username/password in Filebeat keystore and tests configuration/output. Do not commit the keystore, cert private key or plaintext password.

```bash
cd ansible
ansible-playbook -i inventories/private/hosts.yml playbooks/edge.yml \
  --limit edge_nodes --tags wazuh_filebeat
# On edge, after private variables and certificates are provisioned:
sudo filebeat test config -c /etc/filebeat/filebeat.yml
sudo filebeat test output -c /etc/filebeat/filebeat.yml
sudo systemctl status filebeat --no-pager
sudo journalctl -u filebeat -n 80 --no-pager
```

**Gate 3:** generate/locate one harmless Wazuh alert, confirm its presence in Manager `alerts.json`, then find its identifier in a `wazuh-alerts-4.x-YYYY.MM.DD` index using an authenticated private query or Dashboard. A connected Filebeat output alone does not prove delivery; a Dashboard login alone does not prove current indexing. If Manager JSON exists but the Indexer has no document, inspect Filebeat keystore, permissions, CA chain, SAN/hostname, index template/module, publishing errors, cluster disk watermarks and date/time. Never disable certificate verification as a debugging shortcut.

## 5. Deploy Suricata as an **IDS**, not an unreviewed IPS

The tracked Suricata role installs **Suricata 8.0.x** from the OISF 8.0 COPR, disables the old 7.0 repo, applies a small override on top of vendor `suricata.yaml`, loads ET Open rules and the harmless local SID `9900001`, validates with `suricata -T`, and starts the service. The configured AF_PACKET interface defaults to the edge host's routed IPv4 interface; in the dated verification it was `edge/eth0`. It intentionally does **not** simultaneously capture `wg0`, avoiding duplicated observations of routed VPN traffic. Capture only traffic the selected interface can actually see; this is *not* a tap for every East–West Kubernetes packet.

```bash
cd ansible
ansible-playbook -i inventories/private/hosts.yml playbooks/edge.yml \
  --limit edge_nodes --tags suricata
# On edge:
suricata -V
sudo systemctl status suricata --no-pager
sudo journalctl -u suricata -n 60 --no-pager
sudo test -s /var/log/suricata/eve.json && echo 'EVE present'
sudo tail -n 3 /var/log/suricata/eve.json
```

Check effective `suricata_home_net` in *private* vars and that the configured capture interface, sysconfig and override agree. The EVE configuration includes alert, anomaly, HTTP, DNS, TLS, SSH, flow and stats records with Community ID. The role adds `wazuh` to the `suricata` group and manages a JSON `<localfile>` entry in `/var/ossec/etc/ossec.conf`, then validates the logcollector. It is important to verify both file modes and SELinux access if events are absent.

## 6. A controlled end-to-end detection

Perform only against an explicitly authorized **lab endpoint and approved source**; no exploit or broad scan is required. The repository local rule is an HTTP request with URI `/suricata-e2e-test`, SID `9900001`. Send one ordinary test HTTP request over the interface actually monitored and inspect the three evidence layers.

```bash
# From an authorized lab client, replace the hostname with the approved HTTP test endpoint:
curl -i http://APPROVED-LAB-HOST/suricata-e2e-test
# On edge:
sudo grep '9900001' /var/log/suricata/eve.json | tail -n 3
sudo grep '9900001' /var/ossec/logs/alerts/alerts.json | tail -n 3
# Search for the resulting alert ID in the authorized Wazuh Dashboard/Indexer.
```

**Gate 4:** correlate test time, source/destination, Suricata SID and Wazuh rule/alert ID across EVE, Manager JSON and indexed document. If EVE fires but Manager JSON does not, validate JSON localfile location, readable ownership, logcollector restart, decoder and rule level. If Manager JSON fires but Indexer does not, return to Gate 3. The dated 2026-09-23 test observed Suricata **8.0.7**, SID **9900001**, Wazuh rule **86601**, alert ID **1790160649.584653** indexed in **wazuh-alerts-4.x-2026.09.23**. That evidence proves one historical chain; it is not a synthetic event to reinsert into today's metrics.

## 7. Grafana, reliability and acceptance

Git-owned dashboards live in `argocd/resources/grafana/dashboards/wazuh-suricata-observability/`. Their own README separates real Traefik/Kubernetes/Indexer-container metrics from **missing** Wazuh Manager, Filebeat, Suricata-exporter and non-Kubernetes host exporters. A Wazuh event is not a Prometheus sample. Do not turn an absent scrape target into a green `0 alerts` panel. Do not embed raw EVE payloads, credentials, host identities, research data or unbounded rule IDs in Prometheus labels.

Acceptance record for each run: inventory/host and component versions; screenshot or redacted transcript of agent list; Suricata test configuration and effective capture interface; one authorized test's correlated SID/rule/alert/index; Indexer PVC and restore test; Filebeat delivery; private Dashboard reachability; Grafana panel provenance; and any failed gates with root-cause analysis. Redact IPs and identities where the exercise requires it. Retention, rotation, snapshot/restore and sensor/NAT identity attribution are separate hardening tasks; do not claim production readiness solely from this exercise.

## Failure patterns worth teaching

| Symptom | Start with | Avoid |
| --- | --- | --- |
| Manager active, agent missing | SG + edge nftables + route → 1514/1515 → enrollment/agent log | Opening all ports |
| Agent Active, no alert | Manager log, test event, rule threshold and alerts.json | Assuming dashboard is the Manager |
| Filebeat config passes, no indexed event | `test output`, TLS, keystore, template, Indexer disk and publish logs | `ssl.verification_mode: none` |
| Indexer pod Running, dashboard empty | authenticated cluster health, PVC capacity, index patterns, API credentials | Treating pod readiness as data health |
| Suricata service active, no EVE | capture interface, traffic path, HOME_NET, file ownership, SELinux, rules | Capturing wg0 and eth0 blindly |
| EVE alert exists, Wazuh alert absent | JSON localfile, logcollector validation, group access, decoder/rule | Fabricating Grafana alert counters |
| Dashboard folder missing | Argo targetRevision, sidecar label/annotation, folder provider | Manual Grafana import |

## ACE teaching adaptation

For an eventual one-week Automation and Cloud Engineering Challenge, split the exercise into bounded student milestones: architecture and threat model; IaC network/host deployment; agent/IDS enrollment; authenticated event pipeline; controlled verification and evidence pack. Give every team an isolated OpenStack project or scoped lab resources, unique ephemeral credentials, written rules of engagement, non-production test targets and a recovery path. Grade reproducibility, clear evidence, secure defaults and failure analysis—not volume of attacks or number of scary dashboards. QCC scientific workflows belong in `quantum-workflows`, and cross-repo challenge coordination belongs in an explicit programme-level issue; do not couple either challenge's future design to this deployment tutorial.
