# Scenario 01: RDP Brute Force (Hydra)

**MITRE ATT&CK:** T1110.001 Brute Force: Password Guessing
**Attacker:** Kali Linux (192.168.10.250)
**Target:** target.adlab.local (Windows 11, 192.168.10.100), account `ADLAB\rgrimes` over RDP
**Tools:** Hydra (crowbar first, see below), rockyou.txt trimmed to 20 lines

## What I Did

Guessed the password for one RDP account (`rgrimes`) from Kali. Had to turn on RDP for the target and give `rgrimes` remote access first.

Wordlist: `head -n20 rockyou.txt`, then appended the real lab password so it would actually hit.

```bash
hydra -l 'rgrimes' -P passwords.txt rdp://192.168.10.100
```

![Attack execution](../screenshots/03-attacks/01-rdp-brute-force-execution.png)

Tried crowbar first since that's what the tutorial uses. It failed even on a password I already knew worked, leading me to swap to Hydra. (Details in Deviations.)

## Events Generated

| Event ID | What it means |
|---|---|
| 4625 | Failed logon, one per bad guess |
| 4624 | Successful logon |

Bunch of 4625s in a row, then one 4624 with the attacker's hostname (kali) and IP (192.168.10.250) on it.

## Splunk

Searched immediately after running the attack:

```spl
index=endpoint host="target" EventCode=4625
```

All hits were `rgrimes`, all within a few seconds of each other.

Then checked for the success:

```spl
index=endpoint host="target" EventCode=4624 Account_Name=rgrimes
```

![Splunk results](../screenshots/03-attacks/01-rdp-brute-force-splunk.png)

Results: 15x 4625 at 2:44:47 PM, then one 4624 at 2:44:53 PM (6 sec later). The 4624 had:

- Account Name: rgrimes
- Account Domain: ADLAB
- Workstation Name: kali
- Source Network Address: 192.168.10.250
- Auth Package: NTLM V2

![4624 success detail](../screenshots/03-attacks/01-rdp-brute-force-4624.png)

## Detection Idea (not built yet)

The search above only works because I knew when to look for events. For an actual alert:

```spl
index=endpoint host=target EventCode=4625
| stats count min(_time) max(_time) by Account_Name, Source_Network_Address
```

Set a threshold on count, bump severity if a matching 4624 follows.

## Takeaway

15 failed logins in a few seconds from a singular account and IP, then a success 6 sec later. This would not indicate a typo pattern. A real SOC analysist would check what the session did after login, check if 192.168.10.250 should even be hitting RDP on this box.

## Remediation

- Account lockout (off here on purpose, see caveats)
- NLA on RDP
- MFA
- Cut down who has RDP access
- Actually build the threshold alert above

## Deviations

Crowbar said "no results found" on a password I'd already logged in with manually via xfreerdp. Also finished all 20 attempts in under a second, too fast for real handshakes. Hydra 9.7 got it on the first pass. Kept the crowbar output as evidence but the documented attack is the Hydra run.

## Troubleshooting

Kali and the Windows VMs aren't NTP synced. Clocks are off by about an hour (Hydra said 15:47, Splunk's matching 4624 says 2:44:53 PM). Doesn't matter, events still line up by IP + order.

## Lab Caveats

Small wordlist, lockout off for a clean run, flat network, single box. Lab passwords only. Didn't reset the target between crowbar troubleshooting and the final run, Splunk results here are scoped to just the clean Hydra run's time window.
