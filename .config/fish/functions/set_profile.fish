#
# ~/.bash_profile
#
function set_profile

  # default programs
  set -gx EDITOR "vim"
  set -gx TERMINAL "urxvt"
  set -gx BROWSER "opera"
  
  # input for multilang
  set -gx XMODIFIERS "fcitx5"
  set -gx GTK_IM_MODULE "fcitx5"
  set -gx QT_IM_MODULE "fcitx5"
  set -gx DISPLAY ":0"
  
  # wine
  set -gx WINEDEBUG "fps"
  set -gx FREETYPE_PROPERTIES "truetype:interpreter-version=35"
  
  set -gx MOZ_USE_XINPUT2 "1" # mozilla smooth scrolling/touchpads
  set -gx _JAVA_AWT_WM_NONREPARENTING "1" # android studio x11 ui fix
  
  # wmname LG3D

end
