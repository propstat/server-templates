# server-templates
Lightweight Server Scripts to prepare machines to be Setup

# How to Run 
## Windows 2025 Server & other Windows Server Derrivates
propstat-dev/server-templates
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command `"& { Invoke-WebRequest -Uri ''https://vanilla.ps'' -OutFile ''$env:TEMP\vanilla.ps1''; & ''$env:TEMP\vanilla.ps1'' }`"' -Wait"
```
