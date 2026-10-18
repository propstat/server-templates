#!/bin/sh
set -eu

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

REPO_URL="https://github.com/propstat/server-templates.git"
REPO_DIR="/tmp/server-templates"
SOURCE_DIR="$REPO_DIR/ubuntu/strategies"
PROPSTAT_DIR="/etc/propstat"
STRATEGIES_DIR="/etc/propstat/strategies"
RED=$(printf '\033[0;31m')
NC=$(printf '\033[0m')

# ==========================================
# LOGO
# ==========================================
cat << EOF

=========================================================

            il*%%%%*             i%%%%%%%           
           iiiI*%%%%%           iii*%%%%*%          
          iiiiii%%%%%%         iiiii%*%%%*%         
         iiiiiii %%%%%%       iiiiii %*%%%%%        
        iiiiiii   *%%%%%%   iiiiiii   **%%%%*       
       iiiiiii     *%%%%%% iiiiiii     %*%%%%*      
      iiiiiii       **%%%**iiiiii       *%%%%*%     
     iiiiiii         *%%%%*<iiii         **%%%**    
    iiiiiii           %*%%%**ii           *%%%%*%   
   iiiiiiiiiiiiiiiiiiii%%%%%%*%%%%%%%%%%%%%%%%%%%*  
  iiiiiiiiiiiiiiiiiiiiii%*%%%%%%%%%%%%%%%%%%%%%%%%* 
 iiiiiiiiiiiiiiiiiiiiiiii**%%%%%%%%%%%%%%%%%%%%%%%%%
                                                   
iiiii  iiiiii iiiiii  iiiii  iiiiii iiiiii  iii  iiiiii
ii  ii ii  ii ii  ii  ii  ii  ii     ii    ii ii   ii  
iiiii  iiiiii ii  ii  iiiii     ii   ii   iiiiiii  ii  
ii     ii  ii iiiiii  ii     iiiiii  ii   ii   ii  ii  

=========================================================
Common Applications Installer
=========================================================
Non-Commercial use is free of charge, please consult our
license for commercial use.
Please use the following link to view the license:
https://github.com/propstat/server-templates?tab=License-1-ov-file
=========================================================
${RED}YOU ARE DOWNLOADING MATERIAL COVERED BY COPYRIGHT AND${NC}
${RED}LICENSED UNDER THE PROPSTAT LICENSE. IF YOU CONTINUE${NC}
${RED}YOU AGREE TO THE LICENSE TERMS.${NC}
=========================================================
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
    rm -rf "$PROPSTAT_DIR"
    rm -f /usr/local/bin/propstatinstaller \
        /usr/local/bin/confirm_continue.sh \
        /usr/local/bin/cf-ip \
        /usr/local/bin/cf-ip.sh \
        /etc/cron.d/propstat-cf-ip
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

if [ -n "$packages" ]; then
    apt-get update
    # Intentional word splitting: packages contains package names only.
    # shellcheck disable=SC2086
    apt-get install -y $packages
fi

# Ensure the destination exists.
install -d "$STRATEGIES_DIR"

# Remove any previous temporary checkout.
rm -rf "$REPO_DIR"

# Clone the entire repository, including its history.
git clone --sparse "$REPO_URL" "$REPO_DIR"

# Check out the required files.
git -C "$REPO_DIR" sparse-checkout set --no-cone \
    '/ubuntu/strategies/' \
    '/ubuntu/propstatinstaller.sh' \
    '/ubuntu/helpers/confirm_continue.sh' \
    '/ubuntu/helpers/cf-ip.sh'

# Synchronize files, overwriting existing files and deleting obsolete ones.
rsync -a --delete "$SOURCE_DIR/" "$STRATEGIES_DIR/"

printf '%s\n' "Strategies installed successfully."
printf '%s\n' "Adding installer to /usr/local/bin."

install -d /usr/local/bin
cp "$REPO_DIR/ubuntu/propstatinstaller.sh" /usr/local/bin/propstatinstaller
chmod +x /usr/local/bin/propstatinstaller
cp "$REPO_DIR/ubuntu/helpers/confirm_continue.sh" /usr/local/bin/confirm_continue.sh
chmod +x /usr/local/bin/confirm_continue.sh
cp "$REPO_DIR/ubuntu/helpers/cf-ip.sh" /usr/local/bin/cf-ip
chmod +x /usr/local/bin/cf-ip

printf '%s\n' "Scheduling daily Cloudflare IP range updates."
printf '%s\n' "0 3 * * * root /usr/local/bin/cf-ip" > /etc/cron.d/propstat-cf-ip
chmod 644 /etc/cron.d/propstat-cf-ip

# Clean up the temporary checkout.
rm -rf "$REPO_DIR"

printf '%s\n' "You can now use the command propstatinstaller to launch the application installer."
printf '%s\n' "Use the command propstatinstaller to start an installation of a specific application."

while true; do
    printf "Do you accept want to install an Application now? (y/n): "
    read -r reply

    case "$reply" in
        y|Y|yes|YES|Yes)
            break
            propstatinstaller
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