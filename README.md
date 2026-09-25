# server-templates
Lightweight Server Scripts to prepare machines to be Setup

# How to Run 
## Windows 2025 Server & other Windows Server Derrivates
Run with `Win + R`
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$f=Join-Path $env:TEMP 'vanilla.ps1'; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/propstat/server-templates/refs/heads/main/win2k5/vanilla.ps' -OutFile $f; Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',$f)"
```
