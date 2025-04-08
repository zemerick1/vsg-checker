# vsg-checker
Provides a rudimentary check for Aruba's best practice on a AC group configuration.

Copy an Aruba IAP configuration into a text file. Run this script against the file and it will output a rudimentary check for Aruba best practices. 

The example configuration was pulled from an Aruba Central group configuration. 

```
powershell.exe -File "vsg-checkv2.ps1" -ConfigFilePath "path\to\your\config.txt"

powershell.exe -File "vsg-checkv2.ps1" -ConfigFilePath "aos8.conf" -Version 8

powershell.exe -File "vsg-checkv2.ps1" -ConfigFilePath "example.conf" -SsidFeatures "okc,dot11k" -RadioFeatures "max-tx-power,dot11h"

```

# Caveats
1. If you query the group configuration via the API the full configuration is not pulled. Specifically, the Country Code.
2. Some checks are just looking for features that are enabled. It will not check for specific values unless you add it as a parameter value.
3. Max-G-Power is arbitrary check. There will be a note if the script sees anything over 9dBm.

# TODO
1. Support flex radios.
2. Support 6GHz checks.
3. DFS checks.
