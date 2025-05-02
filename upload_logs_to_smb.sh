#!/bin/bash

###########################################################
# Script      : upload_logs_to_smb.sh                     #
# Description : Collects system logs and uploads to SMB.  #
# Author      : lizia102                                  #
# Date        : $(date +%Y-%m-%d)                         #
# Version     : 1.0                                       #
###########################################################

# ===== Configuration Variables (Modify as Needed) =====
SMB_SHARE="//your_smb_server/share_name"  # SMB network share path
SMB_USER="your_username"                  # SMB username
SMB_PASSWORD="your_password"              # SMB password
MOUNT_POINT="/mnt/smb_logs"               # Local mount directory for SMB

# ===== Generate Dynamic Filename =====
# Extract machine model (filter special chars)
MACHINE_MODEL=$(dmidecode -s system-product-name 2>/dev/null | tr -cd '[:alnum:]-_.' | sed 's/[ /]/-/g' || echo "UnknownModel")

# Extract OS info (fallback to lsb_release if /etc/os-release missing)
OS_INFO=$( (cat /etc/os-release 2>/dev/null | grep PRETTY_NAME || lsb_release -d) | awk -F'"' '{print $2}' 2>/dev/null | tr -cd '[:alnum:]-_ .' | sed 's/[ /]/-/g' || echo "UnknownOS")

# Timestamp for unique filenames
DATE_STAMP=$(date +%Y%m%d_%H%M%S)

# Final log filename format: 
# e.g., "LinuxLogs_Dell-PowerEdge-R740_Ubuntu-22.04.3-LTS_20231205_1630.tar.gz"
BACKUP_FILE="LinuxLogs_${MACHINE_MODEL}_${OS_INFO}_${DATE_STAMP}.tar.gz"

# ===== Prepare Temporary Directory =====
BACKUP_DIR="/tmp/logs_backup_${DATE_STAMP}"
mkdir -p "$BACKUP_DIR"

# ===== Collect System Information =====
echo "[+] Collecting system information..."
{
    echo "===== SYSTEM INFO ====="
    echo "Hostname: $(hostname)"
    echo "Machine Model: $(dmidecode -s system-product-name 2>/dev/null || echo "Unknown")"
    echo "OS Info: $(cat /etc/os-release 2>/dev/null || lsb_release -d 2>/dev/null || echo "Unknown")"
    echo "Kernel Version: $(uname -r)"
    echo "Uptime: $(uptime)"
    echo "CPU Info: $(lscpu | grep 'Model name')"
    echo "===== NETWORK INFO ====="
    ip a
    echo "===== DISK USAGE ====="
    df -h
} > "$BACKUP_DIR/system_info.txt"

# ===== Gather Log Files =====
echo "[+] Collecting logs..."
# System logs
cp /var/log/syslog* "$BACKUP_DIR/" 2>/dev/null
cp /var/log/messages* "$BACKUP_DIR/" 2>/dev/null
cp /var/log/auth.log* "$BACKUP_DIR/" 2>/dev/null
cp /var/log/kern.log* "$BACKUP_DIR/" 2>/dev/null
cp /var/log/dmesg* "$BACKUP_DIR/" 2>/dev/null

# Journald logs (systemd systems)
journalctl -xe --no-pager > "$BACKUP_DIR/journalctl.log" 2>/dev/null

# ===== Compress Logs =====
echo "[+] Compressing logs to $BACKUP_FILE..."
tar -czf "/tmp/$BACKUP_FILE" -C "$BACKUP_DIR" .

# ===== Upload to SMB Share =====
echo "[+] Mounting SMB share..."
sudo mkdir -p "$MOUNT_POINT"

# Mount SMB (adjust 'vers=' for compatibility)
sudo mount -t cifs "$SMB_SHARE" "$MOUNT_POINT" -o username="$SMB_USER",password="$SMB_PASSWORD",vers=2.1

# Verify mount success
if mountpoint -q "$MOUNT_POINT"; then
    echo "[+] Uploading $BACKUP_FILE to SMB share..."
    cp "/tmp/$BACKUP_FILE" "$MOUNT_POINT/"
    sudo umount "$MOUNT_POINT"
    echo "[+] Uploaded: $BACKUP_FILE --> $SMB_SHARE/"
else
    echo "[-] Failed to mount SMB share!"
    exit 1
fi

# ===== Cleanup =====
rm -rf "$BACKUP_DIR" "/tmp/$BACKUP_FILE"
echo "[+] Done! Logs saved as: $BACKUP_FILE"
