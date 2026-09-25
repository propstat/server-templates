# server-templates
Lightweight Server Scripts to prepare machines to be Setup

# How to Run 
## Windows 2025 Server & other Windows Server Derrivates
Run with `Win + R`
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; New-Item -ItemType Directory -Path 'C:\propstatInstallScript' -Force | Out-Null; Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/propstat/server-templates/refs/heads/main/win2k5/vanilla.ps' -OutFile 'C:\propstatInstallScript\vanilla.ps1'; Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File','C:\propstatInstallScript\vanilla.ps1'"
```
