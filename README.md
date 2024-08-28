# PowerShell Cleanup Automation

### This version is refactored using Powershell 7.x

## Overview
PowerShell Cleanup Automation is a script designed to automate the cleanup of specified directories on your Windows system. It allows you to specify directories for cleanup in a configuration file and provides options for logging the cleanup process with different levels of detail. This script supports multi-threading for efficient file deletion and includes configurable settings for customizing the cleanup process.

## Features
- **Automated Cleanup**: Recursively delete files and directories based on paths specified in the configuration file.
- **Multi-threading**: Support for concurrent file deletion with customizable thread count.
- **Logging**: Configurable logging with multiple levels (none, error, warning, info, debug) to track the cleanup process.
- **Configurable Settings**: All settings are managed through a simple `config.ini` file, allowing easy customization.
- **Log Retention**: Automatically manage and retain logs based on a specified retention period.

## Installation
1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/CkBcDD/PowerShell-Cleanup-Automation.git
   ```
2. Navigate to the project directory:
   ```bash
   cd PowerShell-Cleanup-Automation
   ```
## Configuration
The script is configured through the config.ini file.

## Usage
Modify the config.ini file to specify the directories you want to clean and adjust the logging and threading settings as needed.
Run the script using PowerShell:
   ```powershell
   .\Program.ps1
   ```
## Requirements
- PowerShell 7.x.
- Proper permissions to delete files in the specified directories.

## License
This project is licensed under the MIT License. See the LICENSE file for more details.

## Contributing
This repo is made under the help from ChatGPT.

Feel free to open issues and submit pull requests. Contributions are welcome!

Contact
For any inquiries or support, please contact [jiangbingquqi@proton.me].
