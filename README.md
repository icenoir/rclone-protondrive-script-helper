# BACKUP SCRIPT #
# Complete Backup Script
This is your complete "all-in-one" backup script!

## How to Use:

### 1. Save the Script

# Create the directory and save the script
```
mkdir -p ~/scripts
cd ~/scripts
git clone https://github.com/icenoir/rclone-protondrive-script-helper.git
cd rclone-protondrive-script-helper
```

# Make it executable
```
chmod +x backup-proton-complete.sh
```

### 2. Customize the Backup Directories
Edit the BACKUP_SOURCES section in the script:
```
BACKUP_SOURCES=(
    "/opt/etc:backup-etc"                    # Your current directories
    "$HOME/.env:backup-env"                  # Add more directories as needed
    "$HOME/docker:backup-docker"             # Format: source:destination-name
)
```

### 3. Initial Configuration

# Make sure rclone is configured
```
rclone config
```

# Test the script
```
./backup-proton-complete.sh config    # Show configuration
./backup-proton-complete.sh test      # Test the connection
```

# Start the daemon
```
./backup-proton-complete.sh start
```

# Check status
```
./backup-proton-complete.sh status
```

# Run the backup
```
./backup-proton-complete.sh backup
```

# Stop the daemon
```
./backup-proton-complete.sh stop
```

# Show logs
```
./backup-proton-complete.sh logs
```

# Show complete help
```
./backup-proton-complete.sh help
```

### Automation (Optional):

# Add to cron for automatic backups
```
crontab -e
```

# Daily backup at 2:00 AM (with daemon always running)
```
0 2 * * * ~/scripts/rclone-protondrive-script-helper/backup-proton-complete.sh backup
```

# Weekly daemon restart (Sunday at 1:00 AM)
```
0 1 * * 0 ~/scriptsrclone-protondrive-script-helper/backup-proton-complete.sh restart
```

## Main Features:
* Smart Daemon: Automatically starts when needed
* Secure Backup: Dry-run before actual backup
* Permission Management: Automatically uses sudo when necessary
* Detailed Logs: Tracks everything
* Versioning: Creates copies with timestamps
* Resilient Connection: Fallback from daemon to direct connection
* Flexible Configuration: Easily add new directories
* The script is ready to use! Just customize the directories in the BACKUP_SOURCES section and you're good to go.
