#!/usr/bin/env node
/**
 * Updates addresses.json with the deployed Gateway address and prints env vars.
 * Usage:
 *   node scripts/update-addresses.js 0x<gateway_address>     # from deploy output
 *   node scripts/update-addresses.js                         # read from broadcast/ run-latest.json
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const ADDRESSES_JSON = path.join(ROOT, "addresses.json");
const BROADCAST_JSON = path.join(
  ROOT,
  "broadcast/DeployGateway.s.sol/84532/run-latest.json"
);

function getGatewayAddress() {
  const arg = process.argv[2];
  if (arg && arg.startsWith("0x") && arg.length === 42) {
    return arg;
  }
  if (fs.existsSync(BROADCAST_JSON)) {
    const data = JSON.parse(fs.readFileSync(BROADCAST_JSON, "utf8"));
    const tx = data.transactions?.find(
      (t) =>
        t.contractName === "WeteEgoGateway" ||
        (t.contractAddress && t.transactionType === "CREATE")
    );
    const addr = tx?.contractAddress;
    if (addr) return addr;
    const first = data.transactions?.find((t) => t.contractAddress);
    if (first?.contractAddress) return first.contractAddress;
  }
  return null;
}

const gateway = getGatewayAddress();
if (!gateway) {
  console.error(
    "Usage: node scripts/update-addresses.js 0x<gateway_address>"
  );
  console.error(
    "  Or run after deploy (broadcast/.../run-latest.json present) with no args."
  );
  process.exit(1);
}

const addresses = JSON.parse(fs.readFileSync(ADDRESSES_JSON, "utf8"));
if (addresses.baseSepolia) {
  addresses.baseSepolia.gateway = gateway;
}
fs.writeFileSync(ADDRESSES_JSON, JSON.stringify(addresses, null, 2) + "\n");
console.log("Updated addresses.json: baseSepolia.gateway =", gateway);
console.log("");
console.log("Set the following in your env files:");
console.log("");
console.log("  # WeteEgo-backend/.env");
console.log("  GATEWAY_ADDRESS=" + gateway);
console.log("");
console.log("  # WeteEgo-order-service/.env");
console.log("  GATEWAY_ADDRESS=" + gateway);
console.log("");
console.log("  # WeteEgo-frontend/.env.local");
console.log("  NEXT_PUBLIC_GATEWAY_ADDRESS=" + gateway);
