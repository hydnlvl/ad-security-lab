# Scenario 01: RDP Brute Force - Attack, Detection & Evasion

**MITRE ATT&CK:** T1110.001 Brute Force: Password Guessing **Attacker:** Kali 192.168.10.250 → **Target:** target (Windows 11, 192.168.10.100) over RDP **Tools:** Hydra (crowbar first, see Deviations), rockyou.txt

**What I did:** ran the attack, found it with a manual search, turned that into a standing alert, tuned the alert to be realistic, then beat it to find where it’s blind.
## The Attack

Guessed the password for one RDP account (`rgrimes`) from Kali. Enabled RDP on the target and gave `rgrimes` remote access first. Made sure lockout was off for clean runs. Wordlist: `head -n20 rockyou.txt` with the real lab password appended so it hits.

```bash
hydra -l 'rgrimes' -P passwords.txt rdp://192.168.10.100
```

![[01-intial-attack.png]]
## What Splunk Caught

Searched for failed logons right after the run:

```spl
index=endpoint host="target" EventCode=4625
```

![[02-splunk-eventcode-4625.png]]

All hits were `rgrimes`, clustered within a few seconds. I then checked for the success:

```spl
index=endpoint host="target" EventCode=4624 Account_Name=rgrimes
```

![[03-splunk-logon-details.png]]

**15x 4625 at 2:44:47 PM, then one 4624 at 2:44:53 PM** (6 sec later). The 4624 tied the success back to the attacker: Workstation `kali`, Source 192.168.10.250

This search only works because I knew when to look. An alert has to be setup to be detected on its own.

> Snapshot was rolled back after this run, so detection work below is on `tstark` (same setup, RDP-enabled account) rather than `rgrimes`.

## Detection - Alert v1

Turned the search into a saved, scheduled alert:

```spl
index=endpoint host=target EventCode=4625
| stats count min(_time) as first_seen max(_time) as last_seen by Account_Name, Source_Network_Address
| where count >= 5
```

**Alert settings:** Cron `*/5 * * * *`, 15-min window, trigger on results > 0, severity High.

Confirmed it fires on a normal Hydra run:
![[04-alert-triggered.png]]

5-in-15-min is unrealistic. Real users can fail logins within that window. Retuned alert to **10 failures in 5 min**:

```spl
index=endpoint host=target EventCode=4625 earliest=-5m@m latest=now
| stats count min(_time) as first_seen max(_time) as last_seen by Account_Name, Source_Network_Address
| where count >= 10
```

Confirmed v2 still fires on the fast attack.

## Evasion - Low and slow

Space guesses out so no 5-min window ever holds 10.

```bash
head -n 15 rockyou.txt > passwords.txt
hydra -l 'tstark' -P passwords.txt -t 1 -W 40 rdp://192.168.10.100
```

**Evaded.** Per-window counts never reached 10, so alert never triggered.

```spl
index=endpoint host=target EventCode=4625 Account_Name=tstark earliest=-20m@m latest=now
| timechart span=5m count
```

![[05-evasion-logs.png]]

| 5-min bin | 13:45 | 13:50 | 13:55 | 14:00 |
| --------- | ----- | ----- | ----- | ----- |
| failures  | 3     | 3     | 6     | 2     |

**Fix:** detect gaps between failures or use a much longer window, both of which can raise false positives. The threshold is always a tradeoff between catching slow attacks and alerting on normal user error.

## Evasion — Password Spray

Spray one password against many accounts. The alert counts failures *per account*, so one guess each spreads the failures too thin to cross the threshold.

```bash
hydra -L users.txt -p 'password123' rdp://192.168.10.100
```

9 accounts hit from one IP, each at 1-2 failures, none near 10:

```spl
index=endpoint host=target EventCode=4625 Source_Network_Address=192.168.10.250 earliest=-5m@m latest=now
| stats count by Account_Name
```

![[06-spray-per-account.png]]

Alert triggered, but only on the blank `-` account: each failure is additionally logged under an account with no name. The blank copies pooled past 10. This is a property of the logging, not spray detection. The rule counts per account, not per source IP.

**Fix:** detect one source hitting many distinct accounts, instead of counting per account.

```spl
index=endpoint host=target EventCode=4625 earliest=-15m@m latest=now
| stats dc(Account_Name) as distinct_accounts values(Account_Name) as accounts by Source_Network_Address
| where distinct_accounts >= 5
```

## Troubleshooting

- **Alert didn't fire at first:** saved as cron `0 6 * * 1` (Mondays 6 AM) with a 24h range. Defaults clicked past in the dialog. Schedule and window have to match. Fixed to `*/5` + 5-min.
- Clock offset (initial attack only): pre-NTP-sync, Kali and Windows clocks differed ~1hr, so the attack screenshots’ timestamps don’t match. Correlated by IP + sequence; detection work is post-sync.