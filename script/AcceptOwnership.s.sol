// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

interface IGateway {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function acceptOwnership() external;
}

/**
 * @notice Complete the two-step Ownable2Step ownership transfer on WeteEgoGateway.
 *
 * Must be called by the pending owner (the Gnosis Safe) after TransferOwnership.s.sol
 * has been broadcast.
 *
 * Via Gnosis Safe UI (recommended for production):
 *   New transaction → To: GATEWAY_ADDRESS → Value: 0 → Data: 0x79ba5097
 *   Collect 2-of-3 signatures → Execute
 *
 * Via forge script with keystore (staging / single-signer EOA test):
 *   # Import the pending-owner key once:
 *   cast wallet import multisig-owner --interactive
 *
 *   export GATEWAY_ADDRESS=0xbe710276c4114c3846a209191a8800049b8ad0a6
 *
 *   # Dry-run (no --broadcast): prints Safe payload only
 *   forge script script/AcceptOwnership.s.sol --rpc-url base_sepolia --account multisig-owner
 *
 *   # Live broadcast:
 *   forge script script/AcceptOwnership.s.sol --rpc-url base_sepolia --account multisig-owner --broadcast
 */
contract AcceptOwnership is Script {
    function run() external {
        address gatewayAddr = vm.envAddress("GATEWAY_ADDRESS");
        IGateway gateway = IGateway(gatewayAddr);

        address pending = gateway.pendingOwner();
        address current = gateway.owner();

        console.log("Gateway address  :", gatewayAddr);
        console.log("Current owner    :", current);
        console.log("Pending owner    :", pending);
        console.log("");
        console.log("Safe transaction payload:");
        console.log("  To   :", gatewayAddr);
        console.log("  Value: 0");
        console.log("  Data : 0x79ba5097");
        console.log("");

        vm.startBroadcast();
        gateway.acceptOwnership();
        vm.stopBroadcast();

        console.log("acceptOwnership() executed.");
        console.log("New owner:", gateway.owner());
    }
}
