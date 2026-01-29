# Internet Speed Limiting Scripts

A set of scripts for limiting internet download speed with local traffic exclusion.

## Description

The scripts use `tc` (traffic control) and `iptables` to limit incoming internet traffic speed. Local traffic (within local networks) is not limited.

### Features

- Only download from the internet is limited
- Local traffic is not limited (networks 172.16.0.0/16 and 10.0.0.0/8)
- Uses IFB (Intermediate Functional Block) for limiting incoming traffic
- Automatic network interface detection

## Files

- `limit-on.sh` - enables speed limiting
- `limit-off.sh` - disables speed limiting

## Usage

### Manual Control

Enable limiting:
```bash
sudo ./limit-on.sh
```

Disable limiting:
```bash
sudo ./limit-off.sh
```

### Configuration

You can modify parameters in `limit-on.sh`:

```bash
LAN_NETS="172.16.0.0/16 10.0.0.0/8"  # Local networks (not limited)
RATE="30000kbit"                       # Limiting speed (30 Mbps)
BURST="10k"                            # Burst size
```

## Automatic Management via cron

### Example: enable at 7:00, disable at 20:00

Add the following lines to crontab (run `crontab -e`):

```bash
# Enable speed limiting at 7:00 every day
0 7 * * * /path/to/directory/speed-limit/limit-on.sh >> /var/log/speed-limit.log 2>&1

# Disable speed limiting at 20:00 every day
0 20 * * * /path/to/directory/speed-limit/limit-off.sh >> /var/log/speed-limit.log 2>&1
```

### Alternative with full paths

If scripts require full paths or run as root:

```bash
# Enable speed limiting at 7:00 every day
0 7 * * * /bin/bash /path/to/directory/speed-limit/limit-on.sh >> /var/log/speed-limit.log 2>&1

# Disable speed limiting at 20:00 every day
0 20 * * * /bin/bash /path/to/directory/speed-limit/limit-off.sh >> /var/log/speed-limit.log 2>&1
```

### Setting up cron for root

If scripts must run as root (usually required for `tc` and `iptables`):

```bash
sudo crontab -e
```

And add:

```bash
# Enable speed limiting at 7:00 every day
0 7 * * * /bin/bash /path/to/directory/speed-limit/limit-on.sh >> /var/log/speed-limit.log 2>&1

# Disable speed limiting at 20:00 every day
0 20 * * * /bin/bash /path/to/directory/speed-limit/limit-off.sh >> /var/log/speed-limit.log 2>&1
```

### Checking cron operation

Check cron logs:
```bash
grep speed-limit /var/log/syslog
# or
journalctl -u cron | grep speed-limit
```

Check active cron tasks:
```bash
crontab -l
# or for root
sudo crontab -l
```

## Status Check

Check active limits:
```bash
tc qdisc show dev <interface>
tc qdisc show dev ifb0
```

Check iptables rules:
```bash
iptables -t mangle -L -n -v
```

## Requirements

- Linux with `tc` (traffic control) support
- `ifb` kernel module
- Root privileges to run scripts
- `iptables` or `nftables` (with iptables-nft support)

## Notes

- Scripts automatically detect network interface by IP address from 172.16.x.x network
- On startup, scripts clear previous settings before applying new ones
- Local traffic is determined by networks specified in `LAN_NETS` variable
