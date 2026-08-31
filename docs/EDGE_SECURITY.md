# Edge Security Model

## Layers

```text
Internet
   |
   v
OpenStack security groups
   |
   v
edge
   |
   +-- nftables
   +-- WireGuard
   +-- Pi-hole
   +-- Wazuh
   +-- Suricata
```

## SSH

Temporary bootstrap:

```text
bootstrap_ssh_cidr -> edge:22
```

Normal administration:

```text
WireGuard -> edge:22
```

After WireGuard is proven, public bootstrap SSH can be removed.

## NAT

```text
10.60.0.0/24
      |
      v
     wg0
      |
      v
    edge
      |
 masquerade
      |
      v
external network
```

## DNS

Permit DNS from:

```text
mgmt_cidr
k8s_cidr
vpn_cidr
```

Do not expose Pi-hole DNS to the public Internet.

## Wazuh

Agents reach the manager on the private infrastructure network.

Do not expose the manager publicly.

## Suricata

Start in IDS mode.

Do not enable inline IPS until the exact traffic path has been tested.
