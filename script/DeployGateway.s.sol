// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {WeteEgoGateway} from "../src/WeteEgoGateway.sol";

contract DeployGatewayScript is Script {
    function run() external {
        address settlement = vm.envAddress("SETTLEMENT_ADDRESS");
        address settler = vm.envAddress("SETTLER_ADDRESS");

        vm.startBroadcast();
        WeteEgoGateway gateway = new WeteEgoGateway(settlement, settler);
        vm.stopBroadcast();

        console.log("WeteEgoGateway deployed at:", address(gateway));
        console.log("Settlement address:", gateway.settlementAddress());
        console.log("Settler:", gateway.settler());
    }
}
