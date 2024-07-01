param (
  [Parameter(Mandatory=$false)][string]$PKG_NAME,
  [Parameter(Mandatory=$false)][string]$PKG_TYPE = "static"
)

# Powershell windows runner always succeeding
#  - https://gitlab.com/gitlab-org/gitlab-runner/-/issues/1514
$ErrorActionPreference = 'Stop'

$PWSH_VERSION = ${Host}.Version
if (($PWSH_VERSION.Major -ge 6) -and (-not $IsWindows)) {
  Write-Host -ForegroundColor Red "'${PSCommandPath}' is only supported on Windows."
  exit 1
}

$PROJ_ROOT = $PSScriptRoot

$triplet = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$triplet_values = $triplet -split '_'
$triplet_length = $triplet_values.Length
if ($triplet_length -eq 3) {
  $TARGET_PLATFORM = $triplet_values[1]
  $TARGET_ARCH = $triplet_values[2]
} else {
  Write-Host -ForegroundColor Red `
    "Please use wrapper to build the project, such as 'build_`${platform}_`${arch}.sh'."
  exit 1
}

switch ($TARGET_PLATFORM) {
  'win-msvc' {
    . "${PROJ_ROOT}\env-msvc.ps1" ${TARGET_PLATFORM} ${TARGET_ARCH}
    if (($LASTEXITCODE -ne $null) -and ($LASTEXITCODE -ne 0)) {
      exit $LASTEXITCODE
    }
    break
  }
}

$compile = {
  param (
    [Parameter(Mandatory=$true)][string]$PKG_NAME,
    [Parameter(Mandatory=$true)][string]$PKG_TYPE,
    [Parameter(Mandatory=$true)][string]$PKG_PLATFORM,
    [Parameter(Mandatory=$true)][string]$PKG_ARCH
  )

  ${env:PROJ_ROOT} = "${PROJ_ROOT}"
  ${env:PYPI_MIRROR} = "-i https://mirrors.bfsu.edu.cn/pypi/web/simple"

  ${env:PKG_NAME} = "${PKG_NAME}"
  ${env:SUBPROJ_SRC} = "${PROJ_ROOT}\deps\${PKG_NAME}"

  ${env:PKG_TYPE} = "${PKG_TYPE}"
  ${env:PKG_PLATFORM} = "${PKG_PLATFORM}"
  ${env:PKG_ARCH} = "${PKG_ARCH}"

  ${env:PKG_BULD_DIR} = "${PROJ_ROOT}\tmp\${PKG_NAME}\${PKG_PLATFORM}\${PKG_ARCH}"
  ${env:PKG_INST_DIR} = "${PROJ_ROOT}\out\${PKG_NAME}\${PKG_PLATFORM}\${PKG_ARCH}"
  if ($GITHUB_ACTIONS -ieq "true") {
    if (${env:BULD_DIR} -ne $null) { ${env:PKG_BULD_DIR} = "${env:BULD_DIR}" }
    if (${env:INST_DIR} -ne $null) { ${env:PKG_INST_DIR} = "${env:INST_DIR}" }
  }

  if (-not (Test-Path -PathType Any -Path "${env:SUBPROJ_SRC}/.git")) {
    Push-Location "${PROJ_ROOT}"
    git submodule update --init -f -- "deps/${PKG_NAME}"
    Pop-Location
  }
  Push-Location "${env:SUBPROJ_SRC}"
  ${env:PKG_VERSION} = "$(git describe --tags --always --dirty --abbrev=7)"
  Pop-Location

  if (Test-Path -PathType Container -Path "${PROJ_ROOT}/patchs/${PKG_NAME}") {
    Push-Location "${env:SUBPROJ_SRC}"
    git reset --hard HEAD

    foreach ($patch in (Get-ChildItem -Path "${PROJ_ROOT}/patchs/${PKG_NAME}" -File)) {
      git apply ${patch}.FullName
    }
    Pop-Location
  }
  & "${PROJ_ROOT}\scripts\${PKG_NAME}.ps1"
}

if ($GITHUB_ACTIONS -ne "true") {
  if (($PKG_NAME -eq $null) -or ($PKG_NAME -eq "")) {
    Write-Host -ForegroundColor Red "Please declare the module to be compiled."
    exit 1
  }
  Invoke-Command -ScriptBlock ${compile} `
    -ArgumentList ${PKG_NAME}, ${PKG_TYPE}, ${TARGET_PLATFORM}, ${TARGET_ARCH}
}