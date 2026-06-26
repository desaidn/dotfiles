# Do not ship a Finder opener app

Finder "Open With" integration is outside this repo's Code Interface. The previous AppleScript opener created a self-signed macOS app that can be blocked on managed machines as an unknown developer, so the repo now keeps code entry through Neovim and terminal tools instead of shipping an OS launcher convenience.
