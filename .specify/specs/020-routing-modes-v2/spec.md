# 020: Routing Modes v2 (k2o-nethub)

> Specification for upgrading MVSM to k2o-nethub with new routing architecture

**Status:** Draft
**Created:** 2026-01-21
**Supersedes:** 003, 004, 005, 006

---

## Overview

Complete restructure of routing modes:
- Rename MVSM → NETHUB
- Three distinct modes based on platform
- Clear separation between RouterOS and standard WireGuard clients

## Routing Modes

| Mode | Platforms | Description |
|------|-----------|-------------|
| `dgw` | Non-ROS | Default Gateway - all traffic via tunnel, internet only |
| `selective` | Non-ROS | Specific networks via tunnel |
| `pbr` | RouterOS ONLY | Policy Based Routing with address-lists |

---

## Mode: `dgw` (Default Gateway)

**Platforms:** Windows, macOS, Linux, iOS, Android
**NOT for:** RouterOS

### Behavior
- All client traffic routed through WG tunnel
- Client has access ONLY to internet
- Client has NO access to other NETHUB networks
- DNS = WG server (10.254.0.1)

### Config (.conf)
```ini
[Interface]
PrivateKey = <key>
Address = 10.254.0.X/32          # /32 for isolation
DNS = 10.254.0.1

[Peer]
PublicKey = <hub_key>
Endpoint = hub.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

### Hub-side
- `allowed-address = {clientIP}/32` (only client IP, no networks)
- Masquerade for outbound traffic on WAN

---

## Mode: `selective`

**Platforms:** Windows, macOS, Linux, iOS, Android
**NOT for:** RouterOS

### Parameter
```routeros
:global nethubGenNetworks "192.168.10.0/24,10.20.0.0/16"
```

### Logic Flow

| nethubGenNetworks | Behavior |
|-------------------|----------|
| Empty (first run) | Warning + show command + EXIT |
| Empty (second run) | Generate minimal config (AllowedIPs = 10.254.0.1/32) |
| `"dgw"` | Switch to dgw mode |
| Valid networks | Generate config with specified networks |

### Config (.conf)
```ini
[Interface]
PrivateKey = <key>
Address = 10.254.0.X/24
DNS = 10.254.0.1

[Peer]
PublicKey = <hub_key>
Endpoint = hub.example.com:51820
AllowedIPs = 10.254.0.1/32, 192.168.10.0/24, 10.20.0.0/16
PersistentKeepalive = 25
```

---

## Mode: `pbr` (Policy Based Routing)

**Platforms:** RouterOS ONLY
**This is the ONLY mode for RouterOS**

### Address Lists

| List | Purpose |
|------|---------|
| `SRCviaWG` | Source addresses routed via WG |
| `DSTviaWG` | Destination addresses routed via WG |
| `SRCtoAVOIDviaWG` | Source addresses NOT routed via WG |
| `DSTtoAVOIDviaWG` | Destination addresses NOT routed via WG |

### Example Entries (disabled by default)

Generated config creates example entries in **disabled** state:
```routeros
/ip firewall address-list
add list=SRCviaWG address=192.168.100.0/24 disabled=yes comment="NETHUB | example: route this subnet via WG"
add list=DSTviaWG address=8.8.8.8 disabled=yes comment="NETHUB | example: route to this IP via WG"
add list=SRCtoAVOIDviaWG address=192.168.200.0/24 disabled=yes comment="NETHUB | example: exclude this subnet"
add list=DSTtoAVOIDviaWG address=1.1.1.1 disabled=yes comment="NETHUB | example: exclude this destination"
```

User enables/adds entries as needed. Examples serve as documentation.

### Behavior without addresses
- Communication ONLY wg-server ↔ wg-client
- No third-party traffic routing
- Examples are disabled — no impact until user enables them

### Generated .rsc Structure
```routeros
# WireGuard interface + peer
# IP address
# DNS = 10.254.0.1

# Address lists with DISABLED examples:
#   SRCviaWG, DSTviaWG (disabled examples)
#   SRCtoAVOIDviaWG, DSTtoAVOIDviaWG (disabled examples)

# Routing table: nethub-route
# Default route in policy table

# Mangle rules:
# 1. AVOID lists (higher priority - accept/passthrough)
# 2. VIA lists (mark-routing to nethub-route)

# Masquerade (only for out-interface=wg_nethub)
# Firewall input accept
```

### Masquerade Requirements

**Only for traffic going through the tunnel:**

Hub (masquerade WG traffic going to WAN):
```routeros
/ip firewall nat add chain=srcnat src-address=10.254.0.0/24 \
    out-interface-list=WAN action=masquerade comment="NETHUB | masq to WAN"
```

Client (masquerade LAN traffic going through WG):
```routeros
/ip firewall nat add chain=srcnat out-interface=wg_nethub \
    action=masquerade comment="NETHUB | masq to WG"
```

**Note:** Only traffic routed via `nethub-route` table exits through `wg_nethub`, so masquerade applies only to PBR-marked traffic.

---

## Renaming

### Variables
| Old | New |
|-----|-----|
| `mvsmHubName` | `nethubName` |
| `mvsmHubFQDN` | `nethubFQDN` |
| `mvsmWgPort` | `nethubWgPort` |
| `mvsmGenName` | `nethubGenName` |
| `mvsmGenPlatform` | `nethubGenPlatform` |
| `mvsmGenMode` | `nethubGenMode` |
| `mvsmGenDefaultGW` | REMOVED |
| `mvsmGenClientNets` | REMOVED |
| `mvsmGenHubNets` | `nethubGenNetworks` |

### Scripts
| Old | New |
|-----|-----|
| `mvsm-generate-client` | `nethub-generate-client` |
| `mvsm-client-list` | `nethub-client-list` |
| `mvsm-client-remove` | `nethub-client-remove` |
| `mvsm-status` | `nethub-status` |
| `mvsm-uninstall` | `nethub-uninstall` |

### Markers
| Old | New |
|-----|-----|
| `MVSM` | `NETHUB` |
| `wg_mvsm` | `wg_nethub` |
| `mvsm-route` | `nethub-route` |

### Output Files
| Platform | Mode | Filename |
|----------|------|----------|
| RouterOS | pbr | `nethub_{name}.rsc` |
| Non-ROS | dgw | `nethub_{name}_dgw.conf` |
| Non-ROS | selective | `nethub_{name}.conf` |
| Non-ROS | selective (empty) | `nethub_{name}_minimal.conf` |
| Linux | * | + `nethub_{name}.sh` |

---

## Validation Rules

```
IF platform = "ros" AND mode != "pbr":
    → Auto-set mode = "pbr"
    → Message: "RouterOS supports only PBR mode"

IF platform != "ros" AND mode = "pbr":
    → Error: "PBR mode is for RouterOS only"
    → Suggest: dgw or selective
```

---

## Migration from v4

| Old Mode | New Mode | Notes |
|----------|----------|-------|
| `hub-only` | `selective` (empty, 2nd run) | Minimal config |
| `full` | `dgw` | Non-ROS only |
| `selective` | `pbr` | ROS only, enhanced |
| `site-to-site` | `pbr` | Merged, use address-lists |

---

## Files Affected

| File | Action |
|------|--------|
| `mvsm_v4_server_deploy.rsc` | Full rewrite → `nethub_server_deploy.rsc` |
| `README.md` | Update documentation |
| `.specify/memory/constitution.md` | Update modes |
| `003-routing-hub-only/` | Archive |
| `004-routing-selective/` | Archive |
| `005-routing-full/` | Archive |
| `006-routing-site-to-site/` | Archive |
