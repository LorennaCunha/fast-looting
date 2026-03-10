#!/bin/bash
set -euo pipefail

# Default configurations
DATE=$(date +%Y%m%d_%H%M)
DEFAULT_USB_DEVICE="/dev/sdX"  # Replace with the default device if necessary
DEFAULT_OUTPUT_DIR="$HOME/fast_looting_$DATE"
MOUNT_DIR="/mnt/windows"
LOG_FILE=""

# Logging function
log() {
    local message="$1"
    echo "[$(date '+%H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Cleanup function to unmount and remove temporary directories
cleanup() {
    log "Cleaning up..."
    umount "$MOUNT_DIR" 2>/dev/null || true
    rm -rf "$MOUNT_DIR"
}

# Error handling function
error_exit() {
    log "[ERROR] $1"
    cleanup
    exit 1
}

# Check for required dependencies
check_dependencies() {
    local dependencies=("mount" "umount" "mkdir" "tar" "gzip" "lsblk")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            error_exit "Dependency not found: $cmd"
        fi
    done
}

# Detect filesystem type and mount the USB device
mount_usb() {
    log "Detecting filesystem for USB device $USB_DEVICE..."
    FS_TYPE=$(blkid -o value -s TYPE "$USB_DEVICE" 2>/dev/null || error_exit "Failed to detect filesystem type.")
    log "Filesystem detected: $FS_TYPE"

    log "Mounting USB device $USB_DEVICE..."
    mkdir -p "$MOUNT_DIR"

    case "$FS_TYPE" in
        ntfs)
            mount -t ntfs "$USB_DEVICE" "$MOUNT_DIR" || error_exit "Failed to mount NTFS filesystem."
            ;;
        vfat)
            mount -t vfat "$USB_DEVICE" "$MOUNT_DIR" || error_exit "Failed to mount FAT32 filesystem."
            ;;
        exfat)
            mount -t exfat "$USB_DEVICE" "$MOUNT_DIR" || error_exit "Failed to mount exFAT filesystem."
            ;;
        *)
            error_exit "Unsupported filesystem type: $FS_TYPE"
            ;;
    esac

    log "USB device mounted at $MOUNT_DIR."
}

# Validate if the mounted device contains a valid Windows system
validate_windows() {
    log "Validating Windows system..."
    if [ ! -d "$MOUNT_DIR/Windows/System32" ]; then
        error_exit "Windows system not found on the mounted device."
    fi
    log "Windows system validated."
}

# Extract critical files from the mounted Windows system
extract_files() {
    log "Extracting files to $OUTPUT_DIR..."
    mkdir -p "$OUTPUT_DIR"/{memory,registry,logs,users}

    # Copy memory dump files
    cp -v "$MOUNT_DIR/pagefile.sys" "$OUTPUT_DIR/memory/" 2>/dev/null || log "pagefile.sys not found."
    cp -v "$MOUNT_DIR/hiberfil.sys" "$OUTPUT_DIR/memory/" 2>/dev/null || log "hiberfil.sys not found."

    # Copy Windows registry files
    cp -v "$MOUNT_DIR/Windows/System32/config/"* "$OUTPUT_DIR/registry/" 2>/dev/null || log "Registry files not found."

    # Copy system logs
    cp -v "$MOUNT_DIR/Windows/System32/winevt/Logs/"* "$OUTPUT_DIR/logs/" 2>/dev/null || log "System logs not found."

    # Copy user profiles
    cp -r "$MOUNT_DIR/Users/"* "$OUTPUT_DIR/users/" 2>/dev/null || log "User profiles not found."

    log "File extraction completed."
}

# Compress the extracted files into a single tar.gz file
compress_output() {
    log "Compressing extracted files..."
    tar -czf "$OUTPUT_DIR.tar.gz" -C "$OUTPUT_DIR" .
    log "Compressed file created: $OUTPUT_DIR.tar.gz"
}

# Display help message
show_help() {
    echo "Usage: $0 [-d USB_DEVICE] [-o OUTPUT_DIR]"
    echo ""
    echo "Options:"
    echo "  -d USB_DEVICE   Specify the USB device to mount (default: $DEFAULT_USB_DEVICE)"
    echo "  -o OUTPUT_DIR   Specify the output directory for extracted files (default: $DEFAULT_OUTPUT_DIR)"
    echo "  -h              Show this help message"
}

# Process command-line arguments
process_args() {
    USB_DEVICE="$DEFAULT_USB_DEVICE"
    OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"

    while getopts "d:o:h" opt; do
        case "$opt" in
            d) USB_DEVICE="$OPTARG" ;;
            o) OUTPUT_DIR="$OPTARG" ;;
            h) show_help; exit 0 ;;
            *) show_help; exit 1 ;;
        esac
    done

    LOG_FILE="$OUTPUT_DIR/fast_looting.log"
}

# Main script flow
main() {
    trap cleanup EXIT
    process_args "$@"
    check_dependencies
    mount_usb
    validate_windows
    extract_files
    compress_output
    log "Fast Looting process completed successfully."
}

main "$@"
