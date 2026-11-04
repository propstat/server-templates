#!/bin/sh
set -eu

SERVICE_NAME="propstat-autoupdate"
COMMAND_PATH="/usr/local/bin/autoupdate"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_FILE="${SYSTEMD_DIR}/${SERVICE_NAME}.service"
TIMER_FILE="${SYSTEMD_DIR}/${SERVICE_NAME}.timer"

usage() {
    printf '%s\n' \
        "Usage: $0 [--frequency daily|weekly] [--time HH:MM]" \
        "       $0 --help" \
        "" \
        "Schedule automatic Ubuntu package upgrades followed by a reboot." \
        "Omitted options are requested interactively." \
        "The time is local 24-hour time."
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

run_updates() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "The automatic update service must run as root."
    fi

    [ -x /usr/bin/apt-get ] || fail "apt-get was not found at /usr/bin/apt-get."
    [ -x /usr/sbin/reboot ] || fail "reboot was not found at /usr/sbin/reboot."

    DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get update
    DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get -y full-upgrade
    /usr/sbin/reboot
}

if [ "${1:-}" = "--run" ]; then
    [ "$#" -eq 1 ] || fail "Unexpected arguments for --run."
    run_updates
    exit 0
fi

FREQUENCY=
TIME=

while [ "$#" -gt 0 ]; do
    case $1 in
        --frequency)
            [ "$#" -ge 2 ] || fail "--frequency requires daily or weekly."
            [ -z "$FREQUENCY" ] || fail "--frequency may only be specified once."
            FREQUENCY=$2
            shift 2
            ;;
        --time)
            [ "$#" -ge 2 ] || fail "--time requires a time in HH:MM format."
            [ -z "$TIME" ] || fail "--time may only be specified once."
            TIME=$2
            shift 2
            ;;
        --help|-h)
            [ "$#" -eq 1 ] || fail "--help cannot be combined with other options."
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

if [ -z "$FREQUENCY" ]; then
    while :; do
        printf '%s\n' \
            "Choose the update frequency:" \
            "  1) daily" \
            "  2) weekly"
        printf '%s' "Frequency [1/2]: "
        if ! IFS= read -r FREQUENCY; then
            fail "Could not read the update frequency from input."
        fi

        case $FREQUENCY in
            1|daily) FREQUENCY=daily; break ;;
            2|weekly) FREQUENCY=weekly; break ;;
            *) printf '%s\n' "Please enter 1 (daily) or 2 (weekly)." >&2 ;;
        esac
    done
else
    case $FREQUENCY in
        daily|weekly) ;;
        *) fail "Frequency must be daily or weekly." ;;
    esac
fi

if [ -z "$TIME" ]; then
    while :; do
        printf '%s\n' \
            "Enter the local time using 24-hour HH:MM format (hours 00-23, minutes 00-59)." \
            "For example, enter 16:30 for 4:30 PM or 03:30 for 3:30 AM."
        printf '%s' "Time [HH:MM]: "
        if ! IFS= read -r TIME; then
            fail "Could not read the update time from input."
        fi

        case $TIME in
            [0-2][0-9]:[0-5][0-9]) ;;
            *) printf '%s\n' "Invalid time. Use 24-hour HH:MM format, for example 03:30." >&2; continue ;;
        esac

        HOUR=${TIME%:*}
        case $HOUR in
            0[0-9]|1[0-9]|2[0-3]) break ;;
            *) printf '%s\n' "Invalid hour. Enter a value from 00 to 23." >&2 ;;
        esac
    done
else
    case $TIME in
        [0-2][0-9]:[0-5][0-9]) ;;
        *) fail "Time must use 24-hour HH:MM format, for example 03:30." ;;
    esac

    HOUR=${TIME%:*}
    case $HOUR in
        0[0-9]|1[0-9]|2[0-3]) ;;
        *) fail "Hour must be between 00 and 23." ;;
    esac
fi

SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "$0")"
[ -f "$SCRIPT_PATH" ] || fail "Cannot locate the update script: $SCRIPT_PATH"

if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        fail "Root privileges are required; sudo was not found."
    fi

    printf '%s\n' "Root privileges are required; requesting sudo." >&2
    sudo -v || fail "Could not authenticate with sudo."
    exec sudo -n -- "$SCRIPT_PATH" --frequency "$FREQUENCY" --time "$TIME"
fi

for command_name in install ln systemctl; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "Required command not found: $command_name"
done

[ -x /usr/bin/apt-get ] || fail "apt-get was not found at /usr/bin/apt-get."
[ -x /usr/sbin/reboot ] || fail "reboot was not found at /usr/sbin/reboot."
[ -d "$SYSTEMD_DIR" ] || fail "systemd unit directory not found: $SYSTEMD_DIR"

if [ ! -x "$COMMAND_PATH" ]; then
    ln -sfn "$SCRIPT_PATH" "$COMMAND_PATH" ||
        fail "Could not link the update command at $COMMAND_PATH."
fi

case $FREQUENCY in
    daily) CALENDAR="*-*-* ${TIME}:00" ;;
    weekly) CALENDAR="Mon *-*-* ${TIME}:00" ;;
esac

TMP_DIR=$(mktemp -d) || fail "Could not create temporary files."
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

cat > "${TMP_DIR}/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Update Ubuntu packages and reboot

[Service]
Type=oneshot
ExecStart=${COMMAND_PATH} --run
TimeoutStartSec=infinity
EOF

cat > "${TMP_DIR}/${SERVICE_NAME}.timer" <<EOF
[Unit]
Description=Scheduled Propstat automatic updates

[Timer]
OnCalendar=${CALENDAR}
Persistent=false

[Install]
WantedBy=timers.target
EOF

install -o root -g root -m 644 "${TMP_DIR}/${SERVICE_NAME}.service" "$SERVICE_FILE" ||
    fail "Could not install the systemd service."
install -o root -g root -m 644 "${TMP_DIR}/${SERVICE_NAME}.timer" "$TIMER_FILE" ||
    fail "Could not install the systemd timer."

systemctl daemon-reload ||
    fail "systemd could not reload its unit configuration."
systemctl enable --now "${SERVICE_NAME}.timer" ||
    fail "Could not enable and start the automatic update timer."

printf 'Automatic updates are scheduled %s at %s local time. Each run upgrades packages and reboots the machine.\n' \
    "$FREQUENCY" "$TIME"