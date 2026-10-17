#!/bin/sh
# cf_ip.sh — Provide Cloudflare IP ranges for Nginx configuration
# Source this file: . ./cf-ip.sh

set -eu

# Configuration
CONFIG_DIR="/etc/propstat/global"
IPV4_FILE="${CONFIG_DIR}/cfipv4"
IPV6_FILE="${CONFIG_DIR}/cfipv6"

IPV4_URL="https://www.cloudflare.com/ips-v4/"
IPV6_URL="https://www.cloudflare.com/ips-v6/"

LOG_TAG="propstat-cfips"

# Write messages to the system journal via syslog.
log() {
    priority=$1
    shift
    logger -p "daemon.${priority}" -t "$LOG_TAG" -- "$*"
}

# Log unexpected script termination.
on_exit() {
    status=$?
    if [ "$status" -ne 0 ]; then
        log err "Script terminated with exit status ${status}"
    fi
}

trap on_exit EXIT

log info "Starting Cloudflare IP range update"

# Ensure curl, logger, nginx and systemctl are available.
for cmd in curl logger cmp install mktemp nginx systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log err "Required command not found: $cmd"
        exit 1
    fi
done

# Create directory and cache files with public read permissions.
if ! install -d -o root -g root -m 755 "$CONFIG_DIR"; then
    log err "Failed to create configuration directory: $CONFIG_DIR"
    exit 1
fi

if [ ! -f "$IPV4_FILE" ]; then
    if ! install -o root -g root -m 644 /dev/null "$IPV4_FILE"; then
        log err "Failed to create $IPV4_FILE"
        exit 1
    fi
fi

if [ ! -f "$IPV6_FILE" ]; then
    if ! install -o root -g root -m 644 /dev/null "$IPV6_FILE"; then
        log err "Failed to create $IPV6_FILE"
        exit 1
    fi
fi

if ! chmod 755 "$CONFIG_DIR" ||
   ! chmod 644 "$IPV4_FILE" "$IPV6_FILE"; then
    log err "Failed to set configuration permissions"
    exit 1
fi

# Create temporary files and clean them up on exit.
TMP_IPV4=$(mktemp) || {
    log err "Failed to create temporary IPv4 file"
    exit 1
}

TMP_IPV6=$(mktemp) || {
    rm -f "$TMP_IPV4"
    log err "Failed to create temporary IPv6 file"
    exit 1
}

cleanup() {
    rm -f "$TMP_IPV4" "$TMP_IPV6"
}

trap cleanup EXIT HUP INT TERM

# Download Cloudflare IPv4 ranges.
if ! curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 \
    "$IPV4_URL" -o "$TMP_IPV4" 2>&1; then
    log err "Failed to download Cloudflare IPv4 ranges"
    exit 1
fi

# Download Cloudflare IPv6 ranges.
if ! curl --fail --silent --show-error --location \
    --proto '=https' --tlsv1.2 \
    "$IPV6_URL" -o "$TMP_IPV6" 2>&1; then
    log err "Failed to download Cloudflare IPv6 ranges"
    exit 1
fi

# Reject empty downloads.
if [ ! -s "$TMP_IPV4" ] || [ ! -s "$TMP_IPV6" ]; then
    log err "Cloudflare returned an empty IP range list"
    exit 1
fi

CHANGED=0

# Compare and update IPv4 ranges.
if ! cmp -s "$IPV4_FILE" "$TMP_IPV4"; then
    if install -o root -g root -m 644 "$TMP_IPV4" "$IPV4_FILE"; then
        log notice "Updated Cloudflare IPv4 ranges"
        CHANGED=1
    else
        log err "Failed to update $IPV4_FILE"
        exit 1
    fi
fi

# Compare and update IPv6 ranges.
if ! cmp -s "$IPV6_FILE" "$TMP_IPV6"; then
    if install -o root -g root -m 644 "$TMP_IPV6" "$IPV6_FILE"; then
        log notice "Updated Cloudflare IPv6 ranges"
        CHANGED=1
    else
        log err "Failed to update $IPV6_FILE"
        exit 1
    fi
fi

# Validate and restart Nginx only if ranges changed.
if [ "$CHANGED" -eq 1 ]; then
    log info "Validating Nginx configuration"

    if nginx -t 2>&1; then
        if systemctl restart nginx 2>&1; then
            log info "Nginx restarted successfully"
        else
            log err "Failed to restart Nginx"
            exit 1
        fi
    else
        log err "Nginx configuration validation failed; service not restarted"
        exit 1
    fi
else
    log info "Cloudflare IP ranges unchanged; Nginx restart not required"
fi

log info "Cloudflare IP range update completed"
exit 0