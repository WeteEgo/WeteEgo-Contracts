// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

interface IRouter {
    function owner() external view returns (address);
    function setOwner(address newOwner) external;
}

interface IGateway {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
}

/**
 * @notice Transfer ownership of WeteEgoRouter and WeteEgoGateway to a Gnosis Safe multisig.
 *
 * Required env vars:
 *   MULTISIG_ADDRESS    — Gnosis Safe address to transfer ownership to
 *   ROUTER_ADDRESS      — deployed WeteEgoRouter address (optional; skip if empty)
 *   GATEWAY_ADDRESS     — deployed WeteEgoGateway address
 *
 * Uses Foundry keystore — no plain-text private key needed.
 * Import your deployer wallet once: cast wallet import deployer --interactive
 *
 * WeteEgoRouter uses a one-step setOwner() — ownership transfers immediately.
 * WeteEgoGateway uses Ownable2Step — the multisig must call acceptOwnership() to complete.
 *
 * Run:
 *   forge script script/TransferOwnership.s.sol \
 *     --rpc-url base_sepolia \
 *     --account deployer \
 *     --broadcast \
 *     --verify
 */
contract TransferOwnership is Script {
    function run() external {
        address multisig = vm.envAddress("MULTISIG_ADDRESS");
        address gatewayAddr = vm.envAddress("GATEWAY_ADDRESS");

        require(multisig != address(0), "MULTISIG_ADDRESS not set");
        require(gatewayAddr != address(0), "GATEWAY_ADDRESS not set");

        vm.startBroadcast();

        // ── WeteEgoRouter ────────────────────────────────────────────────────
        bytes memory routerEnv = abi.encode(vm.envOr("ROUTER_ADDRESS", address(0)));
        address routerAddr = abi.decode(routerEnv, (address));
        if (routerAddr != address(0)) {
            IRouter router = IRouter(routerAddr);
            address currentOwner = router.owner();
            console.log("Router current owner:", currentOwner);
            router.setOwner(multisig);
            console.log("Router.setOwner() called -> new owner:", multisig);
        } else {
            console.log("ROUTER_ADDRESS not set, skipping router ownership transfer");
        }

        // ── WeteEgoGateway (Ownable2Step) ────────────────────────────────────
        IGateway gateway = IGateway(gatewayAddr);
        address gatewayOwner = gateway.owner();
        console.log("Gateway current owner:", gatewayOwner);
        gateway.transferOwnership(multisig);
        console.log("Gateway.transferOwnership() called -> pending owner:", multisig);
        console.log("ACTION REQUIRED: multisig must call Gateway.acceptOwnership() to complete transfer");

        vm.stopBroadcast();
    }
}
