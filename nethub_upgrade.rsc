# ================================================================
# K2O-NETHUB - Upgrade Script
# MVSM v3/v4 → NETHUB v5.0
# ================================================================
#
# This script upgrades existing MVSM installation to NETHUB v5.0
# while preserving all peers, keys, and network settings.
#
# Features:
# - Detects MVSM or existing NETHUB installation
# - Preserves WireGuard interface private key (no client disruption)
# - Preserves all peers with their keys and IPs
# - Renames interface wg_mvsm → wg_nethub
# - Updates all comments MVSM → NETHUB
# - Deploys new management scripts v5.0
# - Preserves custom network/port settings
#
# Usage:
#   /import nethub_upgrade.rsc
#
# Author: t.me/olekovin
# License: MIT
#
# ================================================================

:local version "5.0"
:local newMarker "NETHUB"
:local oldMarker "MVSM"
:local newWgInt "wg_nethub"
:local oldWgInt "wg_mvsm"

:log info "$newMarker: ========================================"
:log info "$newMarker: Starting upgrade to v$version"
:log info "$newMarker: ========================================"

# ================================================================
# SECTION 1: DETECT INSTALLATION
# ================================================================

:put "Detecting existing installation..."

:local wgInterface ""
:local isUpgrade false
:local currentMarker ""

# Check for old MVSM
:if ([:len [/interface wireguard find where name=$oldWgInt]] > 0) do={
    :set wgInterface $oldWgInt
    :set isUpgrade true
    :set currentMarker $oldMarker
    :put "Found: MVSM installation (will upgrade)"
    :log info "$newMarker: Found MVSM installation"
}

# Check for existing NETHUB
:if ([:len [/interface wireguard find where name=$newWgInt]] > 0) do={
    :set wgInterface $newWgInt
    :set isUpgrade true
    :set currentMarker $newMarker
    :put "Found: NETHUB installation (will refresh scripts)"
    :log info "$newMarker: Found existing NETHUB"
}

# No installation found
:if ($wgInterface = "") do={
    :put "ERROR: No MVSM or NETHUB installation found."
    :put "Use nethub_server_deploy.rsc for fresh installation."
    :error "no installation"
}

# ================================================================
# SECTION 2: READ CURRENT CONFIGURATION
# ================================================================

:put "Reading current configuration..."

# Get WireGuard port
:local wgPort [/interface wireguard get [find where name=$wgInterface] listen-port]
:put "  Port: $wgPort"

# Get server IP from interface address
:local serverIP ""
:local serverNetwork ""
:foreach addr in=[/ip address find where interface=$wgInterface] do={
    :local fullAddr [/ip address get $addr address]
    :local slashPos [:find $fullAddr "/"]
    :set serverIP [:pick $fullAddr 0 $slashPos]
    # Calculate network (assuming /24)
    :local p1 [:find $serverIP "."]
    :local p2 [:find $serverIP "." ($p1+1)]
    :local p3 [:find $serverIP "." ($p2+1)]
    :set serverNetwork ([:pick $serverIP 0 ($p3+1)] . "0/24")
}
:put "  Server IP: $serverIP"
:put "  Network: $serverNetwork"

# Get server public key
:local serverPubKey [/interface wireguard get [find where name=$wgInterface] public-key]
:put "  Public Key: $serverPubKey"

# Try to get FQDN from old globals (priority: nethubFQDN > mvsmServerFQDN > mvsmHubFQDN)
:local serverFQDN "hub.example.com"
:do {
    :global mvsmHubFQDN
    :if ([:typeof $mvsmHubFQDN] != "nothing" && [:len $mvsmHubFQDN] > 0) do={
        :set serverFQDN $mvsmHubFQDN
    }
} on-error={}
:do {
    :global mvsmServerFQDN
    :if ([:typeof $mvsmServerFQDN] != "nothing" && [:len $mvsmServerFQDN] > 0) do={
        :set serverFQDN $mvsmServerFQDN
    }
} on-error={}
:do {
    :global nethubFQDN
    :if ([:typeof $nethubFQDN] != "nothing" && [:len $nethubFQDN] > 0 && $nethubFQDN != "hub.example.com") do={
        :set serverFQDN $nethubFQDN
    }
} on-error={}
:put "  FQDN: $serverFQDN"

# Get hub name
:local hubName "hub1"
:do {
    :global mvsmHubName
    :if ([:typeof $mvsmHubName] != "nothing") do={
        :set hubName $mvsmHubName
    }
} on-error={}
:do {
    :global nethubName
    :if ([:typeof $nethubName] != "nothing") do={
        :set hubName $nethubName
    }
} on-error={}
:put "  Hub Name: $hubName"

# Calculate client start from existing peers
:local clientStart 11
:do {
    :global nethubClientStart
    :if ([:typeof $nethubClientStart] != "nothing") do={
        :set clientStart $nethubClientStart
    }
} on-error={}

# ================================================================
# SECTION 3: BACKUP PEERS
# ================================================================

:put ""
:put "Backing up peers..."

:local peerCount 0
:foreach peer in=[/interface wireguard peers find where interface=$wgInterface] do={
    :local peerPubKey [/interface wireguard peers get $peer public-key]
    :local peerAllowed [/interface wireguard peers get $peer allowed-address]
    :local peerComment [/interface wireguard peers get $peer comment]
    :local peerName [/interface wireguard peers get $peer name]
    :set peerCount ($peerCount + 1)
    :put "  [$peerCount] $peerName - $peerAllowed"
}
:put "Total peers: $peerCount"

# ================================================================
# SECTION 4: RENAME INTERFACE (if needed)
# ================================================================

:if ($wgInterface = $oldWgInt) do={
    :put ""
    :put "Renaming interface $oldWgInt -> $newWgInt..."

    /interface wireguard set [find where name=$oldWgInt] name=$newWgInt comment="$newMarker | hub"
    :set wgInterface $newWgInt

    :log info "$newMarker: Interface renamed"
    :put "  Done"
} else={
    # Just update comment
    /interface wireguard set [find where name=$newWgInt] comment="$newMarker | hub"
}

# ================================================================
# SECTION 5: UPDATE PEER COMMENTS
# ================================================================

:put ""
:put "Updating peer comments..."

:foreach peer in=[/interface wireguard peers find where interface=$wgInterface] do={
    :local oldComment [/interface wireguard peers get $peer comment]
    :local newComment $oldComment

    # Replace MVSM with NETHUB in comment
    :if ([:find $oldComment $oldMarker] >= 0) do={
        # Simple replacement - find position and rebuild
        :local pos [:find $oldComment $oldMarker]
        :if ($pos >= 0) do={
            :set newComment ([:pick $oldComment 0 $pos] . $newMarker . [:pick $oldComment ($pos + [:len $oldMarker]) [:len $oldComment]])
        }
        /interface wireguard peers set $peer comment=$newComment
    }
}
:put "  Done"

# ================================================================
# SECTION 6: UPDATE IP ADDRESS COMMENTS
# ================================================================

:put ""
:put "Updating IP address comments..."

:foreach addr in=[/ip address find where interface=$wgInterface] do={
    /ip address set $addr comment="$newMarker | hub"
}
:put "  Done"

# ================================================================
# SECTION 7: UPDATE FIREWALL COMMENTS
# ================================================================

:put ""
:put "Updating firewall rules..."

# Filter rules
:foreach rule in=[/ip firewall filter find where comment~$oldMarker] do={
    :local oldComment [/ip firewall filter get $rule comment]
    :local pos [:find $oldComment $oldMarker]
    :if ($pos >= 0) do={
        :local newComment ([:pick $oldComment 0 $pos] . $newMarker . [:pick $oldComment ($pos + [:len $oldMarker]) [:len $oldComment]])
        /ip firewall filter set $rule comment=$newComment
    }
}

# NAT rules
:foreach rule in=[/ip firewall nat find where comment~$oldMarker] do={
    :local oldComment [/ip firewall nat get $rule comment]
    :local pos [:find $oldComment $oldMarker]
    :if ($pos >= 0) do={
        :local newComment ([:pick $oldComment 0 $pos] . $newMarker . [:pick $oldComment ($pos + [:len $oldMarker]) [:len $oldComment]])
        /ip firewall nat set $rule comment=$newComment
    }
}

# DNS static
:foreach entry in=[/ip dns static find where comment~$oldMarker] do={
    :local oldComment [/ip dns static get $entry comment]
    :local pos [:find $oldComment $oldMarker]
    :if ($pos >= 0) do={
        :local newComment ([:pick $oldComment 0 $pos] . $newMarker . [:pick $oldComment ($pos + [:len $oldMarker]) [:len $oldComment]])
        /ip dns static set $entry comment=$newComment
    }
}

:put "  Done"

# ================================================================
# SECTION 8: REMOVE OLD SCRIPTS
# ================================================================

:put ""
:put "Removing old scripts..."

:do { /system script remove [find where name~"mvsm-"] } on-error={}
:do { /system script remove [find where name~"nethub-"] } on-error={}
:do { /system scheduler remove [find where name~"mvsm-"] } on-error={}
:do { /system scheduler remove [find where name~"nethub-"] } on-error={}

:put "  Done"

# ================================================================
# SECTION 9: DEPLOY NEW SCRIPTS
# ================================================================

:log info "$newMarker: Deploying management scripts v$version..."
:put ""
:put "Deploying new scripts..."

# Store globals for scripts
:global nethubName $hubName
:global nethubFQDN $serverFQDN
:global nethubWgPort $wgPort
:global nethubNetwork $serverNetwork
:global nethubServerIP $serverIP
:global nethubClientStart $clientStart
:global nethubServerPubKey $serverPubKey

# ----- nethub-generate-client -----
:local genSrc ""
:set genSrc ($genSrc . "# NETHUB Client Generator v5.0\r\n")
:set genSrc ($genSrc . ":global nethubName; :global nethubFQDN; :global nethubWgPort\r\n")
:set genSrc ($genSrc . ":global nethubServerIP; :global nethubServerPubKey; :global nethubNetwork; :global nethubClientStart\r\n")
:set genSrc ($genSrc . ":global nethubGenName; :global nethubGenPlatform; :global nethubGenMode; :global nethubGenNetworks; :global nethubGenAdmin\r\n")
:set genSrc ($genSrc . ":global nethubSelectiveWarned\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . ":local marker \"NETHUB\"\r\n")
:set genSrc ($genSrc . ":local wgInt \"wg_nethub\"\r\n")
:set genSrc ($genSrc . ":local clientName \$nethubGenName\r\n")
:set genSrc ($genSrc . ":local platform \$nethubGenPlatform\r\n")
:set genSrc ($genSrc . ":local mode \$nethubGenMode\r\n")
:set genSrc ($genSrc . ":local networks \$nethubGenNetworks\r\n")
:set genSrc ($genSrc . ":local isAdmin (\$nethubGenAdmin = \"yes\" || \$nethubGenAdmin = \"true\" || \$nethubGenAdmin = true)\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Defaults\r\n")
:set genSrc ($genSrc . ":if ([:len \$platform] = 0) do={ :set platform \"ros\" }\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Platform validation and mode defaults\r\n")
:set genSrc ($genSrc . ":if (\$platform = \"ros\") do={\r\n")
:set genSrc ($genSrc . "    :if ([:len \$mode] = 0 || \$mode != \"pbr\") do={\r\n")
:set genSrc ($genSrc . "        :if ([:len \$mode] > 0 && \$mode != \"pbr\") do={\r\n")
:set genSrc ($genSrc . "            :put \"NOTE: RouterOS supports only PBR mode. Switching to pbr.\"\r\n")
:set genSrc ($genSrc . "        }\r\n")
:set genSrc ($genSrc . "        :set mode \"pbr\"\r\n")
:set genSrc ($genSrc . "    }\r\n")
:set genSrc ($genSrc . "} else={\r\n")
:set genSrc ($genSrc . "    :if (\$mode = \"pbr\") do={\r\n")
:set genSrc ($genSrc . "        :put \"ERROR: PBR mode is for RouterOS only.\"\r\n")
:set genSrc ($genSrc . "        :put \"Use 'dgw' for full VPN or 'selective' for specific networks.\"\r\n")
:set genSrc ($genSrc . "        :error \"invalid mode\"\r\n")
:set genSrc ($genSrc . "    }\r\n")
:set genSrc ($genSrc . "    :if ([:len \$mode] = 0) do={ :set mode \"selective\" }\r\n")
:set genSrc ($genSrc . "}\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Usage\r\n")
:set genSrc ($genSrc . ":if ([:len \$clientName] = 0) do={\r\n")
:set genSrc ($genSrc . "    :put \"Usage:\"\r\n")
:set genSrc ($genSrc . "    :put \"  :global nethubGenName \\\"mysite\\\"\"\r\n")
:set genSrc ($genSrc . "    :put \"  :global nethubGenPlatform \\\"ros\\\"       # ros/win/mac/linux/ios/android\"\r\n")
:set genSrc ($genSrc . "    :put \"  :global nethubGenMode \\\"pbr\\\"          # pbr (ros) / dgw,selective (other)\"\r\n")
:set genSrc ($genSrc . "    :put \"  :global nethubGenNetworks \\\"\\\"         # For selective: networks or 'dgw'\"\r\n")
:set genSrc ($genSrc . "    :put \"  :global nethubGenAdmin \\\"yes\\\"         # Optional: allow hub network access\"\r\n")
:set genSrc ($genSrc . "    :put \"  /system script run nethub-generate-client\"\r\n")
:set genSrc ($genSrc . "    :put \"\"\r\n")
:set genSrc ($genSrc . "    :put \"Modes:\"\r\n")
:set genSrc ($genSrc . "    :put \"  pbr       - RouterOS only, policy-based routing with address-lists\"\r\n")
:set genSrc ($genSrc . "    :put \"  dgw       - Non-ROS, all traffic via tunnel (internet only, +admin=hub access)\"\r\n")
:set genSrc ($genSrc . "    :put \"  selective - Non-ROS, specific networks via tunnel (+admin=include hub network)\"\r\n")
:set genSrc ($genSrc . "    :error \"Missing client name\"\r\n")
:set genSrc ($genSrc . "}\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Check duplicate\r\n")
:set genSrc ($genSrc . ":if ([:len [/interface wireguard peers find where interface=\$wgInt comment~\$clientName]] > 0) do={\r\n")
:set genSrc ($genSrc . "    :put \"ERROR: Client '\$clientName' exists. Use nethub-client-remove first.\"\r\n")
:set genSrc ($genSrc . "    :error \"exists\"\r\n")
:set genSrc ($genSrc . "}\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Selective mode logic for non-ROS\r\n")
:set genSrc ($genSrc . ":if (\$platform != \"ros\" && \$mode = \"selective\") do={\r\n")
:set genSrc ($genSrc . "    :if (\$networks = \"dgw\") do={\r\n")
:set genSrc ($genSrc . "        :set mode \"dgw\"\r\n")
:set genSrc ($genSrc . "        :put \"NOTE: Switching to DGW mode (all traffic via tunnel).\"\r\n")
:set genSrc ($genSrc . "    } else={\r\n")
:set genSrc ($genSrc . "        :if ([:len \$networks] = 0) do={\r\n")
:set genSrc ($genSrc . "            :if ([:typeof \$nethubSelectiveWarned] = \"nothing\") do={\r\n")
:set genSrc ($genSrc . "                :global nethubSelectiveWarned true\r\n")
:set genSrc ($genSrc . "                :put \"WARNING: No networks specified for selective mode.\"\r\n")
:set genSrc ($genSrc . "                :put \"\"\r\n")
:set genSrc ($genSrc . "                :put \"Add networks:\"\r\n")
:set genSrc ($genSrc . "                :put \"  :global nethubGenNetworks \\\"192.168.10.0/24,10.20.0.0/16\\\"\"\r\n")
:set genSrc ($genSrc . "                :put \"\"\r\n")
:set genSrc ($genSrc . "                :put \"Or use DGW mode (all traffic):\"\r\n")
:set genSrc ($genSrc . "                :put \"  :global nethubGenNetworks \\\"dgw\\\"\"\r\n")
:set genSrc ($genSrc . "                :put \"\"\r\n")
:set genSrc ($genSrc . "                :put \"Run again to create minimal config (server access only).\"\r\n")
:set genSrc ($genSrc . "                :error \"no networks\"\r\n")
:set genSrc ($genSrc . "            } else={\r\n")
:set genSrc ($genSrc . "                :put \"Creating MINIMAL config (server access only).\"\r\n")
:set genSrc ($genSrc . "                :set nethubSelectiveWarned\r\n")
:set genSrc ($genSrc . "            }\r\n")
:set genSrc ($genSrc . "        }\r\n")
:set genSrc ($genSrc . "    }\r\n")
:set genSrc ($genSrc . "}\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Calculate IP\r\n")
:set genSrc ($genSrc . ":local peerCount [:len [/interface wireguard peers find where interface=\$wgInt]]\r\n")
:set genSrc ($genSrc . ":local clientNum (\$peerCount + \$nethubClientStart)\r\n")
:set genSrc ($genSrc . ":local p1 [:find \$nethubServerIP \".\"]\r\n")
:set genSrc ($genSrc . ":local p2 [:find \$nethubServerIP \".\" (\$p1+1)]\r\n")
:set genSrc ($genSrc . ":local p3 [:find \$nethubServerIP \".\" (\$p2+1)]\r\n")
:set genSrc ($genSrc . ":local clientIP ([:pick \$nethubServerIP 0 (\$p3+1)] . \$clientNum)\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . ":local adminStr \"\"; :if (\$isAdmin) do={ :set adminStr \", admin\" }\r\n")
:set genSrc ($genSrc . ":put (\"Generating: \$clientName (\" . \$platform . \", \" . \$mode . \$adminStr . \")\")\r\n")
:set genSrc ($genSrc . ":put \"  IP: \$clientIP\"\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Generate keypair\r\n")
:set genSrc ($genSrc . "/interface wireguard add name=\"nethub-temp\"\r\n")
:set genSrc ($genSrc . ":delay 500ms\r\n")
:set genSrc ($genSrc . ":local privKey [/interface wireguard get \"nethub-temp\" private-key]\r\n")
:set genSrc ($genSrc . ":local pubKey [/interface wireguard get \"nethub-temp\" public-key]\r\n")
:set genSrc ($genSrc . "/interface wireguard remove \"nethub-temp\"\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Peer comment stores config\r\n")
:set genSrc ($genSrc . ":local adminMark \"\"; :if (\$isAdmin) do={ :set adminMark \"|admin\" }\r\n")
:set genSrc ($genSrc . ":local peerComment (\"\$marker|\$clientName|\$platform|\$mode\" . \$adminMark)\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Allowed addresses on hub (only client IP for isolation in dgw mode)\r\n")
:set genSrc ($genSrc . ":local peerAllowed \"\$clientIP/32\"\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Register peer\r\n")
:set genSrc ($genSrc . "/interface wireguard peers add interface=\$wgInt public-key=\$pubKey allowed-address=\$peerAllowed comment=\$peerComment\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# DNS\r\n")
:set genSrc ($genSrc . ":local dnsName \"\$clientName.\$nethubName.local\"\r\n")
:set genSrc ($genSrc . ":do { /ip dns static remove [find where name=\$dnsName] } on-error={}\r\n")
:set genSrc ($genSrc . "/ip dns static add name=\$dnsName address=\$clientIP comment=\"\$marker | \$clientName\"\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . ":local ts [/system clock get date]\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# === Generate RouterOS PBR config ===\r\n")
:set genSrc ($genSrc . ":if (\$platform = \"ros\") do={\r\n")
:set genSrc ($genSrc . "    :local cfg \"# NETHUB Client: \$clientName\\r\\n\"\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Hub: \$nethubName (\$nethubFQDN)\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Mode: pbr | Generated: \$ts\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local wg \\\"wg_nethub\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local m \\\"NETHUB\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local pk \\\"\" . \$privKey . \"\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local hub \\\"\" . \$nethubServerPubKey . \"\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local ep \\\"\" . \$nethubFQDN . \"\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local port \" . \$nethubWgPort . \"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local ip \\\"\" . \$clientIP . \"/24\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local dns \\\"\" . \$nethubServerIP . \"\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local net \\\"\" . \$nethubNetwork . \"\\\"\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":log info \\\"NETHUB: Deploying client...\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /interface wireguard peers remove [find comment~\\\"\\\$m\\\"] } on-error={}\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /interface wireguard remove [find name=\\\$wg] } on-error={}\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/interface wireguard add name=\\\$wg private-key=\\\$pk mtu=1420 comment=\\\"\\\$m\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":delay 500ms\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/interface wireguard peers add interface=\\\$wg public-key=\\\$hub endpoint-address=\\\$ep endpoint-port=\\\$port allowed-address=\\\$net persistent-keepalive=25s comment=\\\"\\\$m | hub\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /ip address remove [find comment~\\\$m] } on-error={}\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip address add address=\\\$ip interface=\\\$wg comment=\\\"\\\$m\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip dns set servers=\\\$dns\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# ===== Policy Based Routing Setup =====\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Cleanup old PBR config\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /ip firewall address-list remove [find list~\\\"viaWG\\\" or list~\\\"toAVOIDviaWG\\\"] } on-error={}\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /ip firewall mangle remove [find comment~\\\$m] } on-error={}\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /ip route remove [find routing-table=nethub-route] } on-error={}\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /routing table remove nethub-route } on-error={}\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Example address-list entries (disabled by default)\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip firewall address-list add list=SRCviaWG address=192.168.100.0/24 disabled=yes comment=\\\"\\\$m | example: route this subnet via WG\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip firewall address-list add list=DSTviaWG address=8.8.8.8 disabled=yes comment=\\\"\\\$m | example: route to this IP via WG\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip firewall address-list add list=SRCtoAVOIDviaWG address=192.168.200.0/24 disabled=yes comment=\\\"\\\$m | example: exclude this subnet\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip firewall address-list add list=DSTtoAVOIDviaWG address=1.1.1.1 disabled=yes comment=\\\"\\\$m | example: exclude this destination\\\"\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Routing table with FIB\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/routing table add name=nethub-route fib\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip route add dst-address=0.0.0.0/0 gateway=\\\$wg routing-table=nethub-route comment=\\\"\\\$m\\\"\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Mangle: AVOID lists (higher priority - process first)\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip firewall mangle add chain=prerouting src-address-list=SRCtoAVOIDviaWG action=accept passthrough=yes comment=\\\"\\\$m | skip-src\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip firewall mangle add chain=prerouting dst-address-list=DSTtoAVOIDviaWG action=accept passthrough=yes comment=\\\"\\\$m | skip-dst\\\"\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Mangle: VIA lists (mark for routing through WG)\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip firewall mangle add chain=prerouting src-address-list=SRCviaWG action=mark-routing new-routing-mark=nethub-route passthrough=no comment=\\\"\\\$m | src-via\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip firewall mangle add chain=prerouting dst-address-list=DSTviaWG action=mark-routing new-routing-mark=nethub-route passthrough=no comment=\\\"\\\$m | dst-via\\\"\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Masquerade (only for traffic going through WG)\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /ip firewall nat remove [find comment~\\\$m] } on-error={}\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/ip firewall nat add chain=srcnat out-interface=\\\$wg action=masquerade comment=\\\"\\\$m | masq to WG\\\"\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Firewall\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /ip firewall filter remove [find comment~\\\$m] } on-error={}\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":local d [/ip firewall filter find chain=input action=drop]\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":if ([:len \\\$d] > 0) do={ /ip firewall filter add chain=input action=accept in-interface=\\\$wg comment=\\\"\\\$m\\\" place-before=[:pick \\\$d 0] } else={ /ip firewall filter add chain=input action=accept in-interface=\\\$wg comment=\\\"\\\$m\\\" }\\r\\n\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"# Scripts\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":do { /system script remove [find name~\\\"nethub-\\\"] } on-error={}\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/system script add name=\\\"nethub-status\\\" comment=\\\"\\\$m\\\" source=\\\":local p [/interface wireguard peers find interface=wg_nethub]; :if ([:len \\\\\\\$p] > 0) do={ :put \\\\\\\"WG: online\\\\\\\"; :put [/interface wireguard peers get [:pick \\\\\\\$p 0] last-handshake] } else={ :put \\\\\\\"WG: offline\\\\\\\" }; :put \\\\\\\"Mode: pbr\\\\\\\"\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"/system script add name=\\\"nethub-uninstall\\\" comment=\\\"\\\$m\\\" source=\\\":global u; :if ([:typeof \\\\\\\$u]=\\\\\\\"nothing\\\\\\\") do={ :set u 1; :put \\\\\\\"Run 2 more times\\\\\\\" } else={ :set u (\\\\\\\$u+1); :if (\\\\\\\$u>=3) do={ :do { /interface wireguard remove wg_nethub } on-error={}; :do { /ip route remove [find comment~\\\\\\\"NETHUB\\\\\\\"] } on-error={}; :do { /ip route remove [find routing-table=nethub-route] } on-error={}; :do { /routing table remove nethub-route } on-error={}; :do { /ip address remove [find comment~\\\\\\\"NETHUB\\\\\\\"] } on-error={}; :do { /ip firewall filter remove [find comment~\\\\\\\"NETHUB\\\\\\\"] } on-error={}; :do { /ip firewall nat remove [find comment~\\\\\\\"NETHUB\\\\\\\"] } on-error={}; :do { /ip firewall mangle remove [find comment~\\\\\\\"NETHUB\\\\\\\"] } on-error={}; :do { /ip firewall address-list remove [find list~\\\\\\\"viaWG\\\\\\\" or list~\\\\\\\"toAVOIDviaWG\\\\\\\"] } on-error={}; :do { /system script remove [find name~\\\\\\\"nethub-\\\\\\\"] } on-error={}; :set u; :put \\\\\\\"Done\\\\\\\" } else={ :put (\\\\\\\"Run \\\\\\\" . (3-\\\\\\\$u) . \\\\\\\" more\\\\\\\") } }\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \"\\r\\n:log info \\\"NETHUB: Client deployed!\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":put \\\"\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":put \\\"NETHUB PBR deployed. Add addresses to control routing:\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":put \\\"  /ip firewall address-list add list=SRCviaWG address=192.168.x.x/24\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":put \\\"  /ip firewall address-list add list=DSTviaWG address=8.8.8.8\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":put \\\"\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":put \\\"To EXCLUDE from WG routing:\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":put \\\"  /ip firewall address-list add list=DSTtoAVOIDviaWG address=x.x.x.x\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":put \\\"\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :set cfg (\$cfg . \":put \\\"Scripts: nethub-status, nethub-uninstall\\\"\\r\\n\")\r\n")
:set genSrc ($genSrc . "    :local fn \"nethub_\$clientName\"\r\n")
:set genSrc ($genSrc . "    /file print file=\$fn\r\n")
:set genSrc ($genSrc . "    :delay 500ms\r\n")
:set genSrc ($genSrc . "    /file set [find name~\$fn] contents=\$cfg\r\n")
:set genSrc ($genSrc . "    /file set [find name~\$fn] name=(\$fn . \".rsc\")\r\n")
:set genSrc ($genSrc . "    :put \"Config: \$fn.rsc\"\r\n")
:set genSrc ($genSrc . "}\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# === Generate standard .conf for non-ROS ===\r\n")
:set genSrc ($genSrc . ":if (\$platform != \"ros\") do={\r\n")
:set genSrc ($genSrc . "    :local clientAddr\r\n")
:set genSrc ($genSrc . "    :local allowedIPs\r\n")
:set genSrc ($genSrc . "    :local suffix\r\n")
:set genSrc ($genSrc . "    \r\n")
:set genSrc ($genSrc . "    :if (\$mode = \"dgw\") do={\r\n")
:set genSrc ($genSrc . "        :if (\$isAdmin) do={\r\n")
:set genSrc ($genSrc . "            # DGW Admin: /24 for hub network access, all traffic\r\n")
:set genSrc ($genSrc . "            :set clientAddr \"\$clientIP/24\"\r\n")
:set genSrc ($genSrc . "            :set allowedIPs \"0.0.0.0/0, ::/0\"\r\n")
:set genSrc ($genSrc . "            :set suffix \"_admin\"\r\n")
:set genSrc ($genSrc . "        } else={\r\n")
:set genSrc ($genSrc . "            # DGW: /32 for isolation, all traffic\r\n")
:set genSrc ($genSrc . "            :set clientAddr \"\$clientIP/32\"\r\n")
:set genSrc ($genSrc . "            :set allowedIPs \"0.0.0.0/0, ::/0\"\r\n")
:set genSrc ($genSrc . "            :set suffix \"_dgw\"\r\n")
:set genSrc ($genSrc . "        }\r\n")
:set genSrc ($genSrc . "    } else={\r\n")
:set genSrc ($genSrc . "        # Selective\r\n")
:set genSrc ($genSrc . "        :set clientAddr \"\$clientIP/24\"\r\n")
:set genSrc ($genSrc . "        :local hubNet \"\"; :if (\$isAdmin) do={ :set hubNet \", \$nethubNetwork\" }\r\n")
:set genSrc ($genSrc . "        :if ([:len \$networks] = 0) do={\r\n")
:set genSrc ($genSrc . "            # Minimal config - server only (+ hub network if admin)\r\n")
:set genSrc ($genSrc . "            :set allowedIPs (\"\$nethubServerIP/32\" . \$hubNet)\r\n")
:set genSrc ($genSrc . "            :if (\$isAdmin) do={ :set suffix \"_admin\" } else={ :set suffix \"_minimal\" }\r\n")
:set genSrc ($genSrc . "        } else={\r\n")
:set genSrc ($genSrc . "            # With networks (+ hub network if admin)\r\n")
:set genSrc ($genSrc . "            :set allowedIPs (\"\$nethubServerIP/32, \$networks\" . \$hubNet)\r\n")
:set genSrc ($genSrc . "            :if (\$isAdmin) do={ :set suffix \"_admin\" } else={ :set suffix \"\" }\r\n")
:set genSrc ($genSrc . "        }\r\n")
:set genSrc ($genSrc . "    }\r\n")
:set genSrc ($genSrc . "    \r\n")
:set genSrc ($genSrc . "    :local cfg \"[Interface]\\r\\nPrivateKey = \$privKey\\r\\nAddress = \$clientAddr\\r\\nDNS = \$nethubServerIP\\r\\n\\r\\n[Peer]\\r\\nPublicKey = \$nethubServerPubKey\\r\\nEndpoint = \$nethubFQDN:\$nethubWgPort\\r\\nAllowedIPs = \$allowedIPs\\r\\nPersistentKeepalive = 25\\r\\n\"\r\n")
:set genSrc ($genSrc . "    \r\n")
:set genSrc ($genSrc . "    :local fn \"nethub_\$clientName\$suffix\"\r\n")
:set genSrc ($genSrc . "    /file print file=\$fn\r\n")
:set genSrc ($genSrc . "    :delay 500ms\r\n")
:set genSrc ($genSrc . "    /file set [find name~\$fn] contents=\$cfg\r\n")
:set genSrc ($genSrc . "    /file set [find name~\$fn] name=(\$fn . \".conf\")\r\n")
:set genSrc ($genSrc . "    :put \"Config: \$fn.conf\"\r\n")
:set genSrc ($genSrc . "    \r\n")
:set genSrc ($genSrc . "    # Linux shell script\r\n")
:set genSrc ($genSrc . "    :if (\$platform = \"linux\") do={\r\n")
:set genSrc ($genSrc . "        :local sh \"#!/bin/bash\\r\\nset -e\\r\\nCONF=/etc/wireguard/nethub.conf\\r\\nsudo tee \\\\\\\$CONF > /dev/null << 'EOF'\\r\\n\$cfg\\r\\nEOF\\r\\nsudo wg-quick up nethub\\r\\necho Connected\\r\\n\"\r\n")
:set genSrc ($genSrc . "        :local sn \"nethub_\$clientName\$suffix\"\r\n")
:set genSrc ($genSrc . "        /file print file=(\$sn . \"_sh\")\r\n")
:set genSrc ($genSrc . "        :delay 300ms\r\n")
:set genSrc ($genSrc . "        /file set [find name~(\$sn . \"_sh\")] contents=\$sh\r\n")
:set genSrc ($genSrc . "        /file set [find name~(\$sn . \"_sh\")] name=(\$sn . \".sh\")\r\n")
:set genSrc ($genSrc . "        :put \"Script: \$sn.sh\"\r\n")
:set genSrc ($genSrc . "    }\r\n")
:set genSrc ($genSrc . "}\r\n")
:set genSrc ($genSrc . "\r\n")
:set genSrc ($genSrc . "# Cleanup globals\r\n")
:set genSrc ($genSrc . ":set nethubGenName; :set nethubGenPlatform; :set nethubGenMode; :set nethubGenNetworks; :set nethubGenAdmin\r\n")
:set genSrc ($genSrc . ":put \"Client '\$clientName' created!\"\r\n")
:set genSrc ($genSrc . ":log info \"NETHUB: Generated \$clientName\"\r\n")

/system script add name="nethub-generate-client" source=$genSrc comment="$newMarker | generate"
:put "  [+] nethub-generate-client"

# ----- nethub-client-list -----
:local listSrc ""
:set listSrc ($listSrc . ":global nethubName\r\n")
:set listSrc ($listSrc . ":put \"NETHUB Clients (\$nethubName)\"\r\n")
:set listSrc ($listSrc . ":put \"========================================\"\r\n")
:set listSrc ($listSrc . ":local peers [/interface wireguard peers find interface=wg_nethub]\r\n")
:set listSrc ($listSrc . ":foreach p in=\$peers do={\r\n")
:set listSrc ($listSrc . "    :local c [/interface wireguard peers get \$p comment]\r\n")
:set listSrc ($listSrc . "    :local ip [/interface wireguard peers get \$p allowed-address]\r\n")
:set listSrc ($listSrc . "    :local hs [/interface wireguard peers get \$p last-handshake]\r\n")
:set listSrc ($listSrc . "    :local st \"offline\"\r\n")
:set listSrc ($listSrc . "    :if (([:len \$hs] > 0) and (\$hs != \"never\") and ([:find \$hs \"d\"] < 0)) do={\r\n")
:set listSrc ($listSrc . "        :local c1 [:find \$hs \":\"]; :local c2 -1; :local secs 9999\r\n")
:set listSrc ($listSrc . "        :if (\$c1 >= 0) do={ :set c2 [:find \$hs \":\" (\$c1+1)] }\r\n")
:set listSrc ($listSrc . "        :if (\$c1 < 0) do={ :set secs [:tonum \$hs] }\r\n")
:set listSrc ($listSrc . "        :if ((\$c1 >= 0) and (\$c2 < 0)) do={ :set secs ([:tonum [:pick \$hs 0 \$c1]]*60 + [:tonum [:pick \$hs (\$c1+1) [:len \$hs]]]) }\r\n")
:set listSrc ($listSrc . "        :if (\$c2 >= 0) do={ :set secs ([:tonum [:pick \$hs 0 \$c1]]*3600 + [:tonum [:pick \$hs (\$c1+1) \$c2]]*60 + [:tonum [:pick \$hs (\$c2+1) [:len \$hs]]]) }\r\n")
:set listSrc ($listSrc . "        :if (\$secs < 180) do={ :set st \"ONLINE\" }\r\n")
:set listSrc ($listSrc . "    }\r\n")
:set listSrc ($listSrc . "    :put \"\$c\"\r\n")
:set listSrc ($listSrc . "    :put \"  IP: \$ip | \$st\"\r\n")
:set listSrc ($listSrc . "}\r\n")
:set listSrc ($listSrc . ":put \"========================================\"\r\n")
:set listSrc ($listSrc . ":put (\"Total: \" . [:len \$peers])\r\n")

/system script add name="nethub-client-list" source=$listSrc comment="$newMarker | list"
:put "  [+] nethub-client-list"

# ----- nethub-client-remove -----
:local rmSrc ""
:set rmSrc ($rmSrc . ":global nethubName; :global nethubRemoveName\r\n")
:set rmSrc ($rmSrc . ":if ([:len \$nethubRemoveName] = 0) do={\r\n")
:set rmSrc ($rmSrc . "    :put \"Usage: :global nethubRemoveName \\\"clientname\\\"; /system script run nethub-client-remove\"\r\n")
:set rmSrc ($rmSrc . "    :error \"Missing name\"\r\n")
:set rmSrc ($rmSrc . "}\r\n")
:set rmSrc ($rmSrc . ":local peer [/interface wireguard peers find where interface=wg_nethub (name~\$nethubRemoveName or comment~\$nethubRemoveName)]\r\n")
:set rmSrc ($rmSrc . ":if ([:len \$peer] = 0) do={ :put \"Not found\"; :error \"not found\" }\r\n")
:set rmSrc ($rmSrc . ":put \"Removing \$nethubRemoveName...\"\r\n")
:set rmSrc ($rmSrc . "/interface wireguard peers remove \$peer\r\n")
:set rmSrc ($rmSrc . ":do { /ip route remove [find comment~\$nethubRemoveName] } on-error={}\r\n")
:set rmSrc ($rmSrc . ":do { /ip dns static remove [find name~\$nethubRemoveName] } on-error={}\r\n")
:set rmSrc ($rmSrc . ":do { /file remove [find name~\"nethub_\$nethubRemoveName\"] } on-error={}\r\n")
:set rmSrc ($rmSrc . ":set nethubRemoveName\r\n")
:set rmSrc ($rmSrc . ":put \"Done\"\r\n")
:set rmSrc ($rmSrc . ":log info \"NETHUB: Removed \$nethubRemoveName\"\r\n")

/system script add name="nethub-client-remove" source=$rmSrc comment="$newMarker | remove"
:put "  [+] nethub-client-remove"

# ----- nethub-status -----
:local statusSrc ""
:set statusSrc ($statusSrc . ":global nethubName; :global nethubFQDN; :global nethubWgPort; :global nethubServerPubKey\r\n")
:set statusSrc ($statusSrc . ":put \"NETHUB Hub (\$nethubName)\"\r\n")
:set statusSrc ($statusSrc . ":put \"========================================\"\r\n")
:set statusSrc ($statusSrc . ":put \"WG:   wg_nethub (:\$nethubWgPort/UDP)\"\r\n")
:set statusSrc ($statusSrc . ":put \"FQDN: \$nethubFQDN\"\r\n")
:set statusSrc ($statusSrc . ":put \"Key:  \$nethubServerPubKey\"\r\n")
:set statusSrc ($statusSrc . ":local peers [/interface wireguard peers find interface=wg_nethub]\r\n")
:set statusSrc ($statusSrc . ":local on 0\r\n")
:set statusSrc ($statusSrc . ":foreach p in=\$peers do={\r\n")
:set statusSrc ($statusSrc . "    :local h [/interface wireguard peers get \$p last-handshake]\r\n")
:set statusSrc ($statusSrc . "    :if (([:len \$h]>0) and (\$h!=\"never\") and ([:find \$h \"d\"]<0)) do={\r\n")
:set statusSrc ($statusSrc . "        :local c1 [:find \$h \":\"]; :local c2 -1; :local secs 9999\r\n")
:set statusSrc ($statusSrc . "        :if (\$c1>=0) do={ :set c2 [:find \$h \":\" (\$c1+1)] }\r\n")
:set statusSrc ($statusSrc . "        :if (\$c1<0) do={ :set secs [:tonum \$h] }\r\n")
:set statusSrc ($statusSrc . "        :if ((\$c1>=0) and (\$c2<0)) do={ :set secs ([:tonum [:pick \$h 0 \$c1]]*60+[:tonum [:pick \$h (\$c1+1) [:len \$h]]]) }\r\n")
:set statusSrc ($statusSrc . "        :if (\$c2>=0) do={ :set secs ([:tonum [:pick \$h 0 \$c1]]*3600+[:tonum [:pick \$h (\$c1+1) \$c2]]*60+[:tonum [:pick \$h (\$c2+1) [:len \$h]]]) }\r\n")
:set statusSrc ($statusSrc . "        :if (\$secs<180) do={ :set on (\$on+1) }\r\n")
:set statusSrc ($statusSrc . "    }\r\n")
:set statusSrc ($statusSrc . "}\r\n")
:set statusSrc ($statusSrc . ":put (\"Clients: \" . [:len \$peers] . \" total, \" . \$on . \" online\")\r\n")
:set statusSrc ($statusSrc . ":put \"========================================\"\r\n")
:set statusSrc ($statusSrc . ":put \"Scripts: nethub-generate-client, nethub-client-list,\"\r\n")
:set statusSrc ($statusSrc . ":put \"         nethub-client-remove, nethub-uninstall\"\r\n")

/system script add name="nethub-status" source=$statusSrc comment="$newMarker | status"
:put "  [+] nethub-status"

# ----- nethub-uninstall -----
:local uninstSrc ""
:set uninstSrc ($uninstSrc . ":local marker \"NETHUB\"\r\n")
:set uninstSrc ($uninstSrc . ":local peers [/interface wireguard peers find interface=wg_nethub]\r\n")
:set uninstSrc ($uninstSrc . ":local active 0\r\n")
:set uninstSrc ($uninstSrc . ":foreach p in=\$peers do={ :local h [/interface wireguard peers get \$p last-handshake]; :if (([:len \$h]>0) and (\$h!=\"never\")) do={ :set active (\$active+1) } }\r\n")
:set uninstSrc ($uninstSrc . ":if (\$active > 0) do={\r\n")
:set uninstSrc ($uninstSrc . "    :put \"ERROR: \$active client(s) connected. Disconnect first.\"\r\n")
:set uninstSrc ($uninstSrc . "    :error \"active\"\r\n")
:set uninstSrc ($uninstSrc . "}\r\n")
:set uninstSrc ($uninstSrc . ":global nethubUninstallCount\r\n")
:set uninstSrc ($uninstSrc . ":if ([:typeof \$nethubUninstallCount] = \"nothing\") do={\r\n")
:set uninstSrc ($uninstSrc . "    :set nethubUninstallCount 1\r\n")
:set uninstSrc ($uninstSrc . "    :put \"Run 2 more times to uninstall\"\r\n")
:set uninstSrc ($uninstSrc . "} else={\r\n")
:set uninstSrc ($uninstSrc . "    :set nethubUninstallCount (\$nethubUninstallCount + 1)\r\n")
:set uninstSrc ($uninstSrc . "    :if (\$nethubUninstallCount >= 3) do={\r\n")
:set uninstSrc ($uninstSrc . "        :put \"Uninstalling...\"\r\n")
:set uninstSrc ($uninstSrc . "        :do { /interface wireguard peers remove [find interface=wg_nethub] } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :do { /interface wireguard remove wg_nethub } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :do { /ip address remove [find comment~\$marker] } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :do { /ip route remove [find comment~\$marker] } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :do { /ip firewall filter remove [find comment~\$marker] } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :do { /ip firewall nat remove [find comment~\$marker] } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :do { /ip dns static remove [find comment~\$marker] } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :do { /system scheduler remove [find name~\"nethub\"] } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :do { /file remove [find name~\"nethub\"] } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :do { /system script remove [find where name~\"nethub-\" and name!=\"nethub-uninstall\"] } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "        :set nethubUninstallCount\r\n")
:set uninstSrc ($uninstSrc . "        :put \"Done\"\r\n")
:set uninstSrc ($uninstSrc . "        :log warning \"NETHUB: Uninstalled\"\r\n")
:set uninstSrc ($uninstSrc . "        :do { /system script remove nethub-uninstall } on-error={}\r\n")
:set uninstSrc ($uninstSrc . "    } else={\r\n")
:set uninstSrc ($uninstSrc . "        :put (\"Run \" . (3 - \$nethubUninstallCount) . \" more\")\r\n")
:set uninstSrc ($uninstSrc . "    }\r\n")
:set uninstSrc ($uninstSrc . "}\r\n")

/system script add name="nethub-uninstall" source=$uninstSrc comment="$newMarker | uninstall"
:put "  [+] nethub-uninstall"

# ================================================================
# SECTION 10: STARTUP CONFIGURATION
# ================================================================

:put ""
:put "Configuring startup..."

:do { /system script remove [find where name="nethub-startup"] } on-error={}

/system script add name="nethub-startup" comment="$newMarker | startup" source="
:global nethubName \"$hubName\"
:global nethubFQDN \"$serverFQDN\"
:global nethubWgPort $wgPort
:global nethubNetwork \"$serverNetwork\"
:global nethubServerIP \"$serverIP\"
:global nethubClientStart $clientStart
:global nethubServerPubKey \"$serverPubKey\"
:log info \"NETHUB: Ready\"
"

:do { /system scheduler remove [find where name="nethub-boot"] } on-error={}
/system scheduler add name="nethub-boot" on-event="/system script run nethub-startup" start-time=startup comment="$newMarker"

/system script run nethub-startup
:put "  Done"

# ================================================================
# SECTION 11: CLEANUP OLD GLOBALS
# ================================================================

:put ""
:put "Cleaning up old variables..."

# Remove old MVSM globals
:global mvsmHubName; :set mvsmHubName
:global mvsmHubFQDN; :set mvsmHubFQDN
:global mvsmWgListenPort; :set mvsmWgListenPort
:global mvsmSstpBackup; :set mvsmSstpBackup
:global mvsmSplitTunnel; :set mvsmSplitTunnel
:global mvsmSplitTunnelNetworks; :set mvsmSplitTunnelNetworks
:global mvsmServerPubKey; :set mvsmServerPubKey
:global mvsmServerName; :set mvsmServerName
:global mvsmServerFQDN; :set mvsmServerFQDN
:global mvsmRegSecret; :set mvsmRegSecret
:global mvsmNextClientNum; :set mvsmNextClientNum
:global mvsmNextClientNumber; :set mvsmNextClientNumber

# Remove temporary variables
:global peerPubKey; :set peerPubKey
:global peerNumber; :set peerNumber
:global peerName; :set peerName
:global regClientToken; :set regClientToken
:global regClientPubKey; :set regClientPubKey
:global regClientName; :set regClientName
:global clientIP; :set clientIP

:put "  Done"

# ================================================================
# DONE
# ================================================================

:log info "$newMarker: Upgrade complete!"

:put ""
:put "========================================"
:put "NETHUB Upgrade Complete! v$version"
:put "========================================"
:put "Interface: $wgInterface"
:put "Network:   $serverNetwork"
:put "Port:      $wgPort"
:put "FQDN:      $serverFQDN"
:put "Peers:     $peerCount preserved"
:put ""
:put "Verify:"
:put "  /system script run nethub-status"
:put "  /system script run nethub-client-list"
:put "========================================"
