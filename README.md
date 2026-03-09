# WeteEgo-Contracts

EVM router on Base for WeteEgo. **Option A (Paycrest):** Router accepts USDC (and optionally ETH) and forwards to the **Paycrest gateway** address; Paycrest aggregator handles matching and fiat payout. Emits `SwapForwarded` for indexing and status tracking.

## Contracts

- **WeteEgoRouter**: `forwardERC20(token, amount, settlementRef)` and `forwardETH(settlementRef)`. Settlement address is set at deploy time.

## Setup

```bash
# Install Forge (https://book.getfoundry.sh/getting-started/installation)
# Install deps (already done if you cloned with lib)
forge install OpenZeppelin/openzeppelin-contracts
```

## Configure

```bash
cp .env.example .env
# Edit .env: set PRIVATE_KEY, SETTLEMENT_ADDRESS, and RPC URLs.
```

## Build

```bash
forge build
```

## Deploy

**Base Sepolia (testnet):**

```bash
# In .env: SETTLEMENT_ADDRESS = Paycrest gateway (see Paycrest docs) or test EOA for Base Sepolia
# BASE_SEPOLIA_RPC_URL = https://sepolia.base.org (or Alchemy/Infura)
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
```

**Base mainnet:**

```bash
forge script script/Deploy.s.sol --rpc-url base --broadcast --verify
```

After deploy, save the logged router address for the frontend (`NEXT_PUBLIC_ROUTER_ADDRESS`).

## Addresses (to be filled after deploy)

| Network     | Chain ID | WeteEgoRouter | USDC |
|------------|----------|---------------|------|
| Base Sepolia | 84532    | (deploy and paste) | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| Base mainnet  | 8453     | (deploy and paste) | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |

## License

MIT
