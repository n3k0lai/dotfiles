# this script runs an android mirroring 
# program optimized for capture by stream
# https://github.com/Genymobile/scrcpy

$scrcpyDir = 'C:\Program Files\scrcpy-win64\' 
$recordingsDir = 'D:\phone recordings\'

# --no-display
$AllArgs = @('--max-size', '1920', '--bit-rate', '2m')

# if big drive is connected, then record
If (Test-Path D:) {
    $filename = Get-Date -UFormat "recording-%Y-%m-%d-%H:%M:%S"
    $AllArgs += '--record'
    $AllArgs += $recordingsDir + $filename
}

cd $scrcpyDir

& $scrcpyDir'scrcpy.exe' $AllArgs