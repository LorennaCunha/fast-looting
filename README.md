# Fast-Looting

**Fast-Looting** is a Bash script designed to mount Windows systems from a bootable USB drive in a Linux environment. It enables offline extraction of critical files, such as memory dumps, system logs, and user profiles, organizing the data into a structured directory for forensic analysis and security audits.

## Improvements Applied to the Code

- **USB Drive and Windows System Validation**: Verifies if the USB device is mounted and contains a valid Windows system.
- **Directory Structure**: Organizes extracted files into specific directories (`memory`, `registry`, `logs`, `users`).
- **Automatic Compression**: Compresses the extracted files into a single `.tar.gz` file for easy transport.
- **Detailed Logs**: Logs all steps of the process into a log file.
- **Error Handling**: Adds checks to ensure each step is completed successfully.
- **Modularization**: Divides the script into functions for better readability and maintainability.

## Features

- Mounts Windows systems from a bootable USB drive.
- Extracts critical files for offline analysis:
  - Memory dumps (`pagefile.sys`, `hiberfil.sys`).
  - Windows registry files.
  - System logs (`Security.evtx`, `System.evtx`, `Application.evtx`).
  - User profiles.
- Compresses the extracted files into a single `.tar.gz` file.
- Generates detailed logs for tracking operations performed.

## Prerequisites

- Linux operating system.
- Superuser (root) permissions.
- Dependencies:
  - `bash`
  - `mount`
  - `umount`
  - `mkdir`
  - `tar`
  - `gzip`
  - `lsblk`

## How to Use

1. Clone the repository:
   ```bash
   git clone https://github.com/LorennaCunha/fast-looting.git
   cd fast-looting
   ```

2. Make the script executable:
   ```bash
   chmod +x fast-looting.sh
   ```

3. Insert the bootable USB drive and identify the device:
   ```bash
   lsblk
   ```

4. Run the script, specifying the USB device and output directory (optional):
   ```bash
   sudo ./fast-looting.sh -d /dev/sdX -o /path/to/output
   ```

5. The compressed file with the results will be generated in the specified directory:
   ```
   fast-looting_YYYYMMDD_HHMM.tar.gz
   ```

## Output Structure

- **memory/**: Extracted memory dumps.
- **registry/**: Windows registry files.
- **logs/**: System logs.
- **users/**: User profiles.

## Legal Disclaimer

This script should only be used on systems you have explicit permission to access. Unauthorized use may violate local and international laws. The author is not responsible for any misuse of this tool.

## Contribution

Contributions are welcome! Feel free to open issues or submit pull requests.

## License

This project is licensed under the [MIT License](LICENSE).
