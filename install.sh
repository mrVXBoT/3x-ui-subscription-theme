#!/usr/bin/env bash
#
# 3x-ui Modern Subscription Theme Installer
# Minimalist, high-performance subscription theme for 3x-ui with Happ Proxy support.
#
# GitHub: https://github.com/mrVXBoT/3x-ui-subscription-theme
# License: MIT
#

set -e

# Configuration
THEME_DIR_DEFAULT="/etc/x-ui/sub"
XUI_DB_PATH="/etc/x-ui/x-ui.db"
REPO_RAW_URL="https://raw.githubusercontent.com/mrVXBoT/3x-ui-subscription-theme/main"
SCRIPT_VERSION="1.0.0"

# ANSI Colors (disabled if non-interactive or unsupported)
if [ -t 1 ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_BLUE="\033[34m"
    C_CYAN="\033[36m"
else
    C_RESET=""
    C_BOLD=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
fi

# Print Helpers
info() {
    printf "%b[*]%b %s\n" "$C_BLUE" "$C_RESET" "$1"
}

success() {
    printf "%b[+]%b %b%s%b\n" "$C_GREEN" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
}

warn() {
    printf "%b[!]%b %s\n" "$C_YELLOW" "$C_RESET" "$1"
}

error() {
    printf "%b[-] ERROR:%b %s\n" "$C_RED" "$C_RESET" "$1" >&2
}

fatal() {
    error "$1"
    exit 1
}

# Verification & Preflight
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fatal "This command requires root privileges. Please re-run with sudo or as root."
    fi
}

check_dependencies() {
    local missing=()
    for cmd in curl install; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        warn "Missing required packages: ${missing[*]}"
        info "Attempting to install dependencies..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq && apt-get install -y -qq "${missing[@]}" sqlite3
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q "${missing[@]}" sqlite
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q "${missing[@]}" sqlite
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy --noconfirm "${missing[@]}" sqlite
        elif command -v apk >/dev/null 2>&1; then
            apk add --no-cache "${missing[@]}" sqlite
        elif command -v zypper >/dev/null 2>&1; then
            zypper --quiet install -y "${missing[@]}" sqlite3
        else
            fatal "Please install: ${missing[*]}"
        fi
    fi
}

check_xui_installation() {
    if [ ! -d "/usr/local/x-ui" ] && [ ! -d "/etc/x-ui" ]; then
        warn "3x-ui installation directory was not detected at standard locations (/etc/x-ui, /usr/local/x-ui)."
        printf "Continue anyway? (y/N): "
        read -r choice
        case "$choice" in
            [yY]|[yY][eE][sS]) ;;
            *) exit 0 ;;
        esac
    fi
}

# Resolve Theme Source (local file or remote fetch)
get_theme_source() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

    if [ -f "$script_dir/theme/index.html" ]; then
        echo "$script_dir/theme/index.html"
    elif [ -f "$script_dir/index.html" ]; then
        echo "$script_dir/index.html"
    else
        echo "remote"
    fi
}

# Core Actions
do_backup() {
    check_root
    local target_dir="${1:-$THEME_DIR_DEFAULT}"
    local backup_file
    backup_file="$target_dir/index.html.bak.$(date +%Y%m%d_%H%M%S)"

    if [ -f "$target_dir/index.html" ]; then
        info "Backing up existing index.html to: $backup_file"
        cp -a "$target_dir/index.html" "$backup_file"
        
        # Save a persistent original backup if not exists
        if [ ! -f "$target_dir/index.html.orig" ]; then
            cp -a "$target_dir/index.html" "$target_dir/index.html.orig"
            info "Created base original backup: $target_dir/index.html.orig"
        fi
        success "Backup created successfully."
    else
        warn "No existing index.html found in $target_dir to backup."
    fi
}

do_install() {
    check_root
    check_dependencies
    check_xui_installation

    local target_dir="$THEME_DIR_DEFAULT"
    mkdir -p "$target_dir"

    # Backup if existing
    if [ -f "$target_dir/index.html" ]; then
        do_backup "$target_dir"
    fi

    local src
    src="$(get_theme_source)"

    info "Deploying theme template to $target_dir/index.html..."
    if [ "$src" = "remote" ]; then
        local tmp_file
        tmp_file="$(mktemp)"
        info "Downloading latest release template from repository..."
        if ! curl -fsSL "$REPO_RAW_URL/theme/index.html" -o "$tmp_file"; then
            rm -f "$tmp_file"
            fatal "Failed to download theme template. Please check internet connection."
        fi
        install -m 644 "$tmp_file" "$target_dir/index.html"
        rm -f "$tmp_file"
    else
        info "Installing from local file: $src"
        install -m 644 "$src" "$target_dir/index.html"
    fi

    # Configure 3x-ui SQLite database if present
    if [ -f "$XUI_DB_PATH" ] && command -v sqlite3 >/dev/null 2>&1; then
        info "Configuring subThemeDir in 3x-ui database..."
        sqlite3 "$XUI_DB_PATH" "DELETE FROM settings WHERE key='subThemeDir'; INSERT INTO settings (key, value) VALUES ('subThemeDir', '$target_dir');" 2>/dev/null || true
    fi

    # Reload 3x-ui service gracefully
    info "Applying configuration and reloading 3x-ui service..."
    if command -v systemd-run >/dev/null 2>&1 && systemctl is-active --quiet x-ui; then
        systemd-run --on-active=2s systemctl restart x-ui >/dev/null 2>&1
    elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet x-ui; then
        (sleep 2 && systemctl restart x-ui) >/dev/null 2>&1 &
    elif command -v x-ui >/dev/null 2>&1; then
        (sleep 2 && x-ui restart) >/dev/null 2>&1 &
    fi

    echo ""
    success "3x-ui Obsidian Theme successfully installed!"
    info "Target Location: $target_dir/index.html"
    info "Happ Proxy 1-Click integration is now live on all client subscription links."
}

do_restore() {
    check_root
    local target_dir="$THEME_DIR_DEFAULT"

    if [ -f "$target_dir/index.html.orig" ]; then
        info "Restoring base original template ($target_dir/index.html.orig)..."
        cp -a "$target_dir/index.html.orig" "$target_dir/index.html"
        success "Original template restored."
    elif compgen -G "$target_dir/index.html.bak.*" > /dev/null; then
        local latest_bak
        latest_bak="$(find "$target_dir" -maxdepth 1 -name "index.html.bak.*" | sort -r | head -n 1)"
        info "Restoring from latest backup: $latest_bak"
        cp -a "$latest_bak" "$target_dir/index.html"
        success "Restored from backup: $latest_bak"
    else
        warn "No backup files found in $target_dir."
        printf "Do you want to remove the custom index.html completely? (y/N): "
        read -r choice
        case "$choice" in
            [yY]|[yY][eE][sS])
                rm -f "$target_dir/index.html"
                info "Removed custom index.html."
                ;;
            *)
                info "Action aborted."
                return
                ;;
        esac
    fi

    # Clean subThemeDir setting if restoring default
    if [ -f "$XUI_DB_PATH" ] && command -v sqlite3 >/dev/null 2>&1; then
        info "Resetting subThemeDir configuration..."
        sqlite3 "$XUI_DB_PATH" "UPDATE settings SET value='' WHERE key='subThemeDir';" 2>/dev/null || true
    fi

    # Reload 3x-ui
    info "Applying configuration and reloading 3x-ui service..."
    if command -v systemd-run >/dev/null 2>&1 && systemctl is-active --quiet x-ui; then
        systemd-run --on-active=2s systemctl restart x-ui >/dev/null 2>&1
    elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet x-ui; then
        (sleep 2 && systemctl restart x-ui) >/dev/null 2>&1 &
    elif command -v x-ui >/dev/null 2>&1; then
        (sleep 2 && x-ui restart) >/dev/null 2>&1 &
    fi

    success "3x-ui restored to default configuration."
}

do_status() {
    echo ""
    printf "%b========================================%b\n" "$C_BOLD" "$C_RESET"
    printf "%b       3x-ui Subscription Status        %b\n" "$C_BOLD" "$C_RESET"
    printf "%b========================================%b\n" "$C_BOLD" "$C_RESET"

    # Service Status
    printf "Service Status   : "
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet x-ui; then
            printf "%bActive (Running)%b\n" "$C_GREEN" "$C_RESET"
        else
            printf "%bInactive / Stopped%b\n" "$C_RED" "$C_RESET"
        fi
    else
        printf "%bUnknown (systemctl unavailable)%b\n" "$C_YELLOW" "$C_RESET"
    fi

    # Theme File
    printf "Theme File       : "
    if [ -f "$THEME_DIR_DEFAULT/index.html" ]; then
        local fsize
        fsize="$(du -h "$THEME_DIR_DEFAULT/index.html" | cut -f1)"
        printf "%bInstalled (%s)%b at %s\n" "$C_GREEN" "$fsize" "$C_RESET" "$THEME_DIR_DEFAULT/index.html"
    else
        printf "%bDefault (Not installed)%b\n" "$C_YELLOW" "$C_RESET"
    fi

    # Database Setting
    if [ -f "$XUI_DB_PATH" ] && command -v sqlite3 >/dev/null 2>&1; then
        local current_db_theme
        current_db_theme="$(sqlite3 "$XUI_DB_PATH" "SELECT value FROM settings WHERE key='subThemeDir';" 2>/dev/null || echo '')"
        printf "Database Setting : "
        if [ -n "$current_db_theme" ]; then
            printf "%b%s%b\n" "$C_CYAN" "$current_db_theme" "$C_RESET"
        else
            printf "%bDefault (Built-in)%b\n" "$C_YELLOW" "$C_RESET"
        fi
    fi

    # Backups Count
    local bak_count
    bak_count="$(find "$THEME_DIR_DEFAULT" -maxdepth 1 -name "index.html.bak.*" 2>/dev/null | wc -l)"
    printf "Backups Available: %s\n" "$bak_count"
    printf "%b========================================%b\n" "$C_BOLD" "$C_RESET"
    echo ""
}

show_help() {
    cat << EOF
3x-ui Subscription Theme Installer (v$SCRIPT_VERSION)

Usage:
  bash install.sh [OPTION]

Options:
  -i, --install     Install or update the custom subscription theme
  -r, --restore     Restore the original default theme from backup
  -b, --backup      Create a backup of the current theme file
  -s, --status      Check current service and theme status
  -h, --help        Show this help message

Interactive Mode:
  Run without arguments to launch the text management menu.

EOF
}

interactive_menu() {
    clear 2>/dev/null || true
    cat << EOF
======================================================
         3x-ui Modern Subscription Theme
               Version $SCRIPT_VERSION
======================================================
  [1] Install / Update Theme
  [2] Restore Default Theme
  [3] Create Backup
  [4] View Theme & Service Status
  [0] Exit
------------------------------------------------------
EOF
    printf "Enter choice [0-4]: "
    read -r choice
    case "$choice" in
        1)
            echo ""
            do_install
            ;;
        2)
            echo ""
            do_restore
            ;;
        3)
            echo ""
            do_backup
            ;;
        4)
            do_status
            ;;
        0|q|Q)
            exit 0
            ;;
        *)
            warn "Invalid option. Exiting."
            exit 1
            ;;
    esac
}

# Main Entry Point
main() {
    case "${1:-}" in
        -i|--install)
            do_install
            ;;
        -r|--restore)
            do_restore
            ;;
        -b|--backup)
            do_backup
            ;;
        -s|--status)
            do_status
            ;;
        -h|--help)
            show_help
            ;;
        "")
            interactive_menu
            ;;
        *)
            error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
