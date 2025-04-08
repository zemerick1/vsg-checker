param (
    [Parameter(Mandatory=$true, HelpMessage="Path to the configuration file")]
    [string]$ConfigFilePath,
    
    [Parameter(Mandatory=$false, HelpMessage="Comma-separated list of features to check per SSID")]
    [string]$SsidFeatures = "okc,dot11k,dmo-client-threshold 40,rf-band-6ghz,broadcast-filter arp,g-min-tx-rate,a-min-tx-rate,multicast-rate-optimization,dynamic-multicast-optimization,delete-pmkcache",
    
    [Parameter(Mandatory=$false, HelpMessage="Comma-separated list of features to check per radio profile")]
    [string]$RadioFeatures = "max-tx-power,40MHZ-intolerance,dot11h",

    [Parameter(Mandatory=$false, HelpMessage="Comma-separated list of features to check globally")]
    [string]$GlobalFeatures = "data-encryption-enable,application-monitoring,voip_qos_trusted,dpi,ntp-server,ipm,clock timezone none,virtual-controller-country,pmkcache-timeout",

    [Parameter(Mandatory=$false, HelpMessage="8 or 10 (Assumes 10)")]
    [string]$Version = "10"
)

# Convert feature strings to arrays
$ssidFeatureArray = $SsidFeatures -split ','
$radioFeatureArray = $RadioFeatures -split ','

# Define profile-specific features (base set)
$dot11gFeatures = @("max-tx-power", "40MHZ-intolerance", "allowed-channels")
$dot11aFeatures = @("max-tx-power", "dot11h")

# Global settings to check separately
[array]$globalFeatures = $globalFeatures -split ',' | ForEach-Object { $_.Trim() }


# Build collection for AOS8 features.
$globalFeaturesLegacy = @(
    "client-match",
    "wide-bands",
    "rf-band"
)

# Add AOS8 only features if version 8 is declared
if ($Version -eq "8") {
    $globalFeatures += $globalFeaturesLegacy
}
# Hashtables to track tx power from all profiles
$globalMaxGPower = @{}
$globalMinAPower = @{}

# Function to process and display SSID analysis
function Analyze-SSID {
    param (
        [string]$ssidName,
        [string[]]$ssidConfig
    )
    Write-Host "`nAnalyzing SSID: $ssidName" -ForegroundColor Cyan
    Write-Host "------------------------"
    
    $configContent = $ssidConfig -join "`n"
    
    foreach ($feature in $ssidFeatureArray) {
        $feature = $feature.Trim()
        if ($feature -eq "g-min-tx-rate") {
            if ($configContent -match "g-min-tx-rate\s+(\d+)") {
                $actualValue = $matches[1]
                if ($actualValue -eq "12") {
                    Write-Host "g-min-tx-rate 12" -ForegroundColor Green
                } else {
                    Write-Host "g-min-tx-rate $actualValue" -ForegroundColor Red
                }
            } else {
                Write-Host "g-min-tx-rate not set" -ForegroundColor Red
            }
        }
        elseif ($feature -eq "a-min-tx-rate") {
            if ($configContent -match "a-min-tx-rate\s+(\d+)") {
                $actualValue = $matches[1]
                if ($actualValue -eq "24") {
                    Write-Host "a-min-tx-rate 24" -ForegroundColor Green
                } else {
                    Write-Host "a-min-tx-rate $actualValue" -ForegroundColor Red
                }
            } else {
                Write-Host "a-min-tx-rate not set" -ForegroundColor Red
            }
        }
        elseif ($feature -like "broadcast-filter*") {
           if ($configContent -match "broadcast-filter\s+(arp|all)") {
                $actualValue = $matches[1]
                Write-Host "broadcast-filter $actualValue" -ForegroundColor Green
            } else {
                Write-Host "broadcast-filter" -ForegroundColor Red -NoNewline
                write-host " (broadcast filter not set for SSID)" -ForegroundColor Yellow
          } 
        }
        elseif ($configContent -match [regex]::Escape($feature)) {
            Write-Host "$feature" -ForegroundColor Green
        } else {
            Write-Host "$feature" -ForegroundColor Red
        }
    }
}

# Function to process and display Radio Profile analysis
function Analyze-RadioProfile {
    param (
        [string]$profileName,
        [string[]]$profileConfig
    )
    Write-Host "`nAnalyzing Radio Profile: $profileName" -ForegroundColor Magenta
    Write-Host "------------------------"
    
    $configContent = $profileConfig -join "`n"
    # Use full base features for the profile type, overridden by $radioFeatureArray if provided
    $baseFeatures = if ($profileName -like "dot11g-radio-profile*") { $dot11gFeatures } else { $dot11aFeatures }
    $featuresToCheck = if ($radioFeatureArray.Count -gt 0 -and $RadioFeatures -ne "max-tx-power,40MHZ-intolerance,dot11h") { 
        $baseFeatures | Where-Object { $_ -in $radioFeatureArray } 
    } else { 
        $baseFeatures 
    }
    
    # Extract base radio profile name (e.g., "default" or "non-default")
    $radioProfileName = if ($profileName -match "(dot11g-radio-profile|dot11a-radio-profile)\s*(.+)?") {
        if ($matches[2]) { $matches[2] } else { "default" }
    } else { $profileName }
    
    foreach ($feature in $featuresToCheck) {
        $feature = $feature.Trim()
        if ($feature -eq "max-tx-power") {
            if ($configContent -match "max-tx-power\s+(\d+)" -and ($profileName -like "dot11g-radio-profile*")) {
                $maxgPower = [int]$matches[1]
                $globalMaxGPower[$radioProfileName] = $maxgPower  # Use base name as key
                if ($maxgPower -le 9) {
                    Write-Host "max-tx-power $maxgPower" -ForegroundColor Green
                } else {
                    Write-Host "max-tx-power $maxgPower" -ForegroundColor Red -NoNewline
                    Write-Host " (max power above recommended value of 9)" -ForegroundColor Yellow
                }
            } elseif ($configContent -match "min-tx-power\s+(\d+)" -and ($profileName -like "dot11a-radio-profile*")) {
                $minaPower = [int]$matches[1]
                $globalMinAPower[$radioProfileName] = $minaPower  # Use base name as key
                Write-Host "min-tx-power $minaPower" -ForegroundColor Green -NoNewline
                Write-Host " (will check power deltas later)" -ForegroundColor Yellow
            }
            else {
                Write-Host "max-tx-power not set or default" -ForegroundColor Red
            }
        }
        elseif ($feature -eq "allowed-channels") {
            if ($configContent -match "allowed-channels\s+(.+)") {
                $actualValue = $matches[1]
                $defaultChannels = "1,6,11"
                if ($actualValue -eq $defaultChannels) {
                    Write-Host "allowed-channels $actualValue" -ForegroundColor Green
                } else {
                    Write-Host "allowed-channels $actualValue" -ForegroundColor Red -NoNewline
                    Write-Host " (non-default channels)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "allowed-channels not set" -ForegroundColor Green -NoNewline
                Write-Host " (default channels 1,6,11 assumed)" -ForegroundColor Yellow
            }
        }
        elseif ($configContent -match [regex]::Escape($feature)) {
            Write-Host "$feature" -ForegroundColor Green
        } else {
            Write-Host "$feature" -ForegroundColor Red
        }
    }
}

# Read and process the configuration file
try {
    $configLines = Get-Content -Path $ConfigFilePath
    
    # Variables to store configurations
    $currentSSID = ""
    $currentRadioProfile = ""
    $currentConfig = @()
    $ssids = @{}
    $radioProfiles = @{}

    # Parse the configuration line by line
    foreach ($line in $configLines) {
        if ($line -match "^wlan ssid-profile\s+(.+)$") {
            # Store previous config if exists
            if ($currentSSID -ne "") {
                $ssids[$currentSSID] = $currentConfig
            } elseif ($currentRadioProfile -ne "") {
                $radioProfiles[$currentRadioProfile] = $currentConfig
            }
            # Start new SSID
            $currentSSID = $matches[1]
            $currentRadioProfile = ""
            $currentConfig = @()
        }
        elseif ($line -match "^rf (dot11g-radio-profile|dot11a-radio-profile)(?:\s+(.+))?$") {
            # Store previous config if exists
            if ($currentSSID -ne "") {
                $ssids[$currentSSID] = $currentConfig
            } elseif ($currentRadioProfile -ne "") {
                $radioProfiles[$currentRadioProfile] = $currentConfig
            }
            # Start new radio profile
            $radioType = $matches[1]
            $profileName = if ($matches[2]) { "$radioType $($matches[2])" } else { "$radioType default" }
            $currentRadioProfile = $profileName
            $currentSSID = ""
            $currentConfig = @()
        }
        elseif ($currentSSID -ne "" -or $currentRadioProfile -ne "") {
            # Add line to current configuration
            $currentConfig += $line
        }
    }
    
    # Store the last configuration
    if ($currentSSID -ne "") {
        $ssids[$currentSSID] = $currentConfig
    } elseif ($currentRadioProfile -ne "") {
        $radioProfiles[$currentRadioProfile] = $currentConfig
    }

    # Analyze each SSID
    foreach ($ssid in $ssids.Keys) {
        Analyze-SSID -ssidName $ssid -ssidConfig $ssids[$ssid]
    }

    # Analyze each Radio Profile
    foreach ($profile in $radioProfiles.Keys) {
        Analyze-RadioProfile -profileName $profile -profileConfig $radioProfiles[$profile]
    }

    # Check global settings
    $fullConfig = $configLines -join "`n"
    Write-Host "`nGlobal Settings Check" -ForegroundColor Cyan
    Write-Host "------------------------"
     foreach ($feature in $globalFeatures) {
        if ($fullConfig -match [regex]::Escape($feature)) {
            switch ($feature) {
                "clock timezone none" {
                    Write-Host "clock timezone none" -ForegroundColor Red -NoNewline
                    Write-Host " (Timezone not set)" -ForegroundColor Yellow
                }
                "wide-bands" {
                    if ($fullConfig -match "wide-bands\s+(24ghz)") {
                    $actualValue = $matches[1]
                    Write-Host "wide-bands $actualValue" -ForegroundColor Red -NoNewline
                    Write-Host " (Wide Channel bands enabled on 2.4GHz)" -ForegroundColor Yellow
                    } else { Write-Host "wide-bands not enabled on 2.4GHz" -ForegroundColor Green }
                }
                "dpi" {
                    if ($fullConfig -match "dpi\s+(app|all)") {
                        $actualValue = $matches[1]
                        Write-Host "dpi $actualValue" -ForegroundColor Green
                    } else {
                        Write-Host "dpi (unknown value)" -ForegroundColor Red
                    }
                }
                "pmkcache-timeout" {
                    if ($fullConfig -match "pmkcache-timeout\s+(\d+)") {
                        $actualValue = $matches[1]
                        if ($actualValue -ne '8') {
                            Write-Host "pmkcache-timeout $actualValue" -ForegroundColor Green -NoNewline
                            write-host " (recommended value is 8)" -ForegroundColor Yellow
                        } else { Write-Host "pmkcache-timeout $actualValue" -ForegroundColor Green }
                    }
                }
                "rf-band" {
                    if ($fullConfig -match "rf-band\s+(all|2.4|5.0)") {
                        $actualValue = $matches[1]
                        if ($actualValue -notcontains 'all') {
                        Write-Host "rf-band $actualValue" -ForegroundColor Red -NoNewline
                        Write-Host " (recommended value all)" -ForegroundColor Yellow
                    } else { Write-Host "$feature $actualValue" -ForegroundColor Green }
                    }
                }
                default {
                    Write-Host "$feature" -ForegroundColor Green
                }
            }
        } else {
            # Absence of the feature is a simple red output, no special cases
            Write-Host "$feature" -ForegroundColor Red
        }
    }

# Check tx power delta within each radio profile (dot11a vs dot11g within same profile.)
if ($globalMaxGPower.Count -gt 0 -and $globalMinAPower.Count -gt 0) {
    Write-Host "`nTX Power Delta Check" -ForegroundColor Cyan
    Write-Host "------------------------"
    # Get all unique radio profile names
    $radioProfileNames = ($globalMaxGPower.Keys + $globalMinAPower.Keys) | Sort-Object -Unique
    foreach ($profile in $radioProfileNames) {
        if ($globalMaxGPower.ContainsKey($profile) -and $globalMinAPower.ContainsKey($profile)) {
            $maxgPower = $globalMaxGPower[$profile]
            $minaPower = $globalMinAPower[$profile]
            $txDelta = $minaPower - $maxgPower
            if ($txDelta -lt 6) {
                Write-Host "Delta for radio profile '$profile' (dot11g max-tx-power $maxgPower, dot11a min-tx-power $minaPower) is $txDelta dBm" -ForegroundColor Red -NoNewline
                Write-Host " (tx delta between min/max on 5GHz & 2.4GHz should be at least 6dBm)" -ForegroundColor Yellow
            } else {
                Write-Host "TX power delta for radio profile '$profile' (dot11g max-tx-power $maxgPower, dot11a min-tx-power $minaPower) is $txDelta dBm" -ForegroundColor Green
            }
        } elseif ($globalMaxGPower.ContainsKey($profile)) {
            Write-Host "Radio profile '$profile' has dot11g max-tx-power $($globalMaxGPower[$profile]) but no dot11a min-tx-power" -ForegroundColor Yellow
        } elseif ($globalMinAPower.ContainsKey($profile)) {
            Write-Host "Radio profile '$profile' has dot11a min-tx-power $($globalMinAPower[$profile]) but no dot11g max-tx-power" -ForegroundColor Yellow
        }
    }
}
}
catch {
    Write-Host "Error reading the configuration file: $_" -ForegroundColor Red
}


Write-Host "`nLEGEND" -ForegroundColor Cyan
Write-Host "------------------------"
Write-Host "Green: Setting is correctly enabled / has a value set. (ie. We only check that NTP has a value, where DMO is just a toggle.)" -ForegroundColor Green
Write-Host "Yellow: Notes." -ForegroundColor Yellow
Write-host "Red: Setting is missing or is outside the VSG threshold." -ForegroundColor Red
