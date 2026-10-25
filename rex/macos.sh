#!/bin/sh
set -eu

if [ "$(uname -s)" != Darwin ]; then
    printf '%s\n' 'Rex preferences can only be applied on macOS.' >&2
    exit 1
fi

# Temporary macOS preference overrides; see README.md for the Rex config boundary.
defaults write com.superlogical.rex Workspace.terminalFontName -string 'JetBrains Mono'
defaults write com.superlogical.rex Workspace.terminalFontPointSize -float 14
defaults write com.superlogical.rex Workspace.terminalFontSmoothing -bool false

defaults write com.superlogical.rex Workspace.darkThemeID -string 'static-noir'
defaults write com.superlogical.rex Workspace.lightThemeID -string 'merino-light'
defaults write com.superlogical.rex Workspace.interfaceStyle -string 'blendTheme'
defaults write com.superlogical.rex Workspace.usesPaneGlass -bool true
defaults write com.superlogical.rex Workspace.paneDensity -string 'comfortable'
defaults write com.superlogical.rex Workspace.tabsFillAvailableSpace -bool false
