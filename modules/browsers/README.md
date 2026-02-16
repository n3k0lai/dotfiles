# Browser Configuration Management

## Decision: Browsers Self-Manage Their Configs

This directory contains browser module definitions (`brave.nix`, `chrome.nix`, `firefox.nix`, `zen.nix`, `luakit.nix`) that **only install packages** and do not manage XDG configuration files.

### Rationale

Browser configurations are intentionally left unmanaged by NixOS for the following reasons:

1. **Secret Leakage Prevention** - Browser configs contain sensitive data:
   - Session cookies and authentication tokens
   - Saved passwords and autofill data
   - Browsing history and cache
   - Extension tokens and API keys
   
2. **High Volatility** - Browser configs change frequently through GUI interactions:
   - Bookmark additions/modifications
   - Extension installations and updates
   - Theme and appearance changes
   - Privacy and security settings adjustments
   
3. **Conflict Avoidance** - Symlinked configs can conflict with browser's self-management:
   - Extension auto-updates may fail
   - Settings sync (Firefox Sync, Chrome Sync) may break
   - Cache and session management conflicts
   
4. **User Experience** - Browsers expect write access to their config directories:
   - Profile management
   - Download settings
   - Site-specific permissions
   - Form data and search history

### Alternative Approaches

If you need to manage specific browser settings declaratively:

#### Firefox
Use home-manager's `programs.firefox` for **extensions only**:
```nix
home-manager.users.nicho = {
  programs.firefox = {
    enable = true;
    profiles.default = {
      extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        bitwarden
      ];
    };
  };
};
```

#### Chrome/Brave
Manage **policies** via enterprise policy files (not user preferences):
```nix
environment.etc."chromium/policies/managed/default.json".text = builtins.toJSON {
  # Enterprise policies only
  DefaultBrowserSettingEnabled = false;
};
```

### Manual Backup Strategy

For important browser data:

1. **Bookmarks** - Export as HTML/JSON periodically
2. **Extensions** - Document list in this README
3. **Settings** - Screenshot important configurations
4. **Passwords** - Use external password manager (Bitwarden, 1Password, etc.)

### Current Browser Installations

- **Brave** - Primary browser for Web3/crypto
- **Firefox** - Default browser, privacy-focused
- **Chrome** - Testing and development
- **Zen** - Experimental browser
- **Luakit** - Minimal/keyboard-driven browser (`BROWSER_MIN`)

All browsers install packages only; configs remain in `~/.config/` and are gitignored.
