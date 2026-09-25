# server-templates
Lightweight Server Scripts to prepare machines to be Setup

# How to Run 
## Windows 2025 Server & other Windows Server Derrivates
propstat-dev/server-templates
```
$f="$env:TEMP\vanilla.ps1"; Invoke-WebRequest 'https://raw.githubusercontent.com/propstat/server-templates/refs/heads/main/win2k5/vanilla.ps' -OutFile $f; Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$f`"" -Wait
```
