<#
.SYNOPSIS
Validates a final signed APK and creates the two V1 release metadata files.
.DESCRIPTION
Reads the APK, never pubspec.yaml. Requires an explicitly trusted released APK
or an independently verified signing-certificate SHA-256 and baseline code.
Does not build, modify, sign, copy, upload, or publish an APK.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ApkPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ReleaseTag,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ReleaseNotesPath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutputDirectory,
    [string]$BaselineApkPath,
    [string]$ExpectedSignerSha256,
    [Nullable[int]]$BaselineVersionCode,
    [string]$BuildToolsDirectory,
    [string]$AaptPath,
    [string]$ApkSignerPath,
    [DateTimeOffset]$PublishedAt = [DateTimeOffset]::UtcNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Get-InputFile([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label file does not exist: $Path"
    }
    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    if (-not [IO.Path]::IsPathRooted($resolved)) { throw "$Label must be a filesystem file." }
    return $resolved
}

function Get-ToolPath([string]$ExplicitPath, [string]$FileName) {
    if ([string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if ([string]::IsNullOrWhiteSpace($BuildToolsDirectory)) {
            throw 'Set BuildToolsDirectory, or explicitly provide both AaptPath and ApkSignerPath.'
        }
        $ExplicitPath = Join-Path $BuildToolsDirectory $FileName
    }
    return Get-InputFile $ExplicitPath $FileName
}

function Invoke-ApkTool([string]$ToolPath, [string[]]$ToolArguments) {
    # Reset the native/script exit code so PowerShell fixture tools can model errors.
    $global:LASTEXITCODE = 0
    $lines = @(& $ToolPath @ToolArguments 2>&1 | ForEach-Object { $_.ToString() })
    if ($global:LASTEXITCODE -ne 0) {
        throw "APK inspection failed ($([IO.Path]::GetFileName($ToolPath)), exit $global:LASTEXITCODE)."
    }
    return ($lines -join "`n")
}

function Get-SingleMatch([string]$Text, [string]$Pattern, [string]$Label) {
    $found = [regex]::Matches($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($found.Count -ne 1) { throw "Missing or ambiguous APK $Label." }
    return $found[0]
}

function Get-PackageAttribute([string]$PackageLine, [string]$Name) {
    $pattern = "(?<![A-Za-z0-9_])$([regex]::Escape($Name))='([^']*)'"
    $found = Get-SingleMatch $PackageLine $pattern $Name
    return $found.Groups[1].Value
}

function Get-PositiveInteger([string]$Value, [int]$Maximum, [string]$Label) {
    $parsed = 0
    if ($Value -cnotmatch '^[0-9]+$' -or
        -not [int]::TryParse($Value, [ref]$parsed) -or
        $parsed -lt 1 -or $parsed -gt $Maximum) {
        throw "Invalid APK $Label."
    }
    return $parsed
}

function Normalize-SignerHash([string]$Value) {
    $normalized = $Value -replace '[:\s]', ''
    if ($normalized -cnotmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid expected signer SHA-256.' }
    return $normalized.ToLowerInvariant()
}

function Read-Apk([string]$Path) {
    if ([IO.Path]::GetExtension($Path) -ine '.apk') { throw 'Input must be an APK file.' }
    $badging = Invoke-ApkTool $resolvedAapt @('dump', 'badging', $Path)
    $packageLine = (Get-SingleMatch $badging '^package:\s+[^\r\n]+\r?$' 'package record').Value
    $package = Get-PackageAttribute $packageLine 'name'
    $versionName = Get-PackageAttribute $packageLine 'versionName'
    $versionCode = Get-PositiveInteger (Get-PackageAttribute $packageLine 'versionCode') 2147483647 'versionCode'
    if ($package -cne 'com.naihuishi.nai_huishi') { throw 'Only the official production package is supported; preview packages are rejected.' }
    if ($versionName.Length -gt 64 -or $versionName -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?$') {
        throw 'Only a stable numeric APK versionName is supported.'
    }
    if ($packageLine -match "\bversionCodeMajor='([^']*)'" -and $Matches[1] -cne '0') {
        throw 'versionCodeMajor is not supported by the V1 manifest.'
    }
    if ($packageLine -match "\bsplit='([^']+)'" -or $badging -match '(?m)^application-(debuggable|testOnly)\b') {
        throw 'Split, debuggable, or test-only APKs cannot be published by this script.'
    }
    $sdk = Get-SingleMatch $badging "^sdkVersion:'([0-9]+)'\s*\r?$" 'minimum SDK'
    $minSdk = Get-PositiveInteger $sdk.Groups[1].Value 100 'minSdk'
    if ($minSdk -lt 21) { throw 'The V1 manifest requires minSdk >= 21.' }
    $native = Get-SingleMatch $badging '^native-code:[^\r\n]*\r?$' 'native ABI record'
    if ($native.Value -cnotmatch "^native-code:\s*'arm64-v8a'\s*$") {
        throw 'Only a standalone arm64-v8a APK with exactly one ABI is supported.'
    }
    $certificates = Invoke-ApkTool $resolvedSigner @('verify', '--print-certs', $Path)
    $certificate = Get-SingleMatch $certificates '^Signer #[1-9][0-9]* certificate SHA-256 digest:\s*([a-fA-F0-9]{64})\s*\r?$' 'single signing certificate'
    # Key rotation and multiple current signers are intentionally outside V1.
    $signerRecords = [regex]::Matches($certificates, '(?m)^Signer #[1-9][0-9]* certificate SHA-256 digest:')
    if ($signerRecords.Count -ne 1) { throw 'Exactly one current APK signer is required.' }
    return [pscustomobject]@{
        PackageName = $package
        VersionName = $versionName
        VersionCode = $versionCode
        MinSdk = $minSdk
        SignerSha256 = $certificate.Groups[1].Value.ToLowerInvariant()
    }
}

if ([string]::IsNullOrWhiteSpace($BaselineApkPath) -and [string]::IsNullOrWhiteSpace($ExpectedSignerSha256)) {
    throw 'Provide BaselineApkPath or ExpectedSignerSha256. Local/default debug keys are never trusted automatically.'
}
if ($null -ne $BaselineVersionCode -and $BaselineVersionCode -lt 1) { throw 'BaselineVersionCode must be positive.' }
if ([string]::IsNullOrWhiteSpace($BaselineApkPath) -and $null -eq $BaselineVersionCode) {
    throw 'ExpectedSignerSha256 without a baseline APK also requires the verified published BaselineVersionCode.'
}
if ($PublishedAt.UtcDateTime.Year -lt 1970) { throw 'PublishedAt must be in 1970 or later.' }
$resolvedApk = Get-InputFile $ApkPath 'APK'
$resolvedNotes = Get-InputFile $ReleaseNotesPath 'Release notes'
$resolvedAapt = Get-ToolPath $AaptPath 'aapt.exe'
$resolvedSigner = Get-ToolPath $ApkSignerPath 'apksigner.bat'
$resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$manifestPath = Join-Path $resolvedOutput 'update.json'
$sumsPath = Join-Path $resolvedOutput 'SHA256SUMS.txt'
if ((Test-Path -LiteralPath $resolvedOutput) -and -not (Test-Path -LiteralPath $resolvedOutput -PathType Container)) {
    throw 'OutputDirectory must be a directory.'
}
if ((Test-Path -LiteralPath $manifestPath) -or (Test-Path -LiteralPath $sumsPath)) {
    throw 'Output files already exist; choose a new release metadata directory.'
}
if ([IO.Path]::GetExtension($resolvedAapt) -ieq '.ps1' -or [IO.Path]::GetExtension($resolvedSigner) -ieq '.ps1') {
    Write-Warning 'Script inspection tools are injected: their output is fixture evidence, not real APK signature verification.'
}

$apkStream = $null
$baselineStream = $null
$temporaryPaths = New-Object 'System.Collections.Generic.List[string]'
$createdOutputs = New-Object 'System.Collections.Generic.List[string]'
try {
    # Windows denies writes/deletes while the tools, hash, and metadata are read.
    $apkStream = [IO.File]::Open($resolvedApk, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    if ($apkStream.Length -lt 1 -or $apkStream.Length -gt 512MB) { throw 'APK size must be between 1 byte and 512 MiB.' }
    $candidate = Read-Apk $resolvedApk
    $expectedTag = "v$($candidate.VersionName)-$($candidate.VersionCode)"
    if ($ReleaseTag -cne $expectedTag) { throw "ReleaseTag must exactly match the actual APK: $expectedTag" }
    $trustedSigner = $null
    $baselineCode = $BaselineVersionCode
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSignerSha256)) {
        $trustedSigner = Normalize-SignerHash $ExpectedSignerSha256
    }
    if (-not [string]::IsNullOrWhiteSpace($BaselineApkPath)) {
        $resolvedBaseline = Get-InputFile $BaselineApkPath 'Trusted baseline APK'
        $baselineStream = [IO.File]::Open($resolvedBaseline, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $baseline = Read-Apk $resolvedBaseline
        if ($null -ne $baselineCode -and $baselineCode -ne $baseline.VersionCode) { throw 'BaselineVersionCode does not match the baseline APK.' }
        $baselineCode = $baseline.VersionCode
        if ($null -ne $trustedSigner -and $trustedSigner -cne $baseline.SignerSha256) { throw 'The baseline APK signer does not match ExpectedSignerSha256.' }
        $trustedSigner = $baseline.SignerSha256
    }
    if ($candidate.SignerSha256 -cne $trustedSigner) { throw 'APK signing certificate does not match the explicitly trusted release signer.' }
    if ($candidate.VersionCode -le $baselineCode) { throw 'Actual APK versionCode must be strictly newer than the published baseline.' }

    $notes = [IO.File]::ReadAllText($resolvedNotes, $utf8)
    if ($notes.Length -gt 65536 -or $notes -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]') {
        throw 'Release notes exceed the V1 plain-text size limit or contain forbidden control characters.'
    }
    $apkSha256 = (Get-FileHash -InputStream $apkStream -Algorithm SHA256).Hash.ToLowerInvariant()
    $repository = 'https://github.com/sakiko0901/NAI-WorldPainter'
    $manifest = [ordered]@{
        schemaVersion = 1
        channel = 'stable'
        packageName = $candidate.PackageName
        versionName = $candidate.VersionName
        versionCode = $candidate.VersionCode
        publishedAt = $PublishedAt.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
        releaseNotes = $notes
        releaseUrl = "$repository/releases/tag/$ReleaseTag"
        apk = [ordered]@{
            url = "$repository/releases/download/$ReleaseTag/app-release.apk"
            sizeBytes = $apkStream.Length
            sha256 = $apkSha256
            abi = 'arm64-v8a'
            minSdk = $candidate.MinSdk
        }
    }
    $json = ($manifest | ConvertTo-Json -Depth 5) + "`n"
    if ($utf8.GetByteCount($json) -gt 128KB) { throw 'Encoded update.json exceeds the client limit of 128 KiB.' }

    if (-not (Test-Path -LiteralPath $resolvedOutput)) { $null = [IO.Directory]::CreateDirectory($resolvedOutput) }
    $suffix = [Guid]::NewGuid().ToString('N')
    $temporaryManifest = Join-Path $resolvedOutput ".update-$suffix.tmp"
    $temporarySums = Join-Path $resolvedOutput ".sums-$suffix.tmp"
    $temporaryPaths.Add($temporaryManifest)
    $temporaryPaths.Add($temporarySums)
    [IO.File]::WriteAllText($temporaryManifest, $json, $utf8)
    $jsonSha256 = (Get-FileHash -LiteralPath $temporaryManifest -Algorithm SHA256).Hash.ToLowerInvariant()
    $sums = "$apkSha256  app-release.apk`n$jsonSha256  update.json`n"
    [IO.File]::WriteAllText($temporarySums, $sums, $utf8)
    # Publish the manifest locally last; never replace an existing output file.
    [IO.File]::Move($temporarySums, $sumsPath)
    $createdOutputs.Add($sumsPath)
    [IO.File]::Move($temporaryManifest, $manifestPath)
    $createdOutputs.Add($manifestPath)
    [pscustomobject]@{
        ApkPath = $resolvedApk
        ApkAssetName = 'app-release.apk'
        ManifestPath = $manifestPath
        ChecksumsPath = $sumsPath
        VersionName = $candidate.VersionName
        VersionCode = $candidate.VersionCode
        BaselineVersionCode = $baselineCode
        SignerSha256 = $candidate.SignerSha256
        AaptPath = $resolvedAapt
        ApkSignerPath = $resolvedSigner
    }
} catch {
    foreach ($path in $createdOutputs) { Remove-Item -LiteralPath $path -Force }
    throw
} finally {
    if ($null -ne $baselineStream) { $baselineStream.Dispose() }
    if ($null -ne $apkStream) { $apkStream.Dispose() }
    foreach ($path in $temporaryPaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
}
