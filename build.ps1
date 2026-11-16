# Builds bin\Evil.prg for the fenix 6X Pro / Sapphire.
#   .\build.ps1             build only
#   .\build.ps1 -Install    build + copy to GARMIN\Apps on the connected watch
param([switch]$Install)
$ErrorActionPreference = 'Stop'

$cfg = "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg"
if (-not (Test-Path $cfg)) { throw "Connect IQ SDK not found. Install it with the Garmin SDK Manager first." }
$sdk = (Get-Content $cfg -Raw).Trim()

$key = "$PSScriptRoot\developer_key.der"
if (-not (Test-Path $key)) { throw "developer_key.der is missing - see the README for how to generate one." }

$out = "$PSScriptRoot\bin\Evil.prg"
New-Item -ItemType Directory -Force "$PSScriptRoot\bin" | Out-Null

& java -Xms1g "-Dfile.encoding=UTF-8" -jar "$sdk\bin\monkeybrains.jar" `
    -o $out -f "$PSScriptRoot\monkey.jungle" -y $key -d fenix6xpro -r -w
if ($LASTEXITCODE -ne 0) { throw "Build failed." }
"Built $out"
if (-not $Install) { return }

# Watches without music storage mount as a drive letter
$apps = Get-PSDrive -PSProvider FileSystem | ForEach-Object { "$($_.Root)GARMIN\APPS" } | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($apps) {
    Copy-Item $out $apps -Force
    "Copied to $apps"
    return
}

# The fenix 6X Pro / Sapphire is an MTP device, reachable only through the shell
$shell = New-Object -ComObject Shell.Application
$appsFolder = $null
foreach ($device in $shell.Namespace(17).Items() | Where-Object { $_.Type -eq 'Portable Device' }) {
    foreach ($storage in $device.GetFolder.Items()) {
        $garmin = $storage.GetFolder.Items() | Where-Object Name -eq 'GARMIN' | Select-Object -First 1
        if (-not $garmin) { continue }
        $appsFolder = $garmin.GetFolder.Items() | Where-Object Name -eq 'Apps' | Select-Object -First 1
        if ($appsFolder) { break }
    }
    if ($appsFolder) { break }
}
if (-not $appsFolder) { throw "Watch not found - plug it in over USB and try again." }

# MTP does not overwrite reliably, so remove the old copy first
$old = $appsFolder.GetFolder.Items() | Where-Object Name -match '^Evil(\.prg)?$' | Select-Object -First 1
if ($old) { $old.InvokeVerb('delete'); Start-Sleep 3 }
$appsFolder.GetFolder.CopyHere($out, 16)
Start-Sleep 5
"Copied to the watch - unplug it and pick 'EVIL' from the watch face list."
