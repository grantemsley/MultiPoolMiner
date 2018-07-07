using module ..\Include.psm1

$Path = ".\Bin\NVIDIA-NemosRaven\ccminer.exe"
$HashSHA256 = "9F821EE2551A8F457DB0B878A03B813129E4B7049FD76F2131F862BD55447138"
$Uri = "https://github.com/nemosminer/RavencoinMiner/releases/download/v3.0(9.2)/ccminerRavenx32.zip"
$UriManual = ""

$Commands = [PSCustomObject]@{
    "x16r" = "-i 20"
}

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName
                
$Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp" <#temp fix#>} | ForEach-Object {

    $Algorithm_Norm = Get-Algorithm $_

    Switch ($Algorithm_Norm) {
        "PHI"   {$ExtendInterval = 3}
        "X16R"  {$ExtendInterval = 10}
        "X16S"  {$ExtendInterval = 10}
        default {$ExtendInterval = 0}
    }

    [PSCustomObject]@{
        Type           = "NVIDIA"
        Path           = $Path
        HashSHA256     = $HashSHA256
        Arguments      = "-a $_ -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass)$($Commands.$_)"
        HashRates      = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Name)_$($Algorithm_Norm)_HashRate".Week}
        API            = "Ccminer"
        Port           = 4068
        URI            = $Uri
        Fees           = [PSCustomObject]@{$Algorithm_Norm = 1 / 100}
        ExtendInterval = $ExtendInterval
    }
} 
