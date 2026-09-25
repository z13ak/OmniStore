[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$SkipPackage
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repositoryRoot
try {
    if (-not $SkipInstall) {
        wally install
        if ($LASTEXITCODE -ne 0) { throw "wally install failed" }
    }

    stylua --check src tests examples
    if ($LASTEXITCODE -ne 0) { throw "StyLua check failed" }

    selene src tests examples
    if ($LASTEXITCODE -ne 0) { throw "Selene check failed" }

    New-Item -ItemType Directory -Path build -Force | Out-Null
    rojo build default.project.json --output build/OmniStore.rbxm
    if ($LASTEXITCODE -ne 0) { throw "package Rojo build failed" }
    rojo build dev.project.json --output build/OmniStoreDevelopment.rbxlx
    if ($LASTEXITCODE -ne 0) { throw "development Rojo build failed" }
    rojo build test.project.json --output build/OmniStoreTests.rbxlx
    if ($LASTEXITCODE -ne 0) { throw "test Rojo build failed" }

    if (-not $SkipPackage) {
        $manifest = wally manifest-to-json | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw "Wally manifest validation failed" }
        $archive = "build/OmniStore-$($manifest.package.version).zip"
        wally package --output $archive
        if ($LASTEXITCODE -ne 0) { throw "Wally package failed" }
        python scripts/verify_package.py $archive
        if ($LASTEXITCODE -ne 0) { throw "Wally package content validation failed" }
    }

    $artifactPaths = @(Get-ChildItem build -File | Where-Object {
        $_.Extension -in @(".rbxm", ".rbxlx", ".zip")
    })
    $checksums = $artifactPaths | Get-FileHash -Algorithm SHA256 | ForEach-Object {
        "$($_.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($_.Path))"
    }
    $checksums | Set-Content build/SHA256SUMS.txt -Encoding utf8

    git diff --check
    if ($LASTEXITCODE -ne 0) { throw "Git whitespace check failed" }
    Write-Host "OmniStore verification passed. Studio TestEZ remains a separate runtime gate."
}
finally {
    Pop-Location
}
