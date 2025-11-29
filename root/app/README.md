Absolutely! Now that you have switched the system to a **lean Java class** and **intelligent shell scripts**, clear documentation of the scripts makes a lot of sense.

Here is a simple and compact `README.md` specifically for the new scripts `$wg-service.sh` and `$wg-peers.sh`.

-----

# WireGuard Management Scripts

These scripts serve as the primary interface for managing the WireGuard instance (`wg0`) and connected peers. They are designed to be called either directly from the command line or via a **Thin Java Wrapper** (e.g., `$WireGuardManager.java`).

## Script Overview

| Script | Description | Primary Purpose |
| :--- | :--- | :--- |
| **`wg-service.sh`** | Controls the WireGuard service. | **Start, Stop, Status Codes** |
| **`wg-peers.sh`** | Manages peers and provides data. | **Add, Remove, JSON List** |

-----

## 1. `wg-service.sh` (Service Control)

This script manages the **status** of the WireGuard interface (`wg0`). It uses specific **exit codes** to report status:

### Usage

```bash
# Start WireGuard
/app/wg-service.sh start

# Stop WireGuard
/app/wg-service.sh stop
```

### Exit Codes

| Code | Status | Meaning for Java/Caller |
| :--- | :--- | :--- |
| **0** | SUCCESS | Command executed successfully (Started / Stopped). |
| **10** | ALREADY_RUNNING | During **start**, detected that `wg0` is already running. |
| **11** | NOT_RUNNING | During **stop**, detected that `wg0` is already stopped. |
| **>0** | ERROR | A general error has occurred (e.g., configuration error). |

-----

## 2. `wg-peers.sh` (Peer Management & Data)

This script manages client configurations and provides active peer data in **JSON format**.

### Usage

#### A. Add Peer

```bash
# Add peer (IP is automatically assigned, e.g., 10.13.13.X)
/app/wg-peers.sh add <peer-name>

# Add peer with specific IP
/app/wg-peers.sh add <peer-name> <peer-ip>
```

  * **Action:** Creates keys, generates client files, and adds the peer to the server configuration (and adds it at runtime if WireGuard is active).
  * **Exit Code:** **0** on success.

#### B. Remove Peer

```bash
# Remove peer
/app/wg-peers.sh remove <peer-name>
```

  * **Action:** Removes the peer from the runtime instance (`wg0`) and deletes the entry from the server configuration.
  * **Exit Code:** **0** on success.

#### C. Get Peer List (JSON Output)

```bash
# Outputs the list of all active peers as a JSON array to stdout.
/app/wg-peers.sh list-json
```

  * **Action:** Reads the current runtime statistics from `wg show wg0 dump`, enriches them with status information (`isActive`), and formats the result as a single JSON array.
  * **Output:** A JSON array on `stdout` that can be directly deserialized by Java (via **Gson**).

**Example JSON Output:**

```json
[
    {
      "publicKey": "ABCDEF...",
      "psk": "GHIJKL...",
      "endpoint": "1.2.3.4:51820",
      "allowedIps": "10.13.13.2/32",
      "lastHandshake": 1732800000,
      "transferRx": 10240,
      "transferTx": 20480,
      "persistentKeepalive": 25,
      "isActive": true
    },
    ...
]
```

-----
