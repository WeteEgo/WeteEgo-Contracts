#!/usr/bin/env bash
# Interactive deploy for WeteEgoGateway: prompts for private key (no key in .env).
# Usage: ./scripts/deploy-gateway-interactive.sh
# Optional env: RPC_URL, BASESCAN_API_KEY (or you will be prompted for API key if not set).

set -e
cd "$(dirname "$0")/.."

echo "=== WeteEgoGateway deploy (interactive) ==="
echo ""

# Load .env for SETTLEMENT_ADDRESS, SETTLER_ADDRESS (no PRIVATE_KEY)
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

for var in SETTLEMENT_ADDRESS SETTLER_ADDRESS; do
  if [ -z "${!var}" ]; then
    echo "Error: $var must be set in .env"
    exit 1
  fi
done

echo "Settlement: $SETTLEMENT_ADDRESS"
echo "Settler:    $SETTLER_ADDRESS"
echo ""

# Prompt for private key (not stored)
echo "Enter deployer private key (with Base Sepolia ETH); input is hidden:"
read -rs PRIVATE_KEY
echo ""
if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: PRIVATE_KEY is empty"
  exit 1
fi
# Ensure 0x prefix for forge
[[ "$PRIVATE_KEY" != 0x* ]] && PRIVATE_KEY="0x$PRIVATE_KEY"
export PRIVATE_KEY

# Optional: Basescan API key for verification
if [ -z "${BASESCAN_API_KEY}" ]; then
  echo "Enter Basescan API key (or leave empty to skip verification):"
  read -r BASESCAN_API_KEY
  export BASESCAN_API_KEY
fi

RPC_URL="${RPC_URL:-https://sepolia.base.org}"
echo ""
echo "RPC: $RPC_URL"
echo "Deploying..."
echo ""

forge script script/DeployGateway.s.sol \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify \
  ${BASESCAN_API_KEY:+--etherscan-api-key "$BASESCAN_API_KEY"}

echo ""
echo "=== Updating addresses.json and printing env vars ==="
node scripts/update-addresses.js
