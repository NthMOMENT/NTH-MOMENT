// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract IdentityRegistryTest is Test {
    IdentityRegistry registry;

    address owner = makeAddr("owner");
    address borrowerWallet = makeAddr("borrowerWallet");
    address anchorWallet = makeAddr("anchorWallet");
    address randomCaller = makeAddr("randomCaller");

    bytes32 constant SAMPLE_HASH = keccak256("kyc-session-id-001");

    event WalletRegistered(address indexed wallet, bytes32 kycHash);

    function setUp() public {
        registry = new IdentityRegistry(owner);
    }

    // ---------------------------------------------------------------
    // Happy path
    // ---------------------------------------------------------------

    function test_OwnerCanRegisterWallet() public {
        vm.prank(owner);
        registry.registerWallet(borrowerWallet, SAMPLE_HASH);

        assertTrue(registry.isVerified(borrowerWallet));
        assertEq(registry.getKycHash(borrowerWallet), SAMPLE_HASH);
    }

    function test_RegisterWalletEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit WalletRegistered(borrowerWallet, SAMPLE_HASH);
        registry.registerWallet(borrowerWallet, SAMPLE_HASH);
    }

    function test_UnregisteredWalletIsNotVerified() public view {
        assertFalse(registry.isVerified(borrowerWallet));
    }

    function test_UnregisteredWalletHasZeroKycHash() public view {
        assertEq(registry.getKycHash(borrowerWallet), bytes32(0));
    }

    function test_MultipleWalletsIndependentlyTracked() public {
        vm.startPrank(owner);
        registry.registerWallet(borrowerWallet, SAMPLE_HASH);
        vm.stopPrank();

        // anchorWallet was never registered — must remain false.
        assertTrue(registry.isVerified(borrowerWallet));
        assertFalse(registry.isVerified(anchorWallet));
    }

    // ---------------------------------------------------------------
    // Access control — the custody-boundary-adjacent checks
    // ---------------------------------------------------------------

    function test_NonOwnerCannotRegisterWallet() public {
        vm.prank(randomCaller);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomCaller)
        );
        registry.registerWallet(borrowerWallet, SAMPLE_HASH);
    }

    function test_IsVerifiedIsPermissionlessRead() public {
        // Anyone — including a contract simulating the Deal Contract caller —
        // must be able to call isVerified() without restriction.
        vm.prank(randomCaller);
        bool result = registry.isVerified(borrowerWallet);
        assertFalse(result);
    }

    function test_OwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        registry.transferOwnership(newOwner);
        assertEq(registry.owner(), newOwner);

        // Old owner should no longer be able to register.
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner)
        );
        registry.registerWallet(borrowerWallet, SAMPLE_HASH);

        // New owner can.
        vm.prank(newOwner);
        registry.registerWallet(borrowerWallet, SAMPLE_HASH);
        assertTrue(registry.isVerified(borrowerWallet));
    }

    // ---------------------------------------------------------------
    // Edge cases / revert conditions
    // ---------------------------------------------------------------

    function test_RevertWhen_RegisteringZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IdentityRegistry.ZeroAddress.selector)
        );
        registry.registerWallet(address(0), SAMPLE_HASH);
    }

    function test_RevertWhen_RegisteringWithEmptyKycHash() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IdentityRegistry.EmptyKycHash.selector)
        );
        registry.registerWallet(borrowerWallet, bytes32(0));
    }

    function test_RevertWhen_RegisteringAlreadyVerifiedWallet() public {
        vm.startPrank(owner);
        registry.registerWallet(borrowerWallet, SAMPLE_HASH);

        vm.expectRevert(
            abi.encodeWithSelector(IdentityRegistry.AlreadyRegistered.selector, borrowerWallet)
        );
        registry.registerWallet(borrowerWallet, SAMPLE_HASH);
        vm.stopPrank();
    }

    function test_RevertWhen_ReregisteringWithDifferentHash() public {
        // Confirms there is NO update/overwrite path in V1 — re-registration
        // with a different kycHash for an already-verified wallet must also
        // revert. (This is a deliberate V1 limitation: no revoke = no
        // re-verify either. A new KYC cycle for an existing wallet is not
        // supported by this contract version.)
        bytes32 differentHash = keccak256("kyc-session-id-002");
        vm.startPrank(owner);
        registry.registerWallet(borrowerWallet, SAMPLE_HASH);

        vm.expectRevert(
            abi.encodeWithSelector(IdentityRegistry.AlreadyRegistered.selector, borrowerWallet)
        );
        registry.registerWallet(borrowerWallet, differentHash);
        vm.stopPrank();

        // Original hash must remain untouched.
        assertEq(registry.getKycHash(borrowerWallet), SAMPLE_HASH);
    }

    // ---------------------------------------------------------------
    // Fuzz tests
    // ---------------------------------------------------------------

    function testFuzz_RegisterArbitraryWallet(address wallet, bytes32 kycHash) public {
        vm.assume(wallet != address(0));
        vm.assume(kycHash != bytes32(0));

        vm.prank(owner);
        registry.registerWallet(wallet, kycHash);

        assertTrue(registry.isVerified(wallet));
        assertEq(registry.getKycHash(wallet), kycHash);
    }

    function testFuzz_NonOwnerNeverSucceeds(address caller, address wallet, bytes32 kycHash) public {
        vm.assume(caller != owner);
        vm.assume(wallet != address(0));
        vm.assume(kycHash != bytes32(0));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller)
        );
        registry.registerWallet(wallet, kycHash);
    }
}
