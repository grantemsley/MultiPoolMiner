﻿using module ..\Include.psm1

$Path = ".\Bin\CPU-TPruvot\cpuminer-gw64-core2.exe"
$HashSHA256 = "3EA2A09BE5CFFC0501FC07F6744233A351371E2CF93F544768581EE1E6613454"
$Uri = "https://github.com/tpruvot/cpuminer-multi/releases/download/v1.3.1-multi/cpuminer-multi-rel1.3.1-x64.zip"

$Commands = [PSCustomObject]@{
    # CPU Only algos 3/27/2018
    "yescrypt"       = "" #Yescrypt
    "axiom"          = "" #axiom
    
    # CPU & GPU - still profitable 27/03/2018
    "cryptonight"    = "" #CryptoNight
    "shavite3"       = "" #shavite3

    #GPU - never profitable 27/03/2018
    #"bastion"       = "" #bastion
    #"bitcore"       = "" #Bitcore
    #"blake"         = "" #blake
    #"blake2s"       = "" #Blake2s
    #"blakecoin"     = "" #Blakecoin
    #"bmw"           = "" #bmw
    #"c11"           = "" #C11
    #"cryptolight"   = "" #cryptolight
    #"decred"        = "" #Decred
    #"dmd-gr"        = "" #dmd-gr
    #"equihash"      = "" #Equihash
    #"ethash"        = "" #Ethash
    #"groestl"       = "" #Groestl
    #"jha"           = "" #JHA
    #"keccak"        = "" #Keccak
    #"keccakc"       = "" #keccakc
    #"lbry"          = "" #Lbry
    #"lyra2re"       = "" #lyra2re
    #"lyra2v2"       = "" #Lyra2RE2
    #"myr-gr"        = "" #MyriadGroestl
    #"neoscrypt"     = "" #NeoScrypt
    #"nist5"         = "" #Nist5
    #"pascal"        = "" #Pascal
    #"pentablake"    = "" #pentablake
    #"pluck"         = "" #pluck
    #"scrypt:N"      = "" #scrypt:N
    #"scryptjane:nf" = "" #scryptjane:nf
    #"sha256d"       = "" #sha256d
    #"sib"           = "" #Sib
    #"skein"         = "" #Skein
    #"skein2"        = "" #skein2
    #"skunk"         = "" #Skunk
    #"timetravel"    = "" #Timetravel
    #"tribus"        = "" #Tribus
    #"vanilla"       = "" #BlakeVanilla
    #"veltor"        = "" #Veltor
    #"x11"           = "" #X11
    #"x11evo"        = "" #X11evo
    #"x13"           = "" #x13
    #"x14"           = "" #x14
    #"x15"           = "" #x15
    #"x16r"          = "" #x16r
    #"zr5"           = "" #zr5
}

$CommonCommands = " -t $($Config.MaxThreads)"

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Commands | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp" <#temp fix#>} | ForEach-Object {

    $Algorithm_Norm = Get-Algorithm $_

    [PSCustomObject]@{
        Type       = "CPU"
        Path       = $Path
        HashSHA256 = $HashSHA256
        Arguments  = "-a $_ -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass)$($Commands.$_)$($CommonCommands)"
        HashRates  = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Name)_$($Algorithm_Norm)_HashRate".Week}
        API        = "Ccminer"
        Port       = 4048
        URI        = $Uri
    }
}
