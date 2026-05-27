param(
    [string]$Region = "us-east-1",
    [switch]$EnableTgwLab,
    [switch]$EnableVpcFlowLogs
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$TfDir = Join-Path $Root "terraform"

Push-Location $TfDir
try {
    terraform init
    $planArgs = @("plan", "-var", "aws_region=$Region", "-out", "tfplan")
    if ($EnableTgwLab.IsPresent) {
        $planArgs += @("-var", "enable_tgw_lab=true")
    }
    if ($EnableVpcFlowLogs.IsPresent) {
        $planArgs += @("-var", "enable_vpc_flow_logs=true")
    }
    terraform @planArgs
    terraform apply tfplan
}
finally {
    Pop-Location
}
