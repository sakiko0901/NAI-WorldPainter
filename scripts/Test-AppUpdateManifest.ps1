<#
.SYNOPSIS
Offline fixture tests. These files are JSON fixtures, NOT signed Android APKs.
.DESCRIPTION
Injected PowerShell tools model aapt/apksigner output and exit codes. This tests
script decisions and byte hashes only, never Android signature verification.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$generator = Join-Path $PSScriptRoot 'New-AppUpdateManifest.ps1'
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$fixtureRoot = Join-Path $tempParent ("nai-updater-manifest-fixture-" + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$signerA = 'a' * 64
$signerB = 'b' * 64
$caseCount = 0
$unicodeLabel = [string][char]0x4e2d + [char]0x6587

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FIXTURE TEST FAILED: $Message" }
}

function New-ApkFixture([string]$Name, [hashtable]$Changes = @{}) {
    $fixture = [ordered]@{
        fixtureOnly = $true
        packageName = 'com.naihuishi.nai_huishi'
        versionName = '1.2.5'
        versionCode = 220053
        minSdk = 24
        nativeCode = @('arm64-v8a')
        signerHashes = @($signerA)
        aaptExitCode = 0
        verifyExitCode = 0
        attemptMutation = $false
    }
    foreach ($key in $Changes.Keys) { $fixture[$key] = $Changes[$key] }
    $path = Join-Path $fixtureRoot "$Name.apk"
    [IO.File]::WriteAllText($path, ($fixture | ConvertTo-Json -Depth 4), $utf8)
    return $path
}

function Invoke-RejectedCase(
    [string]$Name,
    [hashtable]$FixtureChanges,
    [hashtable]$ArgumentChanges,
    [string]$ExpectedError
) {
    $candidatePath = New-ApkFixture $Name $FixtureChanges
    $beforeHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
    $parameters = $common.Clone()
    $parameters.ApkPath = $candidatePath
    $parameters.OutputDirectory = Join-Path $fixtureRoot "out-$Name"
    foreach ($key in $ArgumentChanges.Keys) {
        if ($null -eq $ArgumentChanges[$key]) { $parameters.Remove($key) }
        else { $parameters[$key] = $ArgumentChanges[$key] }
    }
    $failure = $null
    try { $null = & $generator @parameters -WarningAction SilentlyContinue }
    catch { $failure = $_.Exception.Message }
    Assert-True ($null -ne $failure) "$Name was accepted"
    Assert-True ($failure -match $ExpectedError) "$Name failed for an unexpected reason: $failure"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $parameters.OutputDirectory 'update.json'))) "$Name wrote update.json"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $parameters.OutputDirectory 'SHA256SUMS.txt'))) "$Name wrote checksums"
    Assert-True ((Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash -ceq $beforeHash) "$Name modified the input fixture"
    $script:caseCount++
}

try {
    $null = [IO.Directory]::CreateDirectory($fixtureRoot)
    $fakeAapt = Join-Path $fixtureRoot 'fixture-aapt.ps1'
    $fakeSigner = Join-Path $fixtureRoot 'fixture-apksigner.ps1'
    [IO.File]::WriteAllText($fakeAapt, @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($args.Count -ne 3 -or $args[0] -cne 'dump' -or $args[1] -cne 'badging') { exit 91 }
$fixture = Get-Content -LiteralPath $args[2] -Raw -Encoding UTF8 | ConvertFrom-Json
if ($fixture.aaptExitCode -ne 0) { exit $fixture.aaptExitCode }
"package: name='$($fixture.packageName)' versionCode='$($fixture.versionCode)' versionName='$($fixture.versionName)' platformBuildVersionName='16'"
"sdkVersion:'$($fixture.minSdk)'"
"native-code: " + (($fixture.nativeCode | ForEach-Object { "'$_'" }) -join ' ')
exit 0
'@, $utf8)
    [IO.File]::WriteAllText($fakeSigner, @'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($args.Count -ne 3 -or $args[0] -cne 'verify' -or $args[1] -cne '--print-certs') { exit 92 }
$fixture = Get-Content -LiteralPath $args[2] -Raw -Encoding UTF8 | ConvertFrom-Json
if ($fixture.verifyExitCode -ne 0) { exit $fixture.verifyExitCode }
if ($fixture.attemptMutation) { [IO.File]::AppendAllText($args[2], 'CHANGED') }
$number = 0
foreach ($hash in $fixture.signerHashes) {
    $number++
    "Signer #$number certificate SHA-256 digest: $hash"
}
exit 0
'@, $utf8)
    $notesPath = Join-Path $fixtureRoot "release notes $unicodeLabel.txt"
    [IO.File]::WriteAllText($notesPath, "$unicodeLabel release notes.`n<script>plain text only</script>", $utf8)
    $baselinePath = New-ApkFixture 'published-baseline' @{ versionName = '1.2.4'; versionCode = 220052 }
    $common = @{
        BaselineApkPath = $baselinePath
        ReleaseTag = 'v1.2.5-220053'
        ReleaseNotesPath = $notesPath
        AaptPath = $fakeAapt
        ApkSignerPath = $fakeSigner
        PublishedAt = [DateTimeOffset]::Parse('2026-10-31T12:00:00Z')
    }
    $candidatePath = New-ApkFixture 'final signed fixture'
    $candidateHash = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $baselineHash = (Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash
    $parameters = $common.Clone()
    $parameters.ApkPath = $candidatePath
    $parameters.OutputDirectory = Join-Path $fixtureRoot "valid baseline metadata $unicodeLabel"
    $result = & $generator @parameters -WarningAction SilentlyContinue
    $raw = [IO.File]::ReadAllText($result.ManifestPath, $utf8)
    $manifest = $raw | ConvertFrom-Json
    Assert-True ($manifest.versionName -ceq '1.2.5' -and $manifest.versionCode -eq 220053) 'Version must come from APK output, not pubspec.yaml'
    Assert-True ($manifest.schemaVersion -eq 1 -and $manifest.channel -ceq 'stable') 'Wrong release schema/channel'
    Assert-True ($manifest.packageName -ceq 'com.naihuishi.nai_huishi') 'Wrong package'
    Assert-True ($manifest.releaseUrl -ceq 'https://github.com/sakiko0901/NAI-WorldPainter/releases/tag/v1.2.5-220053') 'Wrong release URL'
    Assert-True ($manifest.apk.url -ceq 'https://github.com/sakiko0901/NAI-WorldPainter/releases/download/v1.2.5-220053/app-release.apk') 'Wrong APK URL'
    Assert-True ($manifest.apk.sha256 -ceq $candidateHash) 'APK SHA-256 did not use actual bytes'
    Assert-True ($manifest.apk.sizeBytes -eq (Get-Item -LiteralPath $candidatePath).Length) 'APK size did not use actual bytes'
    Assert-True ($manifest.apk.abi -ceq 'arm64-v8a' -and $manifest.apk.minSdk -eq 24) 'Wrong platform metadata'
    Assert-True ($manifest.releaseNotes -ceq [IO.File]::ReadAllText($notesPath, $utf8)) 'Notes changed'
    Assert-True ($raw -match '"publishedAt":\s*"2026-10-31T12:00:00.000Z"') 'Timestamp was not normalized to UTC'
    $keys = @($manifest.PSObject.Properties.Name | Sort-Object) -join ','
    $apkKeys = @($manifest.apk.PSObject.Properties.Name | Sort-Object) -join ','
    Assert-True ($keys -ceq 'apk,channel,packageName,publishedAt,releaseNotes,releaseUrl,schemaVersion,versionCode,versionName') 'Unexpected manifest fields'
    Assert-True ($apkKeys -ceq 'abi,minSdk,sha256,sizeBytes,url') 'Unexpected APK fields'
    $sums = [IO.File]::ReadAllText($result.ChecksumsPath, $utf8)
    $jsonHash = (Get-FileHash -LiteralPath $result.ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-True ($sums -ceq "$candidateHash  app-release.apk`n$jsonHash  update.json`n") 'Incorrect checksums'
    Assert-True ((Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $candidateHash) 'Candidate was modified'
    Assert-True ((Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash -ceq $baselineHash) 'Baseline was modified'
    $caseCount++

    $parameters = $common.Clone()
    $parameters.Remove('BaselineApkPath')
    $parameters.ApkPath = $candidatePath
    $parameters.OutputDirectory = Join-Path $fixtureRoot 'valid explicit signer'
    $parameters.ExpectedSignerSha256 = (($signerA.ToUpperInvariant() -split '(.{2})' | Where-Object { $_ }) -join ':')
    $parameters.BaselineVersionCode = 220052
    $result = & $generator @parameters -WarningAction SilentlyContinue
    Assert-True (Test-Path -LiteralPath $result.ManifestPath -PathType Leaf) 'Explicit signer route failed'
    $caseCount++

    Invoke-RejectedCase 'no-trust' @{} @{ BaselineApkPath = $null } 'Provide BaselineApkPath or ExpectedSignerSha256'
    Invoke-RejectedCase 'no-baseline-code' @{} @{ BaselineApkPath = $null; ExpectedSignerSha256 = $signerA } 'requires.*BaselineVersionCode'
    Invoke-RejectedCase 'wrong-signer' @{ signerHashes = @($signerB) } @{} 'signing certificate does not match'
    Invoke-RejectedCase 'wrong-expected-signer' @{} @{ ExpectedSignerSha256 = $signerB } 'baseline APK signer does not match'
    Invoke-RejectedCase 'preview-package' @{ packageName = 'com.naihuishi.nai_huishi.preview' } @{} 'production package'
    Invoke-RejectedCase 'preview-version' @{ versionName = '1.2.5-preview.1' } @{} 'stable numeric'
    Invoke-RejectedCase 'wrong-code-tag' @{} @{ ReleaseTag = 'v1.2.5-220054' } 'ReleaseTag must exactly match'
    Invoke-RejectedCase 'wrong-name-tag' @{} @{ ReleaseTag = 'v1.2.4-220053' } 'ReleaseTag must exactly match'
    Invoke-RejectedCase 'same-code' @{ versionCode = 220052 } @{ ReleaseTag = 'v1.2.5-220052' } 'strictly newer'
    Invoke-RejectedCase 'older-code' @{ versionCode = 220051 } @{ ReleaseTag = 'v1.2.5-220051' } 'strictly newer'
    Invoke-RejectedCase 'multi-abi' @{ nativeCode = @('arm64-v8a', 'x86_64') } @{} 'exactly one ABI'
    Invoke-RejectedCase 'missing-abi' @{ nativeCode = @() } @{} 'exactly one ABI'
    Invoke-RejectedCase 'failed-verify' @{ verifyExitCode = 13 } @{} 'APK inspection failed.*exit 13'
    Invoke-RejectedCase 'failed-aapt' @{ aaptExitCode = 31 } @{} 'APK inspection failed.*exit 31'
    Invoke-RejectedCase 'multiple-signers' @{ signerHashes = @($signerA, $signerB) } @{} 'ambiguous.*signing certificate'
    Invoke-RejectedCase 'baseline-code-mismatch' @{} @{ BaselineVersionCode = 218052 } 'does not match the baseline APK'
    Invoke-RejectedCase 'minimum-sdk' @{ minSdk = 19 } @{} 'minSdk >= 21'
    Invoke-RejectedCase 'input-write-attempt' @{ attemptMutation = $true } @{} 'cannot access|being used|used by another process|access.*denied'

    $badNotes = Join-Path $fixtureRoot 'bad-notes.txt'
    [IO.File]::WriteAllText($badNotes, "bad$([char]1)notes", $utf8)
    Invoke-RejectedCase 'control-character-notes' @{} @{ ReleaseNotesPath = $badNotes } 'forbidden control'
    $bigNotes = Join-Path $fixtureRoot 'large-notes.txt'
    [IO.File]::WriteAllText($bigNotes, ([string][char]0x4e2d * 65000), $utf8)
    Invoke-RejectedCase 'encoded-manifest-too-large' @{} @{ ReleaseNotesPath = $bigNotes } 'exceeds.*128 KiB'

    $parameters = $common.Clone()
    $parameters.ApkPath = $candidatePath
    $parameters.OutputDirectory = Join-Path $fixtureRoot "valid baseline metadata $unicodeLabel"
    $oldManifestHash = (Get-FileHash -LiteralPath (Join-Path $parameters.OutputDirectory 'update.json')).Hash
    $rejected = $false
    try { $null = & $generator @parameters -WarningAction SilentlyContinue }
    catch { $rejected = $_.Exception.Message -match 'already exist' }
    Assert-True $rejected 'Existing metadata was overwritten'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $parameters.OutputDirectory 'update.json')).Hash -ceq $oldManifestHash) 'Existing metadata changed'
    $caseCount++

    Write-Output "PASS: $caseCount offline fixture cases. No real APK/signature, Android build, device, or network verification was performed."
} finally {
    # Delete only this invocation's checked, absolute temporary fixture directory.
    $absolute = [IO.Path]::GetFullPath($fixtureRoot)
    $parent = [IO.Path]::GetDirectoryName($absolute).TrimEnd('\', '/')
    $leaf = [IO.Path]::GetFileName($absolute)
    if ($parent -ine $tempParent -or $leaf -cnotmatch '^nai-updater-manifest-fixture-[a-f0-9]{32}$') {
        throw 'Refusing cleanup outside the intended fixture directory.'
    }
    if (Test-Path -LiteralPath $absolute -PathType Container) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
