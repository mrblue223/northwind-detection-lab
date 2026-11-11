# Adds Success auditing for the two extended rights that make DCSync
# possible (DS-Replication-Get-Changes and -All) on the domain object's
# SACL, for the "Everyone" principal. Without this, a DCSync-style
# replication request generates no distinguishing Event ID 4662 at all -
# this script is what makes detections/10-dcsync-rights-abuse.kql possible.
#
# This is the same underlying mechanism Microsoft Defender for Identity's
# DCSync alert relies on, built here from plain auditing instead of a
# dedicated identity-security product. Requires "Directory Service Access"
# auditing to also be enabled (see ansible/roles/audit_policy) - the SACL
# alone does nothing without that audit subcategory turned on.
#
# NOTE: pattern taken from widely published AD-hardening guidance using
# System.DirectoryServices.ActiveDirectoryAuditRule. Verify this runs
# cleanly against your actual domain functional level before relying on
# the resulting detection - see VALIDATION_NOTES.md.

Import-Module ActiveDirectory

$domainDN = (Get-ADDomain).DistinguishedName

$guidReplicationGetChanges    = [GUID]"1131f6aa-9c07-11d1-f79f-00c04fc2dcd2"
$guidReplicationGetChangesAll = [GUID]"1131f6ad-9c07-11d1-f79f-00c04fc2dcd2"

$everyone = New-Object System.Security.Principal.NTAccount("Everyone")
$sid      = $everyone.Translate([System.Security.Principal.SecurityIdentifier])

$acl = Get-Acl -Path "AD:\$domainDN"

$auditRule1 = New-Object System.DirectoryServices.ActiveDirectoryAuditRule(
    $sid, "ExtendedRight", "Success", $guidReplicationGetChanges
)
$auditRule2 = New-Object System.DirectoryServices.ActiveDirectoryAuditRule(
    $sid, "ExtendedRight", "Success", $guidReplicationGetChangesAll
)

$acl.AddAuditRule($auditRule1)
$acl.AddAuditRule($auditRule2)

Set-Acl -Path "AD:\$domainDN" -AclObject $acl

Write-Output "Replication-rights SACL audit entries added to $domainDN"
