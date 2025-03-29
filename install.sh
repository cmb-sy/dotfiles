#!/bin/bash

# This is a wrapper script that calls the main installation script in the setup directory
# It exists for backwards compatibility with CI workflows

echo "Running main install script at ./setup/install.sh"
./setup/install.sh
