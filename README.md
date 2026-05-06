# macOS Admin Toolkit

A collection of macOS scripts, Jamf Extension Attributes, and Apple endpoint automation examples for real-world device management workflows.

This repository is focused on practical Apple endpoint engineering patterns, including inventory, compliance checks, troubleshooting helpers, application deployment workflows, user-friendly prompts, and Jamf-oriented automation.

## Contents

### Scripts

- `app-download-and-install.sh`  
  General macOS installer workflow for `.zip`, `.pkg`, and `.dmg` payloads.

- `app-maintenance-deferral-template.sh`  
  Example user deferral workflow with version comparison, logging, and Jamf policy orchestration.

- `automatic-timezone-toggle.sh`  
  Utility script for toggling automatic time zone behavior on macOS.

- `change-current-user-picture.zsh`  
  Example workflow for changing the current user profile picture.

- `depnotify-zero-touch-setup.sh`  
  Example DEPNotify-based zero-touch setup workflow with policy sequencing.

- `jamf-inventory-at-startup-launchdaemon.sh`  
  LaunchDaemon example for triggering Jamf inventory at startup.

- `monthly-app-maintenance.zsh`  
  App discovery and maintenance workflow using Installomator labels, swiftDialog progress UI, and deferral scheduling.

- `prompt-users-to-restart.zsh`  
  User-friendly restart prompt workflow with logging and dry-run behavior.

- `rename-computer-by-serial.zsh`  
  Managed-device naming pattern based on serial number.

### Jamf Extension Attributes

- `dictation-usage-check.sh`  
  Lightweight Extension Attribute example for reporting dictation usage state.

- `ea-crowdstrike-status.sh`  
  Reports CrowdStrike Falcon status for Jamf inventory.

- `ea-uptime-status.sh`  
  Reports device uptime for inventory and reporting.

- `ea-admin-users-status.sh`  
  Reports users with local admin rights.

## Featured Workflows

### Monthly App Maintenance

`monthly-app-maintenance.zsh` is the strongest example in this toolkit. It demonstrates app discovery, version checks, Installomator integration, swiftDialog progress UI, user deferral logic, and scheduled maintenance concepts.

### Zero-Touch Setup

`depnotify-zero-touch-setup.sh` demonstrates an enrollment workflow pattern using DEPNotify and Jamf policy sequencing.

## Focus Areas

- macOS endpoint management
- Jamf Pro workflows
- Extension Attributes
- device compliance checks
- patching and update workflows
- SwiftDialog-style user prompts
- Installomator workflows
- automation for Apple IT teams

## Notes

These examples are sanitized and intended for learning, reference, and adaptation. Review and test all scripts before using them in production.

## Author

Created by Gabriel Marcelino / GT Solution.
