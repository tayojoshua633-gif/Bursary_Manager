# build_release.ps1 — auto-increments the patch version in app_version.dart
# and pubspec.yaml, then runs: flutter run --release
# Usage: .\scripts\build_release.ps1

$versionFile = "$PSScriptRoot\..\lib\utils\app_version.dart"
$pubspecFile  = "$PSScriptRoot\..\pubspec.yaml"

# --- Read current version from app_version.dart ---
$content = Get-Content $versionFile -Raw
if ($content -match "kAppVersion = '(\d+)\.(\d+)\.(\d+)'") {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]
} else {
    Write-Error "Could not parse version from $versionFile"
    exit 1
}

# --- Increment patch, cascading into minor/major (each field wraps at 9) ---
$patch++
if ($patch -gt 9) {
    $patch = 0
    $minor++
}
if ($minor -gt 9) {
    $minor = 0
    $major++
}
$newVersion = "$major.$minor.$patch"

# --- Write back to app_version.dart ---
$newContent = "const String kAppVersion = '$newVersion';`n"
Set-Content -Path $versionFile -Value $newContent -Encoding UTF8
Write-Host "app_version.dart -> $newVersion"

# --- Update pubspec.yaml version line ---
$pubspec = Get-Content $pubspecFile -Raw
$pubspec = $pubspec -replace "(?m)^version: \d+\.\d+\.\d+\+\d+", "version: $newVersion+1"
Set-Content -Path $pubspecFile -Value $pubspec -Encoding UTF8
Write-Host "pubspec.yaml     -> $newVersion+1"

# --- Run flutter release ---
Write-Host ""
Write-Host "Running flutter run --release ..."
flutter run --release
