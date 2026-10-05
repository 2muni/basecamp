#!/bin/sh
set -eu

defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true

killall Finder >/dev/null 2>&1 || true
