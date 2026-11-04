#!/bin/sh
set -eu

CONFIG_DIR="/etc/netplan"
CONFIG_PREFIX="99-propstat"
CONFIG_MARKER="# Managed by Propstat change_ip.sh"
ROLLBACK_TIMEOUT=120

usage() {
    printf '%s\n' \
        "Usage: $0 [--list|--help]" \
        "" \
        "List interface IP addresses and interactively configure a physical Ethernet adapter." \
        "Address changes are tested with Netplan and automatically roll back unless confirmed."
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

list_addresses() {
    command -v ip >/dev/null 2>&1 || fail "The ip command was not found."
    printf '%s\n' "Interface addresses:"
    ip -brief address show
}

case ${1:-} in
    --help|-h)
        [ "$#" -eq 1 ] || fail "--help cannot be combined with other options."
        usage
        exit 0
        ;;
    --list)
        [ "$#" -eq 1 ] || fail "--list cannot be combined with other options."
        list_addresses
        exit 0
        ;;
    "")
        ;;
    *)
        fail "Unknown option: $1"
        ;;
esac

for command_name in ip netplan awk grep mktemp install tee; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "Required command not found: $command_name"
done

if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        fail "Root privileges are required to change network settings; sudo was not found."
    fi

    printf '%s\n' "Root privileges are required to change network settings." >&2
    sudo -v || fail "Could not authenticate with sudo."
    exec sudo -n -- "$0" "$@"
fi

[ -d "$CONFIG_DIR" ] || fail "Netplan configuration directory not found: $CONFIG_DIR"

list_addresses
printf '\n%s\n' \
    "This helper configures physical Ethernet adapters only." \
    "Netplan will apply the change temporarily and roll it back unless confirmed within ${ROLLBACK_TIMEOUT} seconds."

INTERFACES=$(ip -o link show | awk -F': ' '$2 != "lo" { sub(/@.*/, "", $2); print $2 }')
[ -n "$INTERFACES" ] || fail "No network interfaces were found."

printf '%s\n' "Available interface names:"
printf '  %s\n' "$INTERFACES"
printf '%s' "Adapter to configure: "
if ! IFS= read -r INTERFACE; then
    fail "Could not read the adapter name."
fi

case $INTERFACE in
    ""|*[!a-zA-Z0-9_.-]*)
        fail "Invalid adapter name: $INTERFACE"
        ;;
esac

if ! printf '%s\n' "$INTERFACES" | grep -Fxq "$INTERFACE"; then
    fail "Adapter not found: $INTERFACE"
fi

if [ -d "/sys/class/net/${INTERFACE}/wireless" ]; then
    fail "Wireless adapters are not supported by this helper."
fi
if [ ! -e "/sys/class/net/${INTERFACE}/device" ]; then
    fail "Only physical Ethernet adapters are supported; $INTERFACE does not appear to be one."
fi

read_mode() {
    family=$1
    while :; do
        printf '%s\n' \
            "Configure IPv${family}:" \
            "  1) DHCP" \
            "  2) Static address" \
            "  3) Disable IPv${family}"
        printf '%s' "Choice [1-3]: "
        if ! IFS= read -r MODE; then
            fail "Could not read the IPv${family} configuration choice."
        fi

        case $MODE in
            1) MODE=dhcp; return ;;
            2) MODE=static; return ;;
            3) MODE=disabled; return ;;
            *) printf '%s\n' "Please enter 1, 2, or 3." >&2 ;;
        esac
    done
}

read_optional_network_value() {
    prompt=$1
    printf '%s' "$prompt"
    if ! IFS= read -r input_value; then
        fail "Could not read network configuration input."
    fi
    case $input_value in
        *[!0-9a-fA-F:./]*)
            fail "Invalid characters in network value."
            ;;
    esac
    REPLY=$input_value
}

read_mode 4
IPV4_MODE=$MODE
IPV4_ADDRESS=
IPV4_GATEWAY=
if [ "$IPV4_MODE" = static ]; then
    read_optional_network_value \
        "IPv4 address with prefix (for example 192.0.2.10/24): "
    IPV4_ADDRESS=$REPLY
    case $IPV4_ADDRESS in
        */*) ;;
        *) fail "IPv4 address must include a CIDR prefix, for example /24." ;;
    esac
    [ -n "$IPV4_ADDRESS" ] || fail "IPv4 address cannot be empty."
    read_optional_network_value "IPv4 gateway (leave blank for none): "
    IPV4_GATEWAY=$REPLY
fi

read_mode 6
IPV6_MODE=$MODE
IPV6_ADDRESS=
IPV6_GATEWAY=
if [ "$IPV6_MODE" = static ]; then
    read_optional_network_value \
        "IPv6 address with prefix (for example 2001:db8::10/64): "
    IPV6_ADDRESS=$REPLY
    case $IPV6_ADDRESS in
        */*) ;;
        *) fail "IPv6 address must include a CIDR prefix, for example /64." ;;
    esac
    [ -n "$IPV6_ADDRESS" ] || fail "IPv6 address cannot be empty."
    read_optional_network_value "IPv6 gateway (leave blank for none): "
    IPV6_GATEWAY=$REPLY
fi

DNS_SERVERS=
printf '%s' "DNS server IPs, comma-separated (leave blank to use DNS from the existing config or DHCP): "
if ! IFS= read -r DNS_SERVERS; then
    fail "Could not read DNS server input."
fi
case $DNS_SERVERS in
    *[!0-9a-fA-F:.,]*)
        fail "DNS servers must be IP addresses separated by commas."
        ;;
esac

TMP_DIR=$(mktemp -d) || fail "Could not create temporary files."
CONFIG_FILE="${TMP_DIR}/netplan.yaml"
PERSISTENT_FILE="${CONFIG_DIR}/${CONFIG_PREFIX}-${INTERFACE}.yaml"
BACKUP_FILE="${TMP_DIR}/previous.yaml"
HAD_PREVIOUS=0
RESTORE_PENDING=0

restore_previous_config() {
    if [ "$RESTORE_PENDING" -eq 1 ]; then
        if [ "$HAD_PREVIOUS" -eq 1 ]; then
            install -o root -g root -m 600 "$BACKUP_FILE" "$PERSISTENT_FILE"
        else
            rm -f "$PERSISTENT_FILE"
        fi
        netplan generate && netplan apply
        RESTORE_PENDING=0
    fi
}

cleanup() {
    restore_previous_config
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [ -e "$PERSISTENT_FILE" ]; then
    if ! grep -Fxq "$CONFIG_MARKER" "$PERSISTENT_FILE"; then
        fail "Refusing to overwrite an unmanaged Netplan file: $PERSISTENT_FILE"
    fi
    cp -p "$PERSISTENT_FILE" "$BACKUP_FILE" ||
        fail "Could not back up the existing Propstat network configuration."
    HAD_PREVIOUS=1
fi

{
    printf '%s\n' "$CONFIG_MARKER" "network:" "  version: 2" "  ethernets:" "    ${INTERFACE}:"

    case $IPV4_MODE in
        dhcp) printf '%s\n' "      dhcp4: true" ;;
        *) printf '%s\n' "      dhcp4: false" ;;
    esac

    case $IPV6_MODE in
        dhcp)
            printf '%s\n' "      dhcp6: true" "      accept-ra: true"
            ;;
        *)
            printf '%s\n' "      dhcp6: false" "      accept-ra: false"
            ;;
    esac

    if [ "$IPV4_MODE" = static ] || [ "$IPV6_MODE" = static ]; then
        printf '%s\n' "      addresses:"
        [ "$IPV4_MODE" != static ] || printf "        - '%s'\n" "$IPV4_ADDRESS"
        [ "$IPV6_MODE" != static ] || printf "        - '%s'\n" "$IPV6_ADDRESS"
    fi

    if [ -n "$IPV4_GATEWAY" ] || [ -n "$IPV6_GATEWAY" ]; then
        printf '%s\n' "      routes:"
        [ -z "$IPV4_GATEWAY" ] || {
            printf '%s\n' "        - to: 0.0.0.0/0"
            printf "          via: '%s'\n" "$IPV4_GATEWAY"
        }
        [ -z "$IPV6_GATEWAY" ] || {
            printf '%s\n' "        - to: ::/0"
            printf "          via: '%s'\n" "$IPV6_GATEWAY"
        }
    fi

    if [ -n "$DNS_SERVERS" ]; then
        printf '%s\n' "      nameservers:" "        addresses:"
        OLD_IFS=$IFS
        IFS=,
        for DNS_SERVER in $DNS_SERVERS; do
            [ -n "$DNS_SERVER" ] || fail "DNS server list contains an empty entry."
            printf "          - '%s'\n" "$DNS_SERVER"
        done
        IFS=$OLD_IFS
    fi
} > "$CONFIG_FILE"

chmod 600 "$CONFIG_FILE"
mkdir -p "${TMP_DIR}/etc/netplan"
cp "$CONFIG_FILE" "${TMP_DIR}/etc/netplan/${CONFIG_PREFIX}-${INTERFACE}.yaml"
if ! netplan generate --root-dir "$TMP_DIR"; then
    fail "Netplan rejected the generated configuration."
fi

if [ "$HAD_PREVIOUS" -eq 1 ]; then
    rm -f "$PERSISTENT_FILE"
fi
RESTORE_PENDING=1

printf '\n%s\n' "Testing the proposed network configuration."
if ! netplan try --config-file "$CONFIG_FILE" --timeout "$ROLLBACK_TIMEOUT" 2>&1 |
    tee "${TMP_DIR}/netplan-try.log"; then
    restore_previous_config
    fail "Netplan could not apply the proposed configuration; the previous configuration was restored."
fi
if ! grep -Fxq "Configuration accepted." "${TMP_DIR}/netplan-try.log"; then
    restore_previous_config
    fail "The network configuration was not confirmed; the previous configuration was restored."
fi

install -o root -g root -m 600 "$CONFIG_FILE" "$PERSISTENT_FILE" ||
    fail "Could not persist the network configuration; restoring the previous configuration."

if ! netplan generate || ! netplan apply; then
    restore_previous_config
    fail "Could not persistently apply the network configuration; the previous configuration was restored."
fi

RESTORE_PENDING=0
printf 'Network configuration for %s saved in %s.\n' "$INTERFACE" "$PERSISTENT_FILE"