#!/bin/sh
set -eu

# Variables

REPO_URL="https://github.com/propstat/server-templates.git"
REPO_DIR="/opt/propstat/server-templates"
SOURCE_DIR="$REPO_DIR/ubuntu/strategies"
PROPSTAT_DIR="/etc/propstat"
STRATEGIES_DIR="/etc/propstat/strategies"

# ==============================================================================
# PROPSTAT COLOR PALETTE
# ==============================================================================

# CI COLORS
PS_DARK_BLUE=$(printf '\033[38;2;0;40;85m')       # #002855
PS_LIGHT_BLUE=$(printf '\033[38;2;94;147;219m')   # #5E93DB
PS_GREY=$(printf '\033[38;2;63;68;68m')                   # #3F4444
PS_SKY_BLUE=$(printf '\033[38;2;221;229;237m')    # #DDE5ED

# INTERFACE COLORS
PS_RED=$(printf '\033[38;2;218;41;28m')            # #DA291C
PS_ORANGE=$(printf '\033[38;2;253;170;99m')        # #FDAA63
PS_YELLOW=$(printf '\033[38;2;250;224;83m')        # #FAE053
PS_GREEN=$(printf '\033[38;2;92;170;127m')         # #5CAA7F

# TERMINAL FORMATTING
PS_BOLD=$(printf '\033[1m')
PS_DIM=$(printf '\033[2m')
NC=$(printf '\033[0m')

# Check for root privileges

if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        printf '%s\n' "Error: sudo is required to install or remove Propstat." >&2
        exit 1
    fi

    printf '%s\n' "Root privileges are required; requesting sudo." >&2
    if ! sudo -v; then
        printf '%s\n' "Error: Could not authenticate with sudo." >&2
        exit 1
    fi

    exec sudo -n -- "$0" "$@"
fi


# ==========================================
# LOGO
# ==========================================
cat << EOF

${PS_ORANGE}=========================================================${NC}

            ${PS_DARK_BLUE}il${PS_LIGHT_BLUE}*%%%%*              ${PS_DARK_BLUE}i${PS_LIGHT_BLUE}%%%%%%%${NC}           
           ${PS_DARK_BLUE}iiiI${PS_LIGHT_BLUE}*%%%%%            ${PS_DARK_BLUE}iii${PS_LIGHT_BLUE}*%%%%*%${NC}          
          ${PS_DARK_BLUE}iiiiii${PS_LIGHT_BLUE}%%%%%%          ${PS_DARK_BLUE}iiiii${PS_LIGHT_BLUE}%*%%%*%${NC}         
         ${PS_DARK_BLUE}iiiiiii ${PS_LIGHT_BLUE}%%%%%%        ${PS_DARK_BLUE}iiiiii ${PS_LIGHT_BLUE}%*%%%%%${NC}        
        ${PS_DARK_BLUE}iiiiiii   ${PS_LIGHT_BLUE}*%%%%%%    ${PS_DARK_BLUE}iiiiiii   ${PS_LIGHT_BLUE}**%%%%*${NC}       
       ${PS_DARK_BLUE}iiiiiii     ${PS_LIGHT_BLUE}*%%%%%%  ${PS_DARK_BLUE}iiiiiii     ${PS_LIGHT_BLUE}%*%%%%*${NC}      
      ${PS_DARK_BLUE}iiiiiii       ${PS_LIGHT_BLUE}**%%%**${PS_DARK_BLUE}iiiiii       ${PS_LIGHT_BLUE}*%%%%*%${NC}     
     ${PS_DARK_BLUE}iiiiiii         ${PS_LIGHT_BLUE}*%%%%*${PS_DARK_BLUE}<iiii         ${PS_LIGHT_BLUE}**%%%**${NC}    
    ${PS_DARK_BLUE}iiiiiii           ${PS_LIGHT_BLUE}%*%%${PS_DARK_BLUE}%**ii           ${PS_LIGHT_BLUE}*%%%%*%${NC}   
   ${PS_DARK_BLUE}iiiiiiiiiiiiiiiiiiii${PS_LIGHT_BLUE}%%%%%%*%%%%%%%%%%%%%%%%%%%*${NC}  
  ${PS_DARK_BLUE}iiiiiiiiiiiiiiiiiiiiii${PS_LIGHT_BLUE}%*%%%%%%%%%%%%%%%%%%%%%%%%*${NC}
 ${PS_DARK_BLUE}iiiiiiiiiiiiiiiiiiiiiiii${PS_LIGHT_BLUE}**%%%%%%%%%%%%%%%%%%%%%%%%%${NC}
                                                   
${PS_LIGHT_BLUE}iiiii  iiiiii iiiiii  iiiii  iiiiii iiiiii  iii  iiiiii${NC}
${PS_LIGHT_BLUE}ii  ii ii  ii ii  ii  ii  ii  ii     ii    ii ii   ii${NC}  
${PS_LIGHT_BLUE}iiiii  iiiiii ii  ii  iiiii     ii   ii   iiiiiii  ii${NC}  
${PS_LIGHT_BLUE}ii     ii  ii iiiiii  ii     iiiiii  ii   ii   ii  ii${NC}  

${PS_ORANGE}=========================================================${NC}
Common Applications Installer Setup Wizard
${PS_ORANGE}=========================================================${NC}
Non-Commercial use is free of charge, please consult our
license for commercial use.
Please use the following link to view the license:
https://github.com/propstat/server-templates?tab=License-1-ov-file
${PS_ORANGE}=========================================================${NC}
${PS_RED}YOU ARE DOWNLOADING MATERIAL COVERED BY COPYRIGHT AND${NC}
${PS_RED}LICENSED UNDER THE PROPSTAT LICENSE. IF YOU CONTINUE${NC}
${PS_RED}YOU AGREE TO THE LICENSE TERMS.${NC}
${PS_ORANGE}=========================================================${NC}
EOF

while true; do
    printf "Do you accept the license terms? (y/n): "
    read -r reply

    case "$reply" in
        y|Y|yes|YES|Yes)
            break
            ;;
        n|N|no|NO|No)
            echo "Installation aborted."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done

if [ -d "$PROPSTAT_DIR" ]; then
    printf '%s\n' "An existing Propstat installation was found."
    printf '%s\n' "1) Update the installation, overwriting installed files"
    printf '%s\n' "2) Remove the installation, including its binaries and cronjob"
    printf '%s\n' "3) Abort"

    while true; do
        printf "Choose an option (1-3): "
        read -r choice

        case "$choice" in
            1) ACTION=install; break ;;
            2) ACTION=remove; break ;;
            3) printf '%s\n' "Process aborted."; exit 0 ;;
            *) printf '%s\n' "Invalid option. Please choose 1, 2, or 3." ;;
        esac
    done
else
    printf '%s\n' "No Propstat installation was found."
    printf '%s\n' "1) Install"
    printf '%s\n' "2) Abort"

    while true; do
        printf "Choose an option (1-2): "
        read -r choice

        case "$choice" in
            1) ACTION=install; break ;;
            2) printf '%s\n' "Process aborted."; exit 0 ;;
            *) printf '%s\n' "Invalid option. Please choose 1 or 2." ;;
        esac
    done
fi

if [ "$ACTION" = remove ]; then
    if [ -f /etc/systemd/system/propstat-autoupdate.timer ]; then
        systemctl disable --now propstat-autoupdate.timer
        systemctl clean --what=state propstat-autoupdate.timer
        rm -f /etc/systemd/system/propstat-autoupdate.timer \
            /etc/systemd/system/propstat-autoupdate.service
        systemctl daemon-reload
    fi

    rm -rf "$PROPSTAT_DIR"
    rm -f /usr/local/bin/propstatinstaller \
        /usr/bin/confirm_continue \
        /usr/bin/confirm_continue.sh \
        /usr/local/bin/confirm_continue.sh \
        /usr/local/bin/autoupdate \
        /usr/local/bin/change-ip \
        /usr/local/bin/timezone \
        /usr/local/sbin/propstat-autoupdate \
        /usr/local/bin/cf-ip \
        /usr/local/bin/cf-ip.sh \
        /etc/cron.d/propstat-cf-ip
    rm -rf "$REPO_DIR"
    printf '%s\n' "Propstat installation and its cronjob have been removed."
    exit 0
fi

# Install missing dependencies.
packages=""

if ! command -v git >/dev/null 2>&1; then
    packages="$packages git"
fi

if ! command -v rsync >/dev/null 2>&1; then
    packages="$packages rsync"
fi

if ! command -v cron >/dev/null 2>&1; then
    packages="$packages cron"
fi

if ! command -v dig >/dev/null 2>&1; then
    packages="$packages dnsutils"
fi

if [ -n "$packages" ]; then
    apt-get update
    # Intentional word splitting: packages contains package names only.
    # shellcheck disable=SC2086
    apt-get install -y $packages
fi

# Ensure the destination exists.
install -d "$STRATEGIES_DIR"
install -d "$(dirname "$REPO_DIR")"

if [ -d "$REPO_DIR/.git" ]; then
    REPO_ORIGIN=$(git -C "$REPO_DIR" remote get-url origin)
    if [ "$REPO_ORIGIN" != "$REPO_URL" ]; then
        printf 'Error: %s is already a checkout of a different repository.\n' "$REPO_DIR" >&2
        exit 1
    fi
    git -C "$REPO_DIR" pull --ff-only origin main
elif [ -e "$REPO_DIR" ]; then
    printf 'Error: %s exists and is not a Git checkout.\n' "$REPO_DIR" >&2
    exit 1
else
    # Clone the repository, including its history, into a persistent location.
    git clone --sparse --branch main "$REPO_URL" "$REPO_DIR"
fi

# Check out strategies and helpers. Cone mode also includes scripts directly
# inside ubuntu/, including the installer scripts.
git -C "$REPO_DIR" sparse-checkout set ubuntu/strategies ubuntu/helpers

# Synchronize files, overwriting existing files and deleting obsolete ones.
rsync -a --delete "$SOURCE_DIR/" "$STRATEGIES_DIR/"

printf '%s\n' "Strategies installed successfully."
printf '%s\n' "Linking installer commands to the project checkout."

install -d /usr/local/bin
ln -sfn "$REPO_DIR/ubuntu/propstatinstaller.sh" /usr/local/bin/propstatinstaller
ln -sfn "$REPO_DIR/ubuntu/helpers/confirm_continue.sh" /usr/bin/confirm_continue
rm -f /usr/bin/confirm_continue.sh
ln -sfn "$REPO_DIR/ubuntu/helpers/cf-ip.sh" /usr/local/bin/cf-ip
ln -sfn "$REPO_DIR/ubuntu/helpers/autoupdate.sh" /usr/local/bin/autoupdate
ln -sfn "$REPO_DIR/ubuntu/helpers/change_ip.sh" /usr/local/bin/change-ip
ln -sfn "$REPO_DIR/ubuntu/helpers/timezone.sh" /usr/local/bin/timezone

printf '%s\n' "Scheduling daily Cloudflare IP range updates."
printf '%s\n' "0 3 * * * root /usr/local/bin/cf-ip" > /etc/cron.d/propstat-cf-ip
chmod 644 /etc/cron.d/propstat-cf-ip

# Load the confirmation helper for the public IP check and update prompt.
. /usr/bin/confirm_continue

# Determine the public IP using Cloudflare DNS, then Google DNS as a fallback.
PUBLIC_IP=$(dig +short +time=2 +tries=1 txt ch whoami.cloudflare @1.0.0.1 2>/dev/null |
    sed -n '1{s/^"//;s/"$//;p;}')
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(dig +short +time=2 +tries=1 TXT o-o.myaddr.l.google.com @8.8.8.8 2>/dev/null |
        sed -n '1{s/^"//;s/"$//;p;}')
fi

if [ -n "$PUBLIC_IP" ]; then
    printf 'Public IP: %s\n' "$PUBLIC_IP"
    confirm_continue -y \
        -startmsg="Is this the correct public IP address?" \
        -endmsg= \
        msg_yes="Keeping the current network configuration." \
        msg_no="Starting network configuration." \
        on_no="change-ip"
else
    printf '%s\n' "Public IP could not be determined."
    change-ip
fi

# Automatic Updates
confirm_continue -y \
    -startmsg="Do you want to update your Ubuntu Server automatically?" \
    on_no="echo 'The machine will not automatically update and reboot.'" \
    on_yes="autoupdate"

printf '%s\n' "You can now use the command propstatinstaller to launch the application installer."
printf '%s\n' "Use the command propstatinstaller to start an installation of a specific application."
exit 0