# server-templates
Lightweight Server Scripts to prepare machines to be Setup

# How to Run 
## Windows 2025 Server & other Windows Server Derrivates
Run with `Win + R`
```
powershell -NoP -EP Bypass -C "saps powershell -Verb RunAs '-NoP -EP Bypass -NoExit -C iwr -UseB https://raw.githubusercontent.com/propstat/server-templates/main/win2k5/vanilla.ps -OutFile C:\Windows\Temp\vanilla.ps1; C:\Windows\Temp\vanilla.ps1'"
```
