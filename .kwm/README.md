### Keybindings

The following keybindings are provided in the `khdrc` file. This is a config file for [Khd](https://github.com/koekeishiya/khd),
a program meant for creating various types of keybindings. Feel free to use any other tool that allows mapping a key-combination to some command.

I strongly recommend taking the time to experiment and set up your own binds, instead of using the ones provided here.

    - prefix-key: ctrl-s

    - cmd:
        - return (enter): opens a new iTerm window

    - cmd+alt+ctrl:
        - t: toggle focus-mode (autofocus -> autoraise -> disabled)
        - q: quit kwm

        - m: mark the focused container
        - h: mark the west container
        - j: mark the south container
        - k: mark the north container
        - l: mark the east container

    - prefix:
        - s: toggle split-type of existing container

        - h: increase split-ratio of focused container towards west
        - j: increase split-ratio of focused container towards south
        - k: increase split-ratio of focused container towards north
        - l: increase split-ratio of focused container towards east

        - f: toggle window fullscreen
        - d: toggle window parent container
        - w: toggle window floating

        - x: increase horizontal gap
        - y: increase vertical gap

        - p: increase screen padding all directions
        - larrow: increase screen padding-left
        - rarrow: increase screen padding-right
        - uarrow: increase screen padding-top
        - darrow: increase screen padding-bottom

    - prefix+shift:
        - h: decrease split-ratio of focused container towards west
        - j: decrease split-ratio of focused container towards south
        - k: decrease split-ratio of focused container towards north
        - l: decrease split-ratio of focused container towards east

        - x: decrease horizontal gap
        - y: decrease vertical gap

        - p: decrease screen padding all directions
        - larrow: decrease screen padding-left
        - rarrow: decrease screen padding-right
        - uarrow: decrease screen padding-top
        - darrow: decrease screen padding-bottom

    - ctrl+shift:
        - x: detach marked window and insert at focused container
        - h: detach focused window and insert at west container
        - j: detach focused window and insert at south container
        - k: detach focused window and insert at north container
        - l: detach focused window and insert at east container

    - ctrl+alt:
        - m: swap with the marked window

        - h: swap with west window
        - j: swap with south window
        - k: swap with north window
        - l: swap with east window

        - 1: send window to screen id 0
        - 2: send window to screen id 1
        - 3: send window to screen id 2

    - cmd+alt
        - h: focus window west
        - j: focus window south
        - k: focus window north
        - l: focus window east

        - 1: give focus to screen id 0
        - 2: give focue to screen id 1
        - 3: give focus to screen id 2

    - cmd+ctrl:
        - a: set mode of current space to bsp
        - s: set mode of current space to monocle
        - d: set mode of current space to float
        - r: rotate window-tree by 90 degrees
