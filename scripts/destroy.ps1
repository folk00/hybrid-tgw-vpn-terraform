param(
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$TfDir = Join-Path $Root "terraform"

Push-Location $TfDir
try {
    terraform destroy -var "aws_region=$Region"
}
finally {
    Pop-Location
}
