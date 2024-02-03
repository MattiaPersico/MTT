#!/bin/sh

# Define the base directory
REPO_ROOT="$(git rev-parse --show-toplevel)"
echo "Repository Root: $REPO_ROOT"

# Get current time in the required format
current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "Current Time: $current_time"

# Read the major and minor version from the Lua file
# Using awk to match the line, then extract the number part
major_version=$(awk -F "= " '/local major_version =/ {gsub(/[[:space:]]|,/, "", $2); print $2}' "$REPO_ROOT/ReAG/mtt_AudioGuide_Interface.lua")
minor_version=$(awk -F "= " '/local minor_version =/ {gsub(/[[:space:]]|,/, "", $2); print $2}' "$REPO_ROOT/ReAG/mtt_AudioGuide_Interface.lua")

echo "Major Version: $major_version"
echo "Minor Version: $minor_version"

# Construct the new version string
new_version="$major_version.$minor_version"
echo "New Version: $new_version"

# Use sed to update the version and time attributes in the XML file
# macOS's version of sed requires an empty string argument ('') after -i to edit in-place without backup
sed -i '' -e "s|<version name=\"[^\"]*\"|<version name=\"$new_version\"|g" -e "s|author=\"[^\"]*\" time=\"[^\"]*\"|author=\"Mattia Persico\" time=\"$current_time\"|g" "$REPO_ROOT/index.xml"

# Add the updated XML file to the commit
git add "$REPO_ROOT/index.xml"

# End the script
exit 0
