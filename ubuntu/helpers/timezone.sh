#!/bin/sh
set -eu

usage() {
    printf '%s\n' \
        "Usage: $0 [AREA/CITY]" \
        "       $0 --help" \
        "" \
        "Print the current system timezone and optionally change it." \
        "Use an IANA timezone such as Europe/Berlin or America/New_York."
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

case $# in
    0) ;;
    1)
        case $1 in
            --help|-h) usage; exit 0 ;;
            -*) fail "Unknown option: $1" ;;
        esac
        REQUESTED_TIMEZONE=$1
        ;;
    *) fail "Expected at most one timezone argument." ;;
esac

if ! command -v timedatectl >/dev/null 2>&1; then
    fail "timedatectl is required but was not found."
fi

CURRENT_TIMEZONE=$(timedatectl show --property=Timezone --value) ||
    fail "Could not read the current system timezone."
printf 'Current timezone: %s\n' "$CURRENT_TIMEZONE"

if [ "$#" -eq 0 ]; then
    if [ -r /usr/bin/confirm_continue ]; then
        . /usr/bin/confirm_continue
    else
        SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
        if [ ! -r "${SCRIPT_DIR}/confirm_continue.sh" ]; then
            fail "The confirmation helper was not found."
        fi
        . "${SCRIPT_DIR}/confirm_continue.sh"
    fi

    if ! command -v confirm_continue >/dev/null 2>&1; then
        fail "The confirmation helper did not define confirm_continue."
    fi

    REQUEST_CHANGE=0
    confirm_continue -n \
        -startmsg="Would you like to change the timezone?" \
        -endmsg= \
        msg_yes="Timezone change selected." \
        msg_no="Timezone unchanged." \
        on_yes="REQUEST_CHANGE=1" \
        on_no="REQUEST_CHANGE=0"

    if [ "$REQUEST_CHANGE" -eq 0 ]; then
        exit 0
    fi

    printf '%s' "Enter an IANA timezone (for example Europe/Berlin): "
    if ! IFS= read -r REQUESTED_TIMEZONE; then
        fail "Could not read the timezone."
    fi
fi

TIMEZONES=$(timedatectl list-timezones) ||
    fail "Could not retrieve the available timezones."
if ! printf '%s\n' "$TIMEZONES" | grep -Fxq "$REQUESTED_TIMEZONE"; then
    fail "Unknown timezone: $REQUESTED_TIMEZONE"
fi

if [ "$CURRENT_TIMEZONE" = "$REQUESTED_TIMEZONE" ]; then
    printf '%s\n' "Timezone is already set to $REQUESTED_TIMEZONE."
    exit 0
fi

if [ "$(id -u)" -eq 0 ]; then
    timedatectl set-timezone "$REQUESTED_TIMEZONE" ||
        fail "Could not set the timezone to $REQUESTED_TIMEZONE."
else
    if ! command -v sudo >/dev/null 2>&1; then
        fail "Root privileges are required to change the timezone, and sudo was not found."
    fi
    sudo timedatectl set-timezone "$REQUESTED_TIMEZONE" ||
        fail "Could not set the timezone to $REQUESTED_TIMEZONE."
fi

printf 'Timezone changed to %s.\n' "$REQUESTED_TIMEZONE"