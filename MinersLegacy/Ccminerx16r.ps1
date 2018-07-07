using module ..\Include.psm1

$Path = ".\Bin\NVIDIA-ccminerx16r\ccminer.exe"
$HashSHA256 = "5786F18DBDA89499775C4B41D13D467B1170B88F18724A4323001BE53D31D9D6"
$Uri = "https://github.com/nemosminer/ccminer-x16r/releases/download/ccminer-x16r-cuda9.2/ccminer-x16r-cuda9.2.7z"

$Commands = [PSCustomObject]@{
    "x16r"        = "" #Raven
}

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp" <#temp fix#>} | ForEach-Object {
    
    $Algorithm_Norm = Get-Algorithm $_

    Switch ($Algorithm_Norm) {
        "PHI"   {$ExtendInterval = 3}
        "X16R"  {$ExtendInterval = 10}
        default {$ExtendInterval = 0}
    }

    [PSCustomObject]@{
        Type             = "NVIDIA"
        Path             = $Path
        HashSHA256       = $HashSHA256
        Arguments        = "-a $_ -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass)$($Commands.$_)"
        HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Name)_$($Algorithm_Norm)_HashRate".Week}
        API              = "Ccminer"
        Port             = 4068
        URI              = $Uri
        ExtendInterval   = $ExtendInterval
    }
}
