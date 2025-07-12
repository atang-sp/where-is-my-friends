#!/bin/bash

echo "Running database migration for where-is-my-friends plugin..."

# Check if we're in a Docker environment
if [ -f "/src/bin/rails" ]; then
    echo "Detected Docker environment, using /src/bin/rails"
    RAILS_PATH="/src/bin/rails"
elif [ -f "bin/rails" ]; then
    echo "Detected local environment, using bin/rails"
    RAILS_PATH="bin/rails"
else
    echo "Error: Could not find Rails executable"
    echo "Please run this script from the Discourse root directory"
    exit 1
fi

# Run the migration
echo "Running migration..."
$RAILS_PATH db:migrate

echo "Migration completed!"
echo "You can now restart your Discourse server and test the plugin." 