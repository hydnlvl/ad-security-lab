# Scripts

Helper tooling for the lab.

## New-LabUsers.ps1

Bulk-creates AD users from `lab-users.csv`, so the attack scenarios have
a realistic population to target. CSV columns: `FirstName`, `LastName`, `Department`, `OU`.

Run on the Domain Controller in an elevated PowerShell session:

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\New-LabUsers.ps1
```

Passwords are hardcoded, weak, and lab-only.
