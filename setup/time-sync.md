# Lab Setup: Time Synchronization

**Goal:** Keep all lab machines on the same accurate clock so Splunk timestamps and cross-host events line up.

**Design:** The Domain Controller is the lab's authoritative time source. The DC syncs to the public internet (`pool.ntp.org`), while every other machine syncs to the DC.

## Problem

Screenshots across hosts disagreed by ~1 hour (Kali terminal vs. Splunk timestamps). A later check found a Windows host a clean 2 hours behind real time.

## Root Cause

- **No NTP sync.** Hosts were never pointed at a common time source, so clocks drifted independently.
- **Paused VMs.** A paused VM's clock stops and resumes behind real time by exactly the pause duration.

## Fix

### Domain Controller (authoritative source)
```powershell
w32tm /config /manualpeerlist:"pool.ntp.org,0x8" /syncfromflags:manual /reliable:yes /update
Restart-Service w32time
w32tm /resync /force
w32tm /query /status      # Source should read pool.ntp.org
```

### Windows Target (domain-joined)
Syncs from the DC automatically.

### Kali
Kali uses `systemd-timesyncd`. Edit `/etc/systemd/timesyncd.conf`:
```ini
[Time]
NTP=192.168.10.7
```
```bash
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
```

### Splunk
Splunk (Ubuntu) uses `chrony`. The config uses a `sourcedir`, so add a source file rather than editing `chrony.conf`:
```bash
echo "server 192.168.10.7 iburst" | sudo tee /etc/chrony/sources.d/dc.sources
sudo chronyc reload sources
```
Public pool sources are left enabled alongside the DC as a fallback. The DC and pool resolve to the same real time.

### Timezone (all hosts) — Central Time
- Windows: `tzutil /s "Central Standard Time"`
- Linux: `sudo timedatectl set-timezone America/Chicago`
- Splunk UI: user → Preferences → Time zone → America/Chicago

`tzutil` changes the label only, not the clock. The clock is corrected via NTP above.

## Verification

**Windows Target**
```powershell
w32tm /stripchart /computer:192.168.10.7 /samples:3 /dataonly   # offsets < 1s
```

**Splunk (chrony)**
```bash
chronyc tracking      # offsets < 1s
```

**Kali / Splunk**
```bash
timedatectl           # "System clock synchronized: yes"
```