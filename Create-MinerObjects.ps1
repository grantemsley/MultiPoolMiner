using module .\Include-Newpoc.psm1

function Create-CcMinerObjects {

    $Miners = @()
    
    # Get device list
    $Devices.$Type | ForEach-Object {

        if ($DeviceTypeModel -and -not $Config.MinerInstancePerCardModel) {return} # after first loop $DeviceTypeModel is present; generate only one miner
        $DeviceTypeModel = $_

        # Get array of IDs of all devices in device set, returned DeviceIDs are of base $DeviceIdBase representation starting from $DeviceIdOffset
        $DeviceIDs = (Get-DeviceIDsSet -Config $Config -Devices $Devices -Type $Type -DeviceTypeModel $DeviceTypeModel -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset)."All"

        if ($DeviceIDs.Count -gt 0) {

            $Config.Miners.$Name.Commands | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pools.(Get-Algorithm $_).Protocol -eq "stratum+tcp" -and $Config.Miners.$Name.DoNotMine.$_ -inotcontains $Pools.(Get-Algorithm $_).Name} | ForEach-Object {

                $Algorithm_Norm = Get-Algorithm $_

                if ($Config.MinerInstancePerCardModel) {
                    $Miner_Name = "$Name-$($DeviceTypeModel.Name_Norm)"
                    $Commands = Get-CommandPerDeviceSet -Command $Config.Miners.$Name.Commands.$_ -DeviceIDs $DeviceIDs -DeviceIdBase $DeviceIdBase -DeviceIdOffset $DeviceIdOffset # additional command line options for algorithm
                }
                else {
                    $Miner_Name = $Name
                    $Commands = $Config.Miners.$Name.Commands.$_.Split(";") | Select-Object -Index 0 # additional command line options for algorithm
                }

                $HashRate = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week
                if ($Config.IgnoreMinerFee -or $Config.Miners.$Name.IgnoreMinerFee) {
                    $Fees = @($null)
                }
                else {
                    $HashRate = $HashRate * (1 - $MinerFeeInPercent / 100)
                    $Fees = @($MinerFeeInPercent)
                }

                [PSCustomObject]@{
                    Name             = $Miner_Name
                    Type             = $Type
                    Path             = $Path
                    Arguments        = ("-a $_ -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) -u $($Pools.$Algorithm_Norm.User) -p $($Pools.$Algorithm_Norm.Pass)$Commands$($Config.Miners.$Name.CommonCommands) -b 127.0.0.1:$($Port) -d $($DeviceIDs -join ',')" -replace "\s+", " ").trim()
                    HashRates        = [PSCustomObject]@{$Algorithm_Norm = $Stats."$($Miner_Name)_$($Algorithm_Norm)_HashRate".Week}
                    API              = $Api
                    Port             = $Port
                    URI              = $Uri
                    Fees             = @($Fees)
                    Index            = $DeviceTypeModel.DeviceIDs -join ';' # Always list all devices
                    ShowMinerWindow  = $Config.ShowMinerWindow
                }
            }
        }
        $Port++ # next higher port for next device
    }
}