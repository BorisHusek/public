<#
.SYNOPSIS
    Connects to an Azure Storage Account using an Account Key and validates
    whether any blob containers exist inside it.

.DESCRIPTION
    This script authenticates to an Azure Storage Account using its name and
    access key (no Az module required — uses the Azure Storage REST API or
    the Az.Storage module if available). It then lists all blob containers
    and reports whether any exist.

.PARAMETER StorageAccountName
    The name of the Azure Storage Account.

.PARAMETER StorageAccountKey
    The storage account access key (Key1 or Key2).

.PARAMETER UseRestApi
    Switch to force use of the Azure Storage REST API instead of the Az.Storage
    PowerShell module. Useful when the Az module is not installed.

.EXAMPLE
    .\Validate-AzureStorageContainers.ps1 `
        -StorageAccountName "mystorageaccount" `
        -StorageAccountKey  "abc123...base64key=="

.EXAMPLE
    .\Validate-AzureStorageContainers.ps1 `
        -StorageAccountName "mystorageaccount" `
        -StorageAccountKey  "abc123...base64key==" `
        -UseRestApi

.NOTES
    Author  : Generated for Azure DevOps / Cloud Infrastructure use
    Requires: PowerShell 5.1+ or PowerShell 7+
              Az.Storage module (optional — falls back to REST API)
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Azure Storage Account name")]
    [ValidateNotNullOrEmpty()]
    [string] $StorageAccountName,

    [Parameter(Mandatory = $true, HelpMessage = "Storage Account access key (Key1 or Key2)")]
    [ValidateNotNullOrEmpty()]
    [string] $StorageAccountKey,

    [Parameter(Mandatory = $false, HelpMessage = "Force REST API instead of Az.Storage module")]
    [switch] $UseRestApi
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region ── Helper: Write-Status ──────────────────────────────────────────────
function Write-Status {
    param (
        [string] $Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")] [string] $Level = "INFO"
    )
    $colors = @{
        INFO    = "Cyan"
        SUCCESS = "Green"
        WARNING = "Yellow"
        ERROR   = "Red"
    }
    $prefix = @{
        INFO    = "[INFO]   "
        SUCCESS = "[OK]     "
        WARNING = "[WARN]   "
        ERROR   = "[ERROR]  "
    }
    Write-Host "$($prefix[$Level])$Message" -ForegroundColor $colors[$Level]
}
#endregion

#region ── Method 1: Az.Storage Module ───────────────────────────────────────
function Test-ContainersViaAzModule {
    param (
        [string] $AccountName,
        [string] $AccountKey
    )

    Write-Status "Using Az.Storage PowerShell module..."

    # Build a storage context using the account key (no Azure login required)
    $ctx = New-AzStorageContext `
        -StorageAccountName $AccountName `
        -StorageAccountKey  $AccountKey

    Write-Status "Storage context created for: $($ctx.StorageAccountName)"
    Write-Status "Blob endpoint: $($ctx.BlobEndPoint)"

    # List all containers
    Write-Status "Querying blob containers..."
    $containers = Get-AzStorageContainer -Context $ctx -ErrorAction Stop

    return $containers
}
#endregion

#region ── Method 2: Azure Storage REST API ──────────────────────────────────
function Test-ContainersViaRestApi {
    param (
        [string] $AccountName,
        [string] $AccountKey
    )

    Write-Status "Using Azure Storage REST API directly..."

    $method      = "GET"
    $requestDate = [DateTime]::UtcNow.ToString("R")
    $apiVersion  = "2020-08-04"
    $resource    = "/?comp=list"
    $uri         = "https://$AccountName.blob.core.windows.net/$resource"

    # ── Build the Shared Key signature ──────────────────────────────────────
    # Canonicalized headers
    $canonicalizedHeaders = "x-ms-date:$requestDate`nx-ms-version:$apiVersion"

    # Canonicalized resource
    $canonicalizedResource = "/$AccountName/`ncomp:list"

    # String to sign (REST Lite / Blob list)
    $stringToSign = @(
        $method,          # VERB
        "",               # Content-Encoding
        "",               # Content-Language
        "",               # Content-Length
        "",               # Content-MD5
        "",               # Content-Type
        "",               # Date (empty when x-ms-date is used)
        "",               # If-Modified-Since
        "",               # If-Match
        "",               # If-None-Match
        "",               # If-Unmodified-Since
        "",               # Range
        $canonicalizedHeaders,
        $canonicalizedResource
    ) -join "`n"

    # HMAC-SHA256 signature
    $keyBytes  = [Convert]::FromBase64String($AccountKey)
    $hmac      = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key  = $keyBytes
    $msgBytes  = [System.Text.Encoding]::UTF8.GetBytes($stringToSign)
    $sigBytes  = $hmac.ComputeHash($msgBytes)
    $signature = [Convert]::ToBase64String($sigBytes)

    $authHeader = "SharedKey ${AccountName}:${signature}"

    # ── Execute request ──────────────────────────────────────────────────────
    $headers = @{
        "x-ms-date"    = $requestDate
        "x-ms-version" = $apiVersion
        "Authorization" = $authHeader
    }

    Write-Status "Sending request to: $uri"

    $response = Invoke-WebRequest -Uri $uri -Method $method -Headers $headers -UseBasicParsing

    # ── Parse XML response ───────────────────────────────────────────────────
    [xml] $xml        = $response.Content
    $containerNodes   = $xml.EnumerationResults.Containers.Container

    return $containerNodes
}
#endregion

#region ── Main ──────────────────────────────────────────────────────────────
function Main {

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  Azure Storage Account — Container Validation Script" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""

    Write-Status "Target storage account : $StorageAccountName"
    Write-Host ""

    # ── Decide which method to use ───────────────────────────────────────────
    $azModuleAvailable = $null -ne (Get-Module -ListAvailable -Name Az.Storage)

    if ($UseRestApi -or -not $azModuleAvailable) {
        if (-not $azModuleAvailable) {
            Write-Status "Az.Storage module not found. Falling back to REST API." "WARNING"
        }
        try {
            $containers = Test-ContainersViaRestApi -AccountName $StorageAccountName -AccountKey $StorageAccountKey
        }
        catch {
            Write-Status "REST API request failed: $_" "ERROR"
            exit 1
        }
    }
    else {
        try {
            $containers = Test-ContainersViaAzModule -AccountName $StorageAccountName -AccountKey $StorageAccountKey
        }
        catch {
            Write-Status "Az.Storage module call failed: $_" "ERROR"
            Write-Status "Retrying with REST API fallback..." "WARNING"
            try {
                $containers = Test-ContainersViaRestApi -AccountName $StorageAccountName -AccountKey $StorageAccountKey
            }
            catch {
                Write-Status "REST API fallback also failed: $_" "ERROR"
                exit 1
            }
        }
    }

    # ── Evaluate results ─────────────────────────────────────────────────────
    Write-Host ""

    if ($null -eq $containers -or ($containers | Measure-Object).Count -eq 0) {
        Write-Status "Connection succeeded but NO containers were found in '$StorageAccountName'." "WARNING"
        Write-Host ""
        exit 0
    }

    $count = ($containers | Measure-Object).Count
    Write-Status "Connection succeeded. Found $count container(s) in '$StorageAccountName'." "SUCCESS"
    Write-Host ""

    # ── Print container table ────────────────────────────────────────────────
    Write-Host "  Container Name".PadRight(42) + "  Public Access" -ForegroundColor DarkGray
    Write-Host "  " + ("─" * 40) + "  " + ("─" * 14) -ForegroundColor DarkGray

    foreach ($c in $containers) {
        # Works for both Az module objects and REST API XML nodes
        if ($c -is [Microsoft.WindowsAzure.Commands.Common.Storage.ResourceModel.AzureStorageContainer]) {
            $name       = $c.Name
            $publicAccess = if ($c.PublicAccess) { $c.PublicAccess.ToString() } else { "Private" }
        }
        else {
            # XML node from REST API
            $name       = $c.Name
            $publicAccess = if ($c.Properties.PublicAccess) { $c.Properties.PublicAccess } else { "Private" }
        }
        Write-Host ("  " + $name.PadRight(40) + "  $publicAccess")
    }

    Write-Host ""
    Write-Status "Validation complete. Storage account is reachable and contains $count container(s)." "SUCCESS"
    Write-Host ""
}

Main
