#!/bin/bash
# /app/wg-peers.sh
set -e

WG_IF="wg0"
CONFIG="/config/wg_confs/${WG_IF}.conf"

action=$1
name=$2
ip=$3

# Helper function: JSON escaping (minimal)
json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

list_json() {
    # If WG is not running, return empty array
    if ! ip link show "$WG_IF" &>/dev/null; then
        echo "[]"
        exit 0
    fi

    local first=true
    local json_array="["
    local skip_first=true  # Skip the interface line (first line of wg show dump)

    # "wg show dump" provides tab-separated values:
    # First line: INTERFACE PRIVATE_KEY LISTEN_PORT FWMARK
    # Following lines: PUBLIC_KEY PSK ENDPOINT ALLOWED_IPS LATEST_HANDSHAKE RX TX KEEPALIVE
    while IFS=$'\t' read -r pub psk endpoint allowed_ips handshake rx tx keepalive; do
        # Skip empty lines
        [ -z "$pub" ] && continue

        # Skip the interface line (it's not a peer)
        if [ "$skip_first" = true ]; then
            skip_first=false
            continue
        fi

        # Ensure numeric fields have valid values, replace non-numeric with 0
        handshake=${handshake:-0}
        rx=${rx:-0}
        tx=${tx:-0}
        keepalive=${keepalive:-0}

        # Replace 'off' with 0 for numeric fields
        [[ "$handshake" == "off" ]] && handshake=0
        [[ "$rx" == "off" ]] && rx=0
        [[ "$tx" == "off" ]] && tx=0
        [[ "$keepalive" == "off" ]] && keepalive=0

        # Calculate time
        now=$(date +%s)
        diff=$((now - handshake))
        isActive="false"
        if [ "$handshake" -ne 0 ] && [ "$diff" -lt 180 ]; then
            isActive="true"
        fi

        # Add comma before new element (not before first)
        if [ "$first" = true ]; then
            first=false
        else
            json_array+=","
        fi

        # Build JSON object
        json_array+="
    {
      \"publicKey\": \"$(json_escape "$pub")\",
      \"psk\": \"$(json_escape "$psk")\",
      \"endpoint\": \"$(json_escape "$endpoint")\",
      \"allowedIps\": \"$(json_escape "$allowed_ips")\",
      \"lastHandshake\": $handshake,
      \"transferRx\": $rx,
      \"transferTx\": $tx,
      \"persistentKeepalive\": $keepalive,
      \"isActive\": $isActive
    }"

    done < <(wg show "$WG_IF" dump)

    json_array+="
]"
    echo "$json_array"
}

add_peer() {
    local peer_name="$1"
    local peer_ip="$2"

    # Validate peer name
    if [ -z "$peer_name" ]; then
        echo "Error: peer name is required"
        exit 1
    fi

    # Check if peer already exists
    if grep -q "^# Peer: $peer_name$" "$CONFIG"; then
        echo "Error: Peer '$peer_name' already exists"
        exit 1
    fi

    # Create peer directory
    local peer_dir="/config/$peer_name"
    mkdir -p "$peer_dir"

    # Generate keys if they don't exist
    if [ ! -f "$peer_dir/privatekey-$peer_name" ]; then
        wg genkey | tee "$peer_dir/privatekey-$peer_name" | wg pubkey > "$peer_dir/publickey-$peer_name"
    fi

    if [ ! -f "$peer_dir/presharedkey-$peer_name" ]; then
        wg genpsk > "$peer_dir/presharedkey-$peer_name"
    fi

    # Get the keys
    local peer_pubkey=$(cat "$peer_dir/publickey-$peer_name")
    local peer_privkey=$(cat "$peer_dir/privatekey-$peer_name")
    local peer_psk=$(cat "$peer_dir/presharedkey-$peer_name")
    local server_pubkey=$(cat /config/server/publickey-server 2>/dev/null || echo "ERROR_NO_SERVER_KEY")

    # Assign IP if not provided
    if [ -z "$peer_ip" ]; then
        # Find the next available IP (simple increment from 10.13.13.2)
        local next_ip_num=2
        while grep -q "AllowedIPs = 10.13.13.$next_ip_num" "$CONFIG"; do
            ((next_ip_num++))
        done
        peer_ip="10.13.13.$next_ip_num"
    fi

    # Add peer to server config
    cat >> "$CONFIG" <<EOF

# Peer: $peer_name
[Peer]
PublicKey = $peer_pubkey
PresharedKey = $peer_psk
AllowedIPs = $peer_ip/32
EOF

    # Create peer config file (for downloading)
    local peer_config="/config/$peer_name/$peer_name.conf"
    local server_endpoint=$(hostname -i | awk '{print $1}')
    cat > "$peer_config" <<EOF
[Interface]
Address = $peer_ip/24
PrivateKey = $peer_privkey
ListenPort = 51820
DNS = 1.1.1.1

[Peer]
PublicKey = $server_pubkey
PresharedKey = $peer_psk
Endpoint = $server_endpoint:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    # Add peer to running interface if WireGuard is active
    if ip link show "$WG_IF" &>/dev/null; then
        wg set "$WG_IF" peer "$peer_pubkey" preshared-key <(cat "$peer_dir/presharedkey-$peer_name") allowed-ips "$peer_ip/32"
    fi

    # Success - output the peer name and IP (Java will fetch the config file)
    echo "OK:$peer_name:$peer_ip"
}

remove_peer() {
    local peer_name="$1"

    # Validate peer name
    if [ -z "$peer_name" ]; then
        echo "Error: peer name is required"
        exit 1
    fi

    # Check if peer exists
    if ! grep -q "^# Peer: $peer_name$" "$CONFIG"; then
        echo "Error: Peer '$peer_name' does not exist"
        exit 1
    fi

    # Get peer's public key for runtime removal
    local peer_pubkey=$(cat "/config/$peer_name/publickey-$peer_name" 2>/dev/null)

    # Remove peer from server config
    # This removes the peer section including the comment line
    sed -i "/^# Peer: $peer_name$/,/^$/d" "$CONFIG"

    # Remove peer from running interface if WireGuard is active and we have the pubkey
    if [ -n "$peer_pubkey" ] && ip link show "$WG_IF" &>/dev/null; then
        wg set "$WG_IF" peer "$peer_pubkey" remove || true
    fi

    # Remove peer directory
    rm -rf "/config/$peer_name"

    echo "Peer '$peer_name' removed successfully"
}

case "$action" in
    list-json)
        list_json
        ;;
    add)
        add_peer "$name" "$ip"
        ;;
    remove)
        remove_peer "$name"
        ;;
    *)
        echo "Usage: $0 {list-json|add <name> [ip]|remove <name>}"
        exit 1
        ;;
esac
