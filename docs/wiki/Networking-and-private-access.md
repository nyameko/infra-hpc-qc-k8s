# Networking, private DNS and remote access

## Purpose and boundaries

The reference platform uses separate management, Kubernetes and WireGuard network roles; exact operational CIDRs, firewall rules, provider IDs and key material belong in protected Terraform/Ansible configuration. The public repository documents role names and architecture rather than a live attack map.

A client accessing a private service crosses **several controls**: local VPN peer and route, WireGuard edge, provider/Neutron security group, edge nftables forwarding, target host/firewall, Kubernetes service/ingress and application authentication. A successful handshake says nothing about application permissions. Never disable multiple controls at once to make a service reachable.

## DNS paths

Private service discovery is anchored by the edge resolver and Kubernetes CoreDNS configuration, with public domains and TLS certificates managed through explicit site DNS and ingress resources. Test lookup independently from connectivity:

```sh
# On an authorised host / VPN client:
ip route
getent hosts <PRIVATE_SERVICE_HOST>
# On an authorised edge administrator shell:
sudo wg show
sudo nft list ruleset
```

On a Kubernetes administrative host, `kubectl get pods -A` and relevant CoreDNS logs/ConfigMaps help distinguish resolution from routing. Do not dump a private hosts file or full peer table into a public issue.

## WireGuard provisioning

Quantum Platform collects public key material and authorized access intent; infrastructure reconciles peers in the supported Ansible/edge workflow. Neither a registered key nor a public account implies a working tunnel. Preserve a recovery/console route before modifying `nftables`, edge routes, DNS or allowed IPs. Validate `nft -c` before a firewall reload, and test traffic from both an authorized and deliberately unauthorized network.

## Incident checklist

If a client cannot connect: verify account and device, tunnel status, split routes, intended DNS server, resolver address, TLS name, service readiness and authorization. Record the failing hop and a redacted timestamp. Keep trust separate from network reachability.

Source guides: [network security](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/02-networking-and-security.md), [CoreDNS private zones](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/kubernetes-coredns-private-zones.md), [WireGuard reconciliation](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/tutorials/m3a-wireguard-peer-reconciliation.md) and [nftables fabric](https://github.com/nyameko/infra-hpc-qc-k8s/blob/main/docs/architecture/ace-fabric-nftables-m4a.md).