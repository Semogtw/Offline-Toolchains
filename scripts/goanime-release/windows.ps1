param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDir
)

$ErrorActionPreference = "Stop"
$source = (Resolve-Path $SourceDir).Path
Push-Location $source

try {
  git config --system core.longpaths true

  $env:AUTO_UPDATER_DSA_PUBLIC_KEY |
    Set-Content -LiteralPath windows\runner\dsa_pub.pem -Encoding ascii
  $env:AUTO_UPDATER_DSA_PRIVATE_KEY |
    Set-Content -LiteralPath dsa_priv.pem -Encoding ascii

  flutter pub get --enforce-lockfile
  if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get failed with exit code $LASTEXITCODE."
  }

  if (-not $env:RUNTIME_DATABASE_MANIFEST_URL) {
    $env:RUNTIME_DATABASE_MANIFEST_URL =
      $env:UPDATE_MANIFEST_URL -replace "/update\.json$", "/runtime_database_manifest.json"
  }

  $shorebirdArgs = @(
    "release",
    "--platforms=windows",
    "--flutter-version=$env:FLUTTER_VERSION",
    "--dart-define=FIREBASE_PROJECT_ID=$env:FIREBASE_PROJECT_ID",
    "--dart-define=FIREBASE_WEB_API_KEY=$env:FIREBASE_WEB_API_KEY",
    "--dart-define=UPDATE_MANIFEST_URL=$env:UPDATE_MANIFEST_URL",
    "--dart-define=UPDATE_APPCAST_URL=$env:UPDATE_APPCAST_URL",
    "--dart-define=UPDATE_MANIFEST_PUBLIC_KEY_ID=$env:UPDATE_MANIFEST_PUBLIC_KEY_ID",
    "--dart-define=UPDATE_MANIFEST_PUBLIC_KEY_B64=$env:UPDATE_MANIFEST_PUBLIC_KEY_B64",
    "--dart-define=UPDATE_MANIFEST_SIGNATURE_REQUIRED=true",
    "--dart-define=ANIME_METADATA_SEED_MANIFEST_URL=$env:ANIME_METADATA_SEED_MANIFEST_URL",
    "--dart-define=RUNTIME_DATABASE_MANIFEST_URL=$env:RUNTIME_DATABASE_MANIFEST_URL"
  )

  $built = $false
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    & shorebird @shorebirdArgs
    if ($LASTEXITCODE -eq 0) {
      $built = $true
      break
    }
    if ($attempt -lt 2) {
      Get-ChildItem -Path build\windows\x64 -Filter "mpv-dev-*.7z" -ErrorAction SilentlyContinue |
        Remove-Item -Force
      Remove-Item -LiteralPath build\windows\x64\CMakeCache.txt -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath build\windows\x64\CMakeFiles -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  if (-not $built) {
    throw "Shorebird Windows release failed after retry."
  }

  $shaderTarget = "build\windows\x64\runner\Release\data\flutter_assets\assets\shaders"
  New-Item -ItemType Directory -Force -Path $shaderTarget | Out-Null
  Copy-Item -Path "assets\shaders\*.glsl" -Destination $shaderTarget -Force

  New-Item -ItemType Directory -Force -Path dist\windows-release | Out-Null
  & "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" `
    "/DAppVersion=$env:VERSION_NAME" `
    "/DBuildDir=$PWD\build\windows\x64\runner\Release" `
    "/DOutputDir=$PWD\dist\windows-release" `
    packaging\windows\GoAnime.iss
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE."
  }

  $expectedInstaller =
    Join-Path $PWD "dist\windows-release\GoAnime-windows-x64-setup-$env:VERSION_NAME.exe"
  if (-not (Test-Path -LiteralPath $expectedInstaller -PathType Leaf)) {
    throw "Expected Windows installer was not produced at $expectedInstaller."
  }
  if ((Get-Item -LiteralPath $expectedInstaller).Length -le 0) {
    throw "Windows installer is empty: $expectedInstaller"
  }

  $dartExe = Join-Path $env:FLUTTER_ROOT 'bin\cache\dart-sdk\bin\dart.exe'
  $dartAppData = Join-Path $env:RUNNER_TEMP 'dart-appdata'
  New-Item -ItemType Directory -Force -Path $dartAppData | Out-Null
  $env:APPDATA = $dartAppData
  $output = & $dartExe run auto_updater:sign_update $expectedInstaller
  if ($LASTEXITCODE -ne 0) {
    throw "auto_updater signing failed with exit code $LASTEXITCODE."
  }

  $match = [regex]::Match(($output -join "`n"), 'sparkle:dsaSignature="([^"]+)"')
  if (-not $match.Success) {
    throw "Unable to extract Windows DSA signature."
  }
  "dsa_signature=$($match.Groups[1].Value)" >> $env:GITHUB_OUTPUT

  gh release upload $env:RELEASE_TAG dist\windows-release\* `
    --repo $env:GOANIME_REPOSITORY `
    --clobber
  if ($LASTEXITCODE -ne 0) {
    throw "GitHub release upload failed with exit code $LASTEXITCODE."
  }
}
finally {
  Remove-Item -LiteralPath dsa_priv.pem -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath windows\runner\dsa_pub.pem -Force -ErrorAction SilentlyContinue
  Pop-Location
}
