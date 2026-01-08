#!/bin/bash
set -e

# =============================================================================
# disable-download.sh
# =============================================================================
# Disables file download capability in JupyterLab file browser.
# =============================================================================

# Disable the download extension in JupyterLab file browser
jupyter labextension disable @jupyterlab/filebrowser-extension:download

# Note: This only hides the UI element.
# Users can still technically access files if they have other network paths or code execution privileges.
# Network-level data exfiltration protection should be handled via VPC Endpoints and SCPs.

