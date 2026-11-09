# SCC26 — share the EXISTING ACE A100 vLLM through an isolated student WireGuard tunnel

Status: **review-only; not deployed**. This design adds NO vLLM instance, NO GPU allocation, NO production LiteLLM keys, and NO changes to Quantum Platform, wg0 or wg-fabric.

## Existing authoritative service

The `gpu_inference` host is already managed by `ansible/playbooks/ace-inference.yml` and `vllm_server`. As of the checked `dev` configuration, the *configured* model is `Qwen/Qwen3.5-27B` with served ID `qwen3.5-27b` on port 8000. **Verify the live `/v1/models` response; a Git default is not proof of the running model**. The current vLLM `--api-key` is ONE backend key; never distribute it to student teams.

## Traffic and ownership

```
five independent student Kubernetes environments (Sebowa)
  -> each team's edge gateway (one WireGuard peer + limited SNAT)
     -> reachable team gateway's UDP listener (A100 dials OUT)
        -> A100 wg-students overlay address, TCP 8443
           -> standalone NGINX proxy, five independently revocable API keys
              -> EXISTING vLLM at 127.0.0.1:8000
```

The A100 has no floating IP. For this no-inbound-ACE variant, each Sebowa team edge must have a **reachable** UDP listener and permitted inbound security-group/host-firewall rule. A100 initiates its WireGuard handshakes via outbound UDP and maintains the NAT binding with keepalives. If the edges cannot accept inbound UDP, this topology is blocked: select an approved reachable shared Sebowa listener / relay instead, rather than opening production wg-fabric.

`AllowedIPs` for A100 peers must be **their respective single /32 tunnel addresses only**. The student edge's peer for the A100 must allow **only A100's overlay /32**, not a management, storage, Kubernetes or default CIDR. The separate nftables table on A100 rejects EVERY student-ingress destination except overlay-IP:8443 and rejects ALL student-to-other-interface forwarding. Host firewalld/SG rules can further deny the traffic; these must be checked without removing production policy.

The student proxy starts conservatively with **one concurrent inference request per team** and a **four-request aggregate student cap**, in addition to per-team request rate limiting. This bounds student demand but does not reserve GPU capacity or guarantee production M4 latency: compare production baseline before and after enabling students, and disable student proxy immediately if M4 service is degraded.

Do NOT assume that setting an extra WireGuard key automatically makes remote Kubernetes pods routable. The team edge must explicitly route ONLY the A100 overlay /32 and apply SNAT for the approved TCP 8443 flow, so the remote source equals that team's WireGuard peer /32. The edge must restrict forwarding to that destination/port and should restrict source workloads to its own student namespaces. Avoid full-subnet route advertisement and general tunnel forwarding.

### Example addresses only — NOT assigned live

| Actor | Illustrative tunnel IP |
| --- | --- |
| A100 | 10.62.26.1/32 |
| Team 1 | 10.62.26.11/32 |
| Team A | 10.62.26.12/32 |
| Collaborative Agents | 10.62.26.13/32 |
| Inference Fabric | 10.62.26.14/32 |
| Cloud HPL | 10.62.26.15/32 |

First verify the overlay does not overlap existing ACE/Sebowa or student private networks; replace all examples with protected inventory allocations.

## Rollout procedure

1. **Validate production baseline.** Identify the real A100 inventory host, its current vLLM model ID and backend key location (DO NOT print the key), host routing, nftables/firewalld, SELinux status, and reachable Sebowa UDP endpoints. Record `systemctl is-active vllm`, `ss -ltn`, `wg show`, firewall and route summaries. Do not restart vLLM.
2. **Generate keys privately.** On A100, create dedicated WireGuard private/public identity for `wg-students` (different from any production interface). Each student edge generates its own WireGuard identity. Store keys in private Ansible Vault/inventory, not Git. Generate FIVE independent strong model API keys and store each in the relevant team's SealedSecret.
3. **Populate private inventory**: `student_inference_enabled: true`, A100 overlay /32 and host IP, WireGuard private key, five peers with `team`, `public_key`, `peer_ip`, `endpoint`, `api_key`, and existing `vllm_server_bearer_token`. The role requires all five peers to avoid partially granting access by accident.
4. **Review `ansible/playbooks/ace-student-inference.yml`**; run syntax/check in your approved automation environment before executing with the protected inventory. This playbook applies ONLY `student_inference_access`; it does not invoke the existing vLLM or production fabric roles.
5. **Provision Sebowa edges**. Each edge's `wg-students` peer has `AllowedIPs=<A100-overlay-IP>/32`, a listening UDP port, an SG allowance, and destination-specific routing. Apply narrowly scoped team-workload -> A100-overlay:8443 forwarding and SNAT to its own tunnel /32. Do not add routes to ACE `10.50/10.51/10.60` networks.
6. **Enable A100 student role**. Confirm `wg show wg-students` latest handshake for each peer, `systemctl status scc26-model-proxy`, `nft list table inet scc26_student_inference`, and `ss -ltn` binding of TCP 8443 to the dedicated overlay IP.
7. **Negative and positive tests from actual student pods**: authenticated `GET /v1/models`, small `POST /v1/chat/completions`, invalid/missing key -> 401, unacceptable routes/SSH/vLLM-direct:8000 denied, revoked team key fails while other teams keep working, bounded concurrent requests. Check the existing production inference clients still work.
8. **Publish contract privately to each team**. `ACP_MODEL_BASE_URL=http://<A100-overlay-IP>:8443/v1`, `ACP_MODEL=<verified returned model ID>`, `ACP_MODEL_API_KEY=<team-specific credential from SealedSecret>`. Open only /32:8443 via relevant student network policies and gateway rules.
9. **Enable the blocked Hermes team(s) via a PR to their own `dev` branch after tests.** Purple Team 1 currently has `replicas: 0` until endpoint and secret are approved. Keep singleton `replicas: 1`; do not modify its persisted DB or replace its upstream ACP image just to connect a model.
10. **Inference Fabric** can benchmark the same shared service after a baseline is captured; explicitly record concurrency, contention, API latency, GPU usage and model identity.

### Per-team edge WireGuard example (illustrative only)

```ini
[Interface]
Address = 10.62.26.11/32
ListenPort = <REACHABLE_TEAM_UDP_PORT>
PrivateKey = <TEAM_PRIVATE_KEY>

[Peer]
PublicKey = <A100_WG_STUDENTS_PUBLIC_KEY>
AllowedIPs = 10.62.26.1/32
# No Endpoint here; the A100 initiates to this public Sebowa edge.
```

### Acceptance

- Production vLLM still serves its existing clients and same verified model.
- All five independent WireGuard handshakes work (or documented unreachable-gateway blockers).
- Exactly one TCP destination, the student proxy, is reachable from each student overlay peer.
- Direct student access to A100 port 8000, ACE management, Kubernetes, storage and other students is denied.
- All five restricted API keys work and an invalid/revoked key is rejected.
- No VPN private key, backend vLLM key or team bearer token enters a public repository or logs.
- Each team's ACP/Hermes has separate credentials, namespace, PostgreSQL and runtime state.
- Student Hermes restart/outage tests preserve task history; Inference Fabric has benchmark evidence.

### Rollback and failure notes

Disable only `scc26-model-proxy` and `wg-quick@wg-students` on the A100 (after notifying teams). Never stop `vllm`, `wg-fabric`, `wg0` or production LiteLLM. The student-specific nftables table is removed by the WireGuard PostDown hook. If the host crashes after PreUp but before PostDown, that table may remain and intentionally prevent unsafe tunnel reactivation; inspect before deleting the dedicated table, then retry. If another host firewall or SELinux blocks the new NGINX port/upstream, diagnose *specifically* and propose a narrowly scoped policy change; do not globally disable enforcement or flush firewalls. Keep ingress operator-reviewed, not auto-opened.

Note: WireGuard encrypts tunnel transport; the student HTTP API is intended only **inside** the private tunnel. Per-team API keys are independently revocable at the proxy; the production vLLM bearer token never leaves the A100.
