using module ..\Include.psm1

$Path = ".\Bin\NVIDIA-Ravencoin\ccminer.exe"
$HashSHA256 = "596CA6EC61E01A36959F1DADDB15B04F5CA45CD5CFB2767AC41A253D34A7094B"
$Uri = "https://github.com/RavencoinProject/RavencoinMiner/releases/download/v3.1-cu92/Ravencoin.Miner.v3.1.win32.cu92.zip"
$UriManual = ""

$Commands = [PSCustomObject]@{
    "x16r" = ""
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
