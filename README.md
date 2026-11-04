# server-templates
Lightweight Server Scripts to prepare machines to be Setup

# How to Run 
## Windows 2025 Server & other Windows Server Derrivates
Run with `Win + R`
```
powershell -NoP -EP Bypass -C "saps powershell -Verb RunAs '-NoP -EP Bypass -NoExit -C iwr -UseB https://raw.githubusercontent.com/propstat/server-templates/main/win2k5/vanilla.ps -OutFile C:\Windows\Temp\vanilla.ps1; C:\Windows\Temp\vanilla.ps1'"
```
## Ubuntu Application Installer
```
sh -c 'tmp=$(mktemp) || exit 1; url="https://raw.githubusercontent.com/propstat/server-templates/main/ubuntu/application-setup-wizard.sh"; url="$url?nocache=$(date +%s)"; if command -v curl >/dev/null 2>&1; then curl -fsSL "$url" -o "$tmp"; elif command -v wget >/dev/null 2>&1; then wget -qO "$tmp" "$url"; else echo "Error: need curl or wget" >&2; exit 1; fi; chmod +x "$tmp"; sh "$tmp"'
```
