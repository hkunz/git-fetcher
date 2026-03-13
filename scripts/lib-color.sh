#!/usr/bin/env bash
# colors.sh - ANSI color helpers for git-fetcher
# Usage: source "colors.sh" in your scripts

# =============================================
# Reset
# =============================================
COLOR_RESET="\033[0m"
BOLD="\033[1m"

# =============================================
# Standard Colors
# =============================================
COLOR_BLACK="\033[30m"
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_MAGENTA="\033[35m"
COLOR_CYAN="\033[36m"
COLOR_WHITE="\033[37m"

# =============================================
# Bright / Light Colors
# =============================================
COLOR_BRIGHT_BLACK="\033[1;30m"
COLOR_BRIGHT_RED="\033[1;31m"
COLOR_BRIGHT_GREEN="\033[1;32m"
COLOR_BRIGHT_YELLOW="\033[1;33m"
COLOR_BRIGHT_BLUE="\033[1;34m"
COLOR_BRIGHT_MAGENTA="\033[1;35m"
COLOR_BRIGHT_CYAN="\033[1;36m"
COLOR_BRIGHT_WHITE="\033[1;37m"

# =============================================
# Helper: colorize text
# =============================================
color_text() {
    local color="$1"
    local text="$2"
    echo -e "${color}${text}${COLOR_RESET}"
}

color_reset() {
    echo -e "${COLOR_RESET}"
}

# =============================================
# Convenience wrappers: Normal colors
# =============================================
black()   { color_text "$COLOR_BLACK" "$1"; }
red()     { color_text "$COLOR_RED" "$1"; }
green()   { color_text "$COLOR_GREEN" "$1"; }
yellow()  { color_text "$COLOR_YELLOW" "$1"; }
blue()    { color_text "$COLOR_BLUE" "$1"; }
magenta() { color_text "$COLOR_MAGENTA" "$1"; }
cyan()    { color_text "$COLOR_CYAN" "$1"; }
white()   { color_text "$COLOR_WHITE" "$1"; }

# =============================================
# Convenience wrappers: Bright / Light colors
# =============================================
bright_black()   { color_text "$COLOR_BRIGHT_BLACK" "$1"; }
bright_red()     { color_text "$COLOR_BRIGHT_RED" "$1"; }
bright_green()   { color_text "$COLOR_BRIGHT_GREEN" "$1"; }
bright_yellow()  { color_text "$COLOR_BRIGHT_YELLOW" "$1"; }
bright_blue()    { color_text "$COLOR_BRIGHT_BLUE" "$1"; }
bright_magenta() { color_text "$COLOR_BRIGHT_MAGENTA" "$1"; }
bright_cyan()    { color_text "$COLOR_BRIGHT_CYAN" "$1"; }
bright_white()   { color_text "$COLOR_BRIGHT_WHITE" "$1"; }

# =============================================
# Bold wrappers
# =============================================
bold() { color_text "$BOLD" "$1"; }

# Bold + Normal color
bold_black()   { echo -e "${BOLD}${COLOR_BLACK}$1${COLOR_RESET}"; }
bold_red()     { echo -e "${BOLD}${COLOR_RED}$1${COLOR_RESET}"; }
bold_green()   { echo -e "${BOLD}${COLOR_GREEN}$1${COLOR_RESET}"; }
bold_yellow()  { echo -e "${BOLD}${COLOR_YELLOW}$1${COLOR_RESET}"; }
bold_blue()    { echo -e "${BOLD}${COLOR_BLUE}$1${COLOR_RESET}"; }
bold_magenta() { echo -e "${BOLD}${COLOR_MAGENTA}$1${COLOR_RESET}"; }
bold_cyan()    { echo -e "${BOLD}${COLOR_CYAN}$1${COLOR_RESET}"; }
bold_white()   { echo -e "${BOLD}${COLOR_WHITE}$1${COLOR_RESET}"; }

# Bold + Bright color
bold_bright_black()   { echo -e "${BOLD}${COLOR_BRIGHT_BLACK}$1${COLOR_RESET}"; }
bold_bright_red()     { echo -e "${BOLD}${COLOR_BRIGHT_RED}$1${COLOR_RESET}"; }
bold_bright_green()   { echo -e "${BOLD}${COLOR_BRIGHT_GREEN}$1${COLOR_RESET}"; }
bold_bright_yellow()  { echo -e "${BOLD}${COLOR_BRIGHT_YELLOW}$1${COLOR_RESET}"; }
bold_bright_blue()    { echo -e "${BOLD}${COLOR_BRIGHT_BLUE}$1${COLOR_RESET}"; }
bold_bright_magenta() { echo -e "${BOLD}${COLOR_BRIGHT_MAGENTA}$1${COLOR_RESET}"; }
bold_bright_cyan()    { echo -e "${BOLD}${COLOR_BRIGHT_CYAN}$1${COLOR_RESET}"; }
bold_bright_white()   { echo -e "${BOLD}${COLOR_BRIGHT_WHITE}$1${COLOR_RESET}"; }