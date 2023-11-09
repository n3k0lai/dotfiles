# \  _/\_
#  ><_  _*>   鱼
# /   \/
set_color brblue
echo "  ,__"
echo " /__/__"
echo "'|__|__|"
echo " |__|__|"
echo "---------"
set_color normal
#set -l options (fish_opt -s u -l ui)
#set options $options (fish_opt -s c -l clean)
if set -q YU_DIR 
    echo "YU_DIR already set: $YU_DIR"
else
    set -Ux YU_DIR (pwd)
end

# check if .config/fish/functions exists
if not test -d ~/.config/fish/functions
    echo "Creating ~/.config/fish/functions"
    mkdir -p ~/.config/fish/functions
end

#if set -q _flag_clean
echo "Emptying functions directory"
set_color red
rm -rf ~/.config/fish/functions/*
set_color normal
#end

# make a list of all files in major directories and copy to .config/fish/functions
set categories aliases core tools
if set -q _flag_ui
    echo "UI flag detected"
    set categories $categories ui
end
for category in $categories
    echo "copying"(set_color brblue)" $category "(set_color normal)"scripts"
    for file in $YU_DIR/$category/*.fish
        cp $file ~/.config/fish/functions/
        echo (set_color blue) '鱼' (set_color brblue) '~' (set_color normal) (basename $file)
    end
end

# add set_profile to ~/.config/fish/config.fish if not already there
if not grep -q "set_profile" ~/.config/fish/config.fish
    echo "Adding set_profile to ~/.config/fish/config.fish"
    if set -q _flag_ui
        echo "set_profile -u;" >> ~/.config/fish/config.fish
    else 
        echo "set_profile;" >> ~/.config/fish/config.fish
    end
else 
    echo (set_color red)"set_profile already in ~/.config/fish/config.fish"
end