# New-LabUsers.ps1 — create lab AD users from a CSV.
# Lab use only: passwords are weak by design. Run on the Domain Controller,
# in an elevated PowerShell session.

Import-Module ActiveDirectory

$users    = Import-Csv -Path .\lab-users.csv
$password = ConvertTo-SecureString 'LabPassw0rd!2026' -AsPlainText -Force

foreach ($user in $users) {
    # Logon name = first initial + last name, lowercased (e.g. James Smith -> jsmith)
    $sam = ($user.FirstName.Substring(0,1) + $user.LastName).ToLower()

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'") { continue }

    New-ADUser `
        -Name              "$($user.FirstName) $($user.LastName)" `
        -GivenName         $user.FirstName `
        -Surname           $user.LastName `
        -SamAccountName    $sam `
        -UserPrincipalName "$sam@adlab.local" `
        -Department        $user.Department `
        -Path              "OU=$($user.OU),DC=adlab,DC=local" `
        -AccountPassword   $password `
        -Enabled           $true

    Write-Host "Created $sam"
}
