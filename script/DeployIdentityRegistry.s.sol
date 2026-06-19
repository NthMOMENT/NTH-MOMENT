// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";

/// @notice Deploys IdentityRegistry with msg.sender (the deployer's wallet,
///         from PRIVATE_KEY env var) as the initial owner.
/// @dev Per business doc Section 6.1-6.2: this is identity-attestation
///      ownership only. This deployer key never touches deal funds — that
///      property lives in the Escrow Settlement contract (Month 2), which
///      will have no owner/admin function at all.
contract DeployIdentityRegistry is Script {
    function run() external returns (IdentityRegistry) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        IdentityRegistry registry = new IdentityRegistry(deployer);
        vm.stopBroadcast();

        console.log("IdentityRegistry deployed at:", address(registry));
        console.log("Owner set to:", deployer);

        return registry;
    }
}
