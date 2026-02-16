#!/usr/bin/env sh
#
# external-rules.sh
# Copyright (C) 2022 sandvich <sandvich@archtop>
#
# Distributed under terms of the MIT license.
#

wid=$1
class=$2
instance=$3
consequences=$4

title=$(xtitle "$wid")
case "$title" in
    # chatterino usercards floating
    *"'s Usercard"*)
        echo "state=floating"
        ;;
esac


