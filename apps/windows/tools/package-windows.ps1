# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Nino'nun Windows paketini hazırlar (kimlikler-veri.md §1.2, §2). Windows'ta çalışır (PowerShell 7 ya da 5.1).
#
#   1. dotnet publish (win-x64, kendi içinde, Release) → publish klasörü
#   2. Yanına konması gerekenler denetlenir: nino_native.dll, Fonts\OFL-*.txt, NOTICE, LICENSE, Nino.deps.json;
#      THIRD-PARTY.md (apps/windows) eklenir; TV paketleri (tv-app\*) varsa sayılır
#   3. (İsteğe bağlı) önceki sürümün Velopack dosyaları GitHub'dan indirilir (delta için; yoksa yalnız tam paket)
#   4. vpk pack: paket kimliği NinoGameTranslator, kanal win, ana exe Nino.exe, simge Assets\Nino.ico
#   5. Kurulum dosyası Nino-Windows-Setup.exe adını alır; zip dağıtımı Nino-windows-x64.zip olarak yazılır
#
# Kullanım (depo kökünden ya da herhangi bir yerden):
#   pwsh apps/windows/tools/package-windows.ps1 -Version 4.5.0
#   pwsh apps/windows/tools/package-windows.ps1 -Version 4.5.1-beta.1 -NativeDll C:\yol\nino_native.dll -DownloadPrevious
#
# Gerekenler: .NET 10 SDK, vpk aracı (dotnet tool install -g vpk --version 1.2.161; uygulamadaki Velopack sürümüyle aynı).
# Çıktı: apps/windows/artifacts/ (publish\, releases\, Nino-windows-x64.zip).

[CmdletBinding()]
param(
    # Paket sürümü (etiketten "v" atılmış: 4.0.6, 0.1.0-beta.10). Derlemeye -p:Version olarak da verilir.
    [Parameter(Mandatory = $true)][string]$Version,
    # Hazır nino_native.dll; verilirse native\bin'e kopyalanır (RemotePlay projesi oradan yayına koyar).
    [string]$NativeDll = "",
    # TV uygulaması paketlerinin klasörü (varsayılan: depo kökündeki dist\tv-app).
    [string]$TvAppSource = "",
    # Çıktı klasörü.
    [string]$OutputDir = "",
    # Önceki sürümün Velopack dosyalarını GitHub'dan indir (delta paketi için).
    [switch]$DownloadPrevious,
    # GitHub erişim anahtarı (indirme için isteğe bağlı; ortamdaki GITHUB_TOKEN de kullanılır).
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    # Paket sunucusu adresi (boşsa paket indirme kapalı derlenir).
    [string]$PacksUrl = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ---- Sabitler (kimlikler-veri.md §2: değişirse kurulu kullanıcılar güncellemeyi alamaz) ----
$PackId      = "NinoGameTranslator"
$PackTitle   = "Nino Game Translator"
$PackAuthors = "Yunus Demirbag"
$Channel     = "win"
$MainExe     = "Nino.exe"
$Runtime     = "win-x64"
$RepoUrl     = "https://github.com/yunusdemirbag/nino-game-translator"
$SetupName   = "Nino-Windows-Setup.exe"
$ZipName     = "Nino-windows-x64.zip"

$appsWindows = Split-Path -Parent $PSScriptRoot
$repoRoot    = Split-Path -Parent (Split-Path -Parent $appsWindows)
$project     = Join-Path $appsWindows "src\Nino.App\Nino.App.csproj"
$icon        = Join-Path $appsWindows "src\Nino.App\Assets\Nino.ico"
if (-not $OutputDir)   { $OutputDir = Join-Path $appsWindows "artifacts" }
if (-not $TvAppSource) { $TvAppSource = Join-Path $repoRoot "dist\tv-app" }
$publishDir  = Join-Path $OutputDir "publish"
$releasesDir = Join-Path $OutputDir "releases"

function Step([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Fail([string]$text) { Write-Host "HATA: $text" -ForegroundColor Red; exit 1 }

if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$') { Fail "sürüm biçimi tanınmadı: $Version" }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Fail "dotnet bulunamadı (.NET 10 SDK gerekli)" }
if (-not (Get-Command vpk -ErrorAction SilentlyContinue)) { Fail "vpk bulunamadı: dotnet tool install -g vpk --version 1.2.161" }

# ---- 1. Yerel köprü ----
$nativeBin = Join-Path $appsWindows "native\bin"
if ($NativeDll) {
    if (-not (Test-Path $NativeDll)) { Fail "nino_native.dll yok: $NativeDll" }
    New-Item -ItemType Directory -Force -Path $nativeBin | Out-Null
    Copy-Item $NativeDll (Join-Path $nativeBin "nino_native.dll") -Force
}

# ---- 2. Yayın ----
Step "dotnet publish ($Runtime, kendi içinde, sürüm $Version)"
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
$publishArgs = @(
    "publish", $project,
    "-c", "Release",
    "-r", $Runtime,
    "--self-contained", "true",
    "-o", $publishDir,
    "-p:Version=$Version",
    "-p:NinoTvAppSource=$TvAppSource"
)
if ($PacksUrl) { $publishArgs += "-p:NinoPacksUrl=$PacksUrl" }
& dotnet @publishArgs
if ($LASTEXITCODE -ne 0) { Fail "dotnet publish başarısız ($LASTEXITCODE)" }

# ---- 3. Yanında olması gerekenler ----
Step "yayın klasörü denetleniyor"
$required = @($MainExe, "Nino.dll", "Nino.deps.json", "nino_native.dll", "NOTICE", "LICENSE")
foreach ($name in $required) {
    if (-not (Test-Path (Join-Path $publishDir $name))) { Fail "yayın klasöründe eksik: $name" }
}
$ofl = @(Get-ChildItem -Path (Join-Path $publishDir "Fonts") -Filter "OFL-*.txt" -ErrorAction SilentlyContinue)
if ($ofl.Count -eq 0) { Fail "yayın klasöründe yazı tipi lisansları (Fonts\OFL-*.txt) yok" }
Copy-Item (Join-Path $appsWindows "THIRD-PARTY.md") $publishDir -Force

$tvApps = @(Get-ChildItem -Path (Join-Path $publishDir "tv-app") -Include "*.ipk", "*.wgt", "*.apk" -Recurse -ErrorAction SilentlyContinue)
if ($tvApps.Count -eq 0) { Write-Warning "tv-app klasörü boş, TV paketi yok: uygulama TV'ye kendisi kuramaz ($TvAppSource)" }
else { $tvApps | ForEach-Object { Write-Host "    TV paketi: $($_.Name)" } }

# ---- 4. Önceki sürüm (delta için) ----
New-Item -ItemType Directory -Force -Path $releasesDir | Out-Null
if ($DownloadPrevious) {
    Step "önceki sürümün Velopack dosyaları indiriliyor"
    $downloadArgs = @("download", "github", "--repoUrl", $RepoUrl, "--channel", $Channel, "--outputDir", $releasesDir)
    if ($GitHubToken) { $downloadArgs += @("--token", $GitHubToken) }
    & vpk @downloadArgs
    if ($LASTEXITCODE -ne 0) { Write-Warning "önceki sürüm indirilemedi; yalnız tam paket üretilecek" }
}

# ---- 5. Velopack paketi ----
Step "vpk pack ($PackId $Version, kanal $Channel)"
$packArgs = @(
    "pack",
    "--packId", $PackId,
    "--packVersion", $Version,
    "--packDir", $publishDir,
    "--mainExe", $MainExe,
    "--packTitle", $PackTitle,
    "--packAuthors", $PackAuthors,
    "--icon", $icon,
    "--channel", $Channel,
    "--outputDir", $releasesDir,
    "--framework", "webview2"
)
& vpk @packArgs
if ($LASTEXITCODE -ne 0) { Fail "vpk pack başarısız ($LASTEXITCODE)" }

$setup = Join-Path $releasesDir "$PackId-$Channel-Setup.exe"
if (-not (Test-Path $setup)) { Fail "kurulum dosyası üretilmedi: $setup" }
Move-Item $setup (Join-Path $releasesDir $SetupName) -Force
# "Portable" zip yayına konmaz.
Get-ChildItem -Path $releasesDir -Filter "*-Portable.zip" -ErrorAction SilentlyContinue | Remove-Item -Force

# ---- 6. Zip dağıtımı (kendini güncelleyemez) ----
Step "zip: $ZipName"
$zip = Join-Path $OutputDir $ZipName
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $publishDir "*") -DestinationPath $zip

Step "hazır"
Get-ChildItem $releasesDir | ForEach-Object { Write-Host "    $($_.Name)" }
Write-Host "    $zip"
Write-Host "GitHub sürümüne yüklenecekler: $SetupName, *.nupkg, RELEASES, releases.$Channel.json, assets.$Channel.json"
