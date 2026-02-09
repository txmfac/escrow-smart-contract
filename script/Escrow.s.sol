// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {EscrowContract} from "../src/Escrow.sol";

contract DeployEscrowScript is Script {
    EscrowContract public escrow;

    function run() public {
        vm.startBroadcast();

        escrow = new EscrowContract();

        vm.stopBroadcast();
    }
}
