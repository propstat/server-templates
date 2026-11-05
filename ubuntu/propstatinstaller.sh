#!/bin/sh
set -eu

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

printf '%s\n' "Starting Propstat installer..."

printf '%s\n' "You have finished the installation."