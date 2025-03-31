param (
    [Parameter(Mandatory=$true, HelpMessage="Path to the configuration file")]
    [string]$ConfigFilePath,
    
    [Parameter(Mandatory=$false, HelpMessage="Comma-separated list of features to check per SSID")]
    [string]$SsidFeatures = "okc,dot11k,dmo-client-threshold 40,rf-band-6ghz,broadcast-filter arp,g-min-tx-rate,a-min-tx-rate,multicast-rate-optimization,dynamic-multicast-optimization",
    
    [Parameter(Mandatory=$false, HelpMessage="Comma-separated list of features to check per radio profile")]
    [string]$RadioFeatures = "max-tx-power,40MHZ-intolerance,dot11h"
)

# Convert feature strings to arrays
$ssidFeatureArray = $SsidFeatures -split ','
$radioFeatureArray = $RadioFeatures -split ','

# Define profile-specific features (base set)
$dot11gFeatures = @("max-tx-power", "40MHZ-intolerance", "allowed-channels")
$dot11aFeatures = @("max-tx-power", "dot11h")

# Global settings to check separately
$globalFeatures = @(
    "data-encryption-enable",
    "application-monitoring",
    "voip_qos_trusted",
    "dpi app",
    "ntp-server",
    "ipm",
    "clock timezone none",
    "virtual-controller-country"
)

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
    
    foreach ($feature in $featuresToCheck) {
        $feature = $feature.Trim()
        if ($feature -eq "max-tx-power") {
            if ($configContent -match "max-tx-power\s+(\d+)") {
                $actualValue = [int]$matches[1]
                if ($actualValue -le 9) {
                    Write-Host "max-tx-power $actualValue" -ForegroundColor Green
                } else {
                    Write-Host "max-tx-power $actualValue" -ForegroundColor Red -NoNewline
                    Write-Host " (max power above recommended value of 9)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "max-tx-power not set" -ForegroundColor Red
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
            if ($feature -eq "clock timezone none") {
                Write-Host "clock timezone none" -ForegroundColor Green -NoNewline
                Write-Host " (Timezone not set)" -ForegroundColor Yellow
            } else {
                Write-Host "$feature" -ForegroundColor Green
            }
        } else {
            if ($feature -eq "virtual-controller-country") {
                Write-Host "virtual-controller-country" -ForegroundColor Red -NoNewline
                Write-Host " (Country Code not set)" -ForegroundColor Yellow
            } else {
                Write-Host "$feature" -ForegroundColor Red
            }
        }
    }
}
catch {
    Write-Host "Error reading the configuration file: $_" -ForegroundColor Red
}
