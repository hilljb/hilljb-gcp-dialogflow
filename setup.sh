#!/bin/bash

# setup.sh - Idempotent script to create the project directory structure

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Setting up project directory structure..."

# Create the public web root and API directory
mkdir -p public/api

# Create the private directory for sensitive files (like the GCP JSON key)
mkdir -p private

# Create empty frontend files if they don't exist
touch public/index.html
touch public/app.js
touch public/style.css

# Create empty backend API file if it doesn't exist
touch public/api/chat.php

# Provide instructions for the GCP key
if [ ! -f "private/gcp-key.json" ]; then
    echo "Note: Please place your Google Cloud Service Account JSON key at 'private/gcp-key.json'."
fi

echo "Directory structure setup complete."
