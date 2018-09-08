# MultiPoolMiner
###### Licensed under the GNU General Public License v3.0 - Permissions of this strong copyleft license are conditioned on making available complete source code of licensed works and modifications, which include larger works using a licensed work, under the same license. Copyright and license notices must be preserved. Contributors provide an express grant of patent rights. https://github.com/grantemsley/MultiPoolMiner/blob/master/LICENSE

This is a fork of the MultiPoolMiner created by aaronsace at https://github.com/MultiPoolMiner/MultiPoolMiner

## INSTALLATION

Installation differs from the official version.  I do not create releases, since changes often happen on an almost daily basis.

1. Download and install git from https://git-scm.com/download/win
2. Download and install powershell 6 from https://github.com/PowerShell/PowerShell/releases
3. In a command line window, run `git clone https://github.com/grantemsley/MultiPoolMiner.git`. This will create a new folder MultiPoolMiner in that directory.
4. Run update-dev.bat - this will download all the necessary miner files for you.
5. Run launcher.bat, then click start mining. This generates the initial config.txt file
6. In the launcher, click Edit Config.txt and edit with your bitcoin address and MiningPoolHub username
7. Let the benchmarking finish (you will be earning shares even during benchmarking).

Done. You are all set to mine the most profitable coins and maximise your profits using MultiPoolMiner.

*Any bitcoin donations are greatly appreciated: 16Qf1mEk5x2WjJ1HhfnvPnqQEi2fvCeity*

## UPDATING

To update to the latest version, simply run `update-dev.bat`.  This runs a bunch of checks, then downloads the latest master version and updates the miner binaries.

I make no guarantee that the master version will always run without error - we do our best, but sometimes bugs slip through. If you are updating a large number of machines,
I recommend updating a single machine first and making sure it works properly before updating the rest.  If you do find an issue, please report it so we can fix it.