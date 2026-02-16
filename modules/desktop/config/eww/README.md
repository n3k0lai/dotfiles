# Eww Sidebar Configuration

A custom Eww sidebar for Hyprland using the waves colorscheme.

## Features

- **Time & Date Display** - Large clock with date information
- **Workspace Indicator** - Interactive workspace switcher (1-10)
  - Click to switch workspaces
  - Shows active workspace
  - Indicates occupied workspaces
- **System Statistics**
  - CPU usage with progress bar
  - RAM usage with progress bar
  - Disk usage with progress bar
- **Volume Control**
  - Visual volume slider
  - Mute/unmute button
  - Dynamic volume icon
- **System Info**
  - Uptime display
  - Hostname

## Files

- `eww.yuck` - Main configuration and widget definitions
- `eww.css` - Styling with waves colorscheme
- `eww.scss` - SCSS source (optional, use if you have sass/sassc)
- `scripts/` - Helper scripts for dynamic data
  - `cpu.sh` - CPU usage percentage
  - `memory.sh` - Memory usage percentage
  - `volume.sh` - Volume control and icon
  - `workspaces.sh` - Workspace information
  - `current-workspace.sh` - Active workspace tracking

## Colors (Waves Theme)

- Primary Blue: `#6f95fc`
- Cyan: `#83d9f7`
- Teal: `#4ba69c`
- Green: `#bae67e`
- Dark Background: `#0A0E14`
- Foreground: `#bfbab0`
- Accent: `#9da09e`

## Usage

### Start/Stop
```fish
# Start daemon and open sidebar
eww daemon
eww open sidebar

# Close sidebar
eww close sidebar

# Reload configuration
eww reload

# Kill daemon
eww kill
```

### Debugging
```fish
# Check active windows
eww active-windows

# View state
eww state

# Get variable value
eww get <variable_name>
```

## Dependencies

- `eww` - The widget system
- `hyprland` - Window manager
- `wpctl` (pipewire) - Audio control
- `jq` - JSON processing
- `socat` - Socket communication for workspace events
- `free`, `df`, `top` - System information

## Integration

The sidebar is automatically launched by Hyprland via:
```hyprlang
exec-once = eww daemon
exec-once = eww open sidebar
```

Located in `~/.config/hypr/hyprland.conf`.

## Customization

### Adjust Width
Edit `eww.yuck`, change the `width` in the window geometry:
```lisp
:geometry (geometry :width "280px" ...)
```

### Change Update Intervals
Edit the `:interval` values in `eww.yuck`:
```lisp
(defpoll cpu_usage :interval "2s" ...)
```

### Modify Colors
Edit `eww.css` and change the color values.

### Add More Workspaces
The scripts currently handle workspaces 1-10. To change this, edit:
- `scripts/workspaces.sh` - Change the `seq 1 10` range

## Troubleshooting

### Sidebar not showing
```fish
eww kill
eww daemon
eww open sidebar
```

### Scripts not working
Make sure all scripts are executable:
```fish
chmod +x ~/.config/eww/scripts/*.sh
```

### Volume control not working
Ensure pipewire and wpctl are installed and running.

### Workspace switching not working
Make sure you're running Hyprland and have socat installed.
