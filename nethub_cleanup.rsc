# NETHUB Cleanup Script
# One-time fix: set correct FQDN and remove old MVSM globals
# Run: /import nethub_cleanup.rsc

:put "========================================"
:put "NETHUB Cleanup"
:put "========================================"

# Set correct FQDN
:global nethubFQDN "nethub.k2o.cc"
:put "Set nethubFQDN = nethub.k2o.cc"

# Remove old MVSM globals
:put ""
:put "Removing old MVSM globals..."
:global mvsmHubName; :set mvsmHubName
:global mvsmHubFQDN; :set mvsmHubFQDN
:global mvsmWgListenPort; :set mvsmWgListenPort
:global mvsmSstpBackup; :set mvsmSstpBackup
:global mvsmSplitTunnel; :set mvsmSplitTunnel
:global mvsmServerPubKey; :set mvsmServerPubKey
:global mvsmServerName; :set mvsmServerName
:global mvsmServerFQDN; :set mvsmServerFQDN
:global mvsmRegSecret; :set mvsmRegSecret
:global mvsmNextClientNum; :set mvsmNextClientNum
:global mvsmNextClientNumber; :set mvsmNextClientNumber
:global mvsmSplitTunnelNetworks; :set mvsmSplitTunnelNetworks
:put "  Done"

# Remove temporary variables
:put ""
:put "Removing temporary variables..."
:global peerPubKey; :set peerPubKey
:global peerNumber; :set peerNumber
:global peerName; :set peerName
:global regClientToken; :set regClientToken
:global regClientPubKey; :set regClientPubKey
:global regClientName; :set regClientName
:global clientIP; :set clientIP
:put "  Done"

# Update startup script with correct FQDN
:put ""
:put "Updating startup script..."

:global nethubName
:global nethubWgPort
:global nethubNetwork
:global nethubServerIP
:global nethubServerPubKey
:global nethubClientStart

:local startupSrc ""
:set startupSrc ":global nethubName \"$nethubName\"\r\n"
:set startupSrc ($startupSrc . ":global nethubFQDN \"nethub.k2o.cc\"\r\n")
:set startupSrc ($startupSrc . ":global nethubWgPort $nethubWgPort\r\n")
:set startupSrc ($startupSrc . ":global nethubNetwork \"$nethubNetwork\"\r\n")
:set startupSrc ($startupSrc . ":global nethubServerIP \"$nethubServerIP\"\r\n")
:set startupSrc ($startupSrc . ":global nethubServerPubKey \"$nethubServerPubKey\"\r\n")
:set startupSrc ($startupSrc . ":global nethubClientStart $nethubClientStart\r\n")

:do { /system script remove [find name="nethub-startup"] } on-error={}
/system script add name="nethub-startup" source=$startupSrc comment="NETHUB v5.0 | startup"
:put "  Done"

:put ""
:put "========================================"
:put "Cleanup Complete!"
:put "========================================"
:put "FQDN: nethub.k2o.cc"
:put ""
:put "Verify: /environment print"
:put "========================================"
