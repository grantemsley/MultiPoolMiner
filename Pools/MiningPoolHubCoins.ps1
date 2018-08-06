using module ..\Include.psm1

param(
    [alias("UserName")]
    [String]$User, 
    [alias("WorkerName")]
    [String]$Worker, 
    [TimeSpan]$StatSpan
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$PoolAPIUri= "http://miningpoolhub.com/index.php?page=api&action=getminingandprofitsstatistics&$(Get-Date -Format "yyyy-MM-dd_HH-mm")"
$PoolRegions = "europe", "us-east", "asia"

if (-not (Test-Port -Hostname ([Uri]$PoolAPIUri).Host -Port ([Uri]$PoolAPIUri).Port -Timeout 500)) {
    Write-Log -Level Warn "Pool API ($Name) is down. "
    return
}

#defines minimum memory required per coin, default is 4gb
$MinMem = [PSCustomObject]@{
    "Expanse"  = "2gb"
    "Soilcoin" = "2gb"
    "Ubiq"     = "2gb"
    "Musicoin" = "3gb"
}

if ($User) {

    try {
        $APIRequest = [PSCustomObject]@{}
        $APIRequest = Invoke-RestMethod $PoolAPIUri-UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn "Pool API ($Name) has failed. "
        return
    }

    if ($APIRequest.return.count -le 1) {
        Write-Log -Level Warn "Pool API ($Name) returned nothing. "
        return
    }

    $APIRequest.return | ForEach-Object {

        $PoolHosts      = $_.host_list.split(";")
        $Port           = $_.port
        $Algorithm      = $_.algo
        $Algorithm_Norm = Get-Algorithm $Algorithm
        $CoinName       = (Get-Culture).TextInfo.ToTitleCase(($_.coin_name -replace "-", " " -replace "_", " ").ToLower()) -replace " "

        #Electroneum hardforked. ETN algo changed to previous Cryptonight which is also compatible with ASIC
        if ($CoinName -eq "Electroneum") {$Algorithm_Norm = "CryptoNight"}

        #temp fix. no need to replace first value hub.miningpoolhub 'cause it is never used
        if ($Algorithm -eq "Equihash-BTG") {$PoolHosts = ($_.host_list -replace ".hub.miningpoolhub", ".equihash-hub.miningpoolhub").split(";")}
        if ($Algorithm_Norm -eq "Sia") {$Algorithm_Norm = "SiaClaymore"} #temp fix

        $Divisor = 1000000000

        $Stat = Set-Stat -Name "$($Name)_$($Algorithm_Norm)_Profit" -Value ([Double]$_.profit / $Divisor) -Duration $StatSpan -ChangeDetection $true

        $PoolRegions | ForEach-Object {
            $Region = $_
            $Region_Norm = Get-Region ($Region -replace "^us-east$", "us")

            [PSCustomObject]@{
                Algorithm     = "$($Algorithm_Norm)$(if ($Algorithm_Norm -EQ "Ethash"){$MinMem.$CoinName})"
                CoinName      = $CoinName
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+tcp"
                Host          = $PoolHosts | Sort-Object -Descending {$_ -ilike "$Region*"} | Select-Object -First 1
                Port          = $Port
                User          = "$User.$Worker"
                Pass          = "x"
                Region        = $Region_Norm
                SSL           = $false
                Updated       = $Stat.Updated
                Fee           = 0.9 / 100
            }
            [PSCustomObject]@{
                Algorithm     = "$($Algorithm_Norm)$(if ($Algorithm_Norm -EQ "Ethash"){$MinMem.$CoinName})"
                CoinName      = $CoinName
                Price         = $Stat.Live
                StablePrice   = $Stat.Week
                MarginOfError = $Stat.Week_Fluctuation
                Protocol      = "stratum+ssl"
                Host          = $PoolHosts | Sort-Object -Descending {$_ -ilike "$Region*"} | Select-Object -First 1
                Port          = $Port
                User          = "$User.$Worker"
                Pass          = "x"
                Region        = $Region_Norm
                SSL           = $true
                Updated       = $Stat.Updated
                Fee           = 0.9 / 100
            }
        }
    }
}
