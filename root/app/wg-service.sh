#!/bin/bash
# /app/wg-service.sh
set -e

WG_IF="wg0"
CONFIG="/config/wg_confs/${WG_IF}.conf"

action=$1

is_running() {
    ip link show "$WG_IF" &>/dev/null
}

case "$action" in
    start)
        if is_running; then
            echo "WireGuard is already running."
            exit 10 # Code 10 = Already Running
        fi

        echo "Starting WireGuard..."
        wg-quick up "$CONFIG"
        exit 0
        ;;

    stop)
        if ! is_running; then
            echo "WireGuard is not running."
            exit 11 # Code 11 = Not Running
        fi

        echo "Stopping WireGuard..."
        wg-quick down "$CONFIG"
        exit 0
        ;;

    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac