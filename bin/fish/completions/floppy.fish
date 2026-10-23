complete -c floppy -f
complete -c floppy -n __fish_use_subcommand -a status -d "Drive + disk label + mount"
complete -c floppy -n __fish_use_subcommand -a ls -d "List files on the disk"
complete -c floppy -n __fish_use_subcommand -a copy -d "Copy photos to ~/Photos/floppy/<LABEL>/"
complete -c floppy -n __fish_use_subcommand -a watch -d "Copy, wait for the next disk, repeat"
complete -c floppy -n __fish_use_subcommand -a eject -d "Unmount so you can swap disks"
complete -c floppy -n __fish_use_subcommand -a help -d "Usage"
