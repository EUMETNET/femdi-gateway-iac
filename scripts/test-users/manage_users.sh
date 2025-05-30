#!/bin/zsh
# test_users.sh - Setup venv, install deps, set env vars, and run create/delete for test-users

set -e

usage() {
  echo "Usage: $0 [create|delete]"
  exit 1
}

if [ $# -ne 1 ]; then
  usage
fi

CMD=$1
if [[ "$CMD" != "create" && "$CMD" != "delete" ]]; then
  usage
fi

# Set script dir to test-users/
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Create venv if not exists
if [ ! -d "venv" ]; then
  echo "Creating Python venv..."
  python3 -m venv venv
fi

# Activate venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt 1>/dev/null

# Check required env vars
REQUIRED_VARS=(CLUSTERS VAULT_TOKENS APISIX_API_KEYS)
for var in $REQUIRED_VARS; do
  if [[ -z ${(P)var} ]]; then
    echo ""
    echo "Error: Required variable '$var' is not set."
    deactivate
    exit 1
  fi
done

# Run the Python script
python generate_test_users.py $CMD

# Deactivate venv
deactivate
