# wrapper for jirutka/swalock-effects
function lock
  set -l lockargs --clock -d -c 191919
  set lockargs $lockargs --indicator --indicator-radius 100 --indicator-thickness 7 
  set lockargs $lockargs --effect-blur 7x5 --effect-vignette 0.5:0.5
  set lockargs $lockargs --ring-color 6f95fc --key-hl-color 83d9f7 --text-color 83d9f7
  set lockargs $lockargs --line-color 00000000 --inside-color 00000088 --separator-color 00000000
  #set lockargs $lockargs --grace-no-mouse 2 --fade-in 0.2
  # this arg takes a .so file
  #set lockargs $lockargs --effect-custom cmatrix
  swaylock $lockargs
end

