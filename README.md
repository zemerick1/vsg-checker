# vsg-checker
Provides a rudimentary check for Aruba's best practice on a AC group configuration.

Copy an Aruba IAP configuration into a text file. Run this script against the file and it will output a rudimentary check for Aruba best practices. 

The example configuration was pulled from an Aruba Central group configuration. 

```
powershell.exe -File "vsg-checkv2.ps1" -ConfigFilePath "path\to\your\config.txt"

powershell.exe -File "vsg-checkv2.ps1" -ConfigFilePath "example.conf" -SsidFeatures "okc,dot11k" -RadioFeatures "max-tx-power,dot11h"
```
