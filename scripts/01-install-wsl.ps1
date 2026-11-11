# Etape 1 (Windows, PowerShell) : installe WSL2 + Ubuntu et regle la RAM allouee a WSL.
# Usage : powershell -ExecutionPolicy Bypass -File .\01-install-wsl.ps1 [-MemoryGB 59] [-SwapGB 16]
param(
    [int]$MemoryGB = 59,   # a adapter : environ (RAM totale - 5 Go)
    [int]$SwapGB   = 16,
    [int]$Cpus     = 0     # 0 = nombre de coeurs physiques detectes
)
$ErrorActionPreference = "Stop"

if ($Cpus -le 0) {
    $Cpus = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
}

wsl --install -d Ubuntu --no-launch

$cfg = Join-Path $env:USERPROFILE ".wslconfig"
if (Test-Path $cfg) {
    Write-Host "[!] $cfg existe deja, je ne le modifie pas. Verifie qu'il contient au moins :"
    Write-Host "    [wsl2]`n    memory=${MemoryGB}GB`n    swap=${SwapGB}GB`n    processors=$Cpus"
} else {
    "[wsl2]`nmemory=${MemoryGB}GB`nswap=${SwapGB}GB`nprocessors=$Cpus" | Set-Content $cfg -Encoding ascii
    Write-Host "[+] $cfg cree (memory=${MemoryGB}GB swap=${SwapGB}GB processors=$Cpus)"
}

wsl --shutdown
Write-Host "[+] Termine. Un redemarrage de Windows peut etre demande si c'est la premiere installation de WSL."
Write-Host "    Ensuite, depuis WSL : bash scripts/02-download-model.sh"
