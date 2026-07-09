// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DealContract} from "../src/DealContract.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";

contract DealContractTest is Test {
    IdentityRegistry registry;
    DealContract dealContract;

    address registryOwner = makeAddr("registryOwner");
    address borrower = makeAddr("borrower");
    address anchor = makeAddr("anchor");
    address lender = makeAddr("lender");
    address escrow = makeAddr("escrow"); // placeholder address; Escrow Settlement contract not yet built (Month 2 follow-up)
    address randomCaller = makeAddr("randomCaller");

    uint256 constant FACE_VALUE = 500_000e6; // 500k USDC, 6 decimals
    uint256 constant RATE_BPS = 350; // 3.5%
    bytes32 constant DOC_HASH = keccak256("tri-party-agreement-v1");

    uint256 maturityDate;

    event DealCreated(
        address indexed borrower,
        address indexed anchor,
        address indexed lender,
        uint256 faceValue,
        uint256 rate,
        uint256 maturityDate,
        bytes32 docHash,
        address escrowAddress
    );

    function setUp() public {
        registry = new IdentityRegistry(registryOwner);
        maturityDate = block.timestamp + 60 days;

        dealContract = new DealContract(
            address(registry),
            borrower,
            anchor,
            lender,
            FACE_VALUE,
            RATE_BPS,
            maturityDate,
            DOC_HASH,
            escrow
        );
    }

    function _verifyAll() internal {
        vm.startPrank(registryOwner);
        registry.registerWallet(lender, keccak256("kyc-lender"));
        registry.registerWallet(anchor, keccak256("kyc-anchor"));
        registry.registerWallet(borrower, keccak256("kyc-borrower"));
        vm.stopPrank();
    }

    // ---------------------------------------------------------------
    // Construction / terms
    // ---------------------------------------------------------------

    function test_DealCreatedWithCorrectTerms() public view {
        assertEq(dealContract.borrower(), borrower);
        assertEq(dealContract.anchor(), anchor);
        assertEq(dealContract.lender(), lender);
        assertEq(dealContract.faceValue(), FACE_VALUE);
        assertEq(dealContract.rate(), RATE_BPS);
        assertEq(dealContract.maturityDate(), maturityDate);
        assertEq(dealContract.docHash(), DOC_HASH);
        assertEq(dealContract.escrowAddress(), escrow);
        assertEq(uint8(dealContract.status()), uint8(DealContract.Status.PENDING));
    }

    function test_RevertWhen_MaturityDateInPast() public {
        vm.expectRevert(DealContract.MaturityMustBeFuture.selector);
        new DealContract(
            address(registry), borrower, anchor, lender,
            FACE_VALUE, RATE_BPS, block.timestamp - 1, DOC_HASH, escrow
        );
    }

    function test_RevertWhen_MaturityDateExactlyEqualsBlockTimestamp() public {
        // Boundary precision per tech doc Section 6.2 item 4: the check is
        // `_maturityDate <= block.timestamp`, so a maturityDate EQUAL to
        // the current block.timestamp must also revert — "future" means
        // strictly after now, not "now or later." Previously only the
        // clearly-in-the-past case (block.timestamp - 1) was tested; the
        // exact equality boundary was never confirmed.
        vm.expectRevert(DealContract.MaturityMustBeFuture.selector);
        new DealContract(
            address(registry), borrower, anchor, lender,
            FACE_VALUE, RATE_BPS, block.timestamp, DOC_HASH, escrow
        );
    }

    function test_MaturityDateOneSecondInFutureSucceeds() public {
        // The exact transition point: block.timestamp + 1 is the first
        // valid maturityDate.
        DealContract d = new DealContract(
            address(registry), borrower, anchor, lender,
            FACE_VALUE, RATE_BPS, block.timestamp + 1, DOC_HASH, escrow
        );
        assertEq(d.maturityDate(), block.timestamp + 1);
    }

    function test_RevertWhen_ZeroFaceValue() public {
        vm.expectRevert(DealContract.ZeroFaceValue.selector);
        new DealContract(
            address(registry), borrower, anchor, lender,
            0, RATE_BPS, maturityDate, DOC_HASH, escrow
        );
    }

    function test_RevertWhen_EmptyDocHash() public {
        vm.expectRevert(DealContract.EmptyDocHash.selector);
        new DealContract(
            address(registry), borrower, anchor, lender,
            FACE_VALUE, RATE_BPS, maturityDate, bytes32(0), escrow
        );
    }

    function test_RevertWhen_EscrowAddressZero() public {
        vm.expectRevert(DealContract.ZeroAddress.selector);
        new DealContract(
            address(registry), borrower, anchor, lender,
            FACE_VALUE, RATE_BPS, maturityDate, DOC_HASH, address(0)
        );
    }

    // ---------------------------------------------------------------
    // Signing order: Lender -> Anchor -> Borrower (strict)
    // ---------------------------------------------------------------

    function test_LenderCanSignFirst() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();
        assertTrue(dealContract.lenderSigned());
    }

    function test_RevertWhen_AnchorSignsBeforeLender() public {
        _verifyAll();
        vm.prank(anchor);
        vm.expectRevert(DealContract.WrongSigningOrder.selector);
        dealContract.signAsAnchor();
    }

    function test_RevertWhen_BorrowerSignsBeforeAnchor() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();

        vm.prank(borrower);
        vm.expectRevert(DealContract.WrongSigningOrder.selector);
        dealContract.signAsBorrower();
    }

    function test_RevertWhen_BorrowerSignsBeforeLenderOrAnchor() public {
        _verifyAll();
        vm.prank(borrower);
        vm.expectRevert(DealContract.WrongSigningOrder.selector);
        dealContract.signAsBorrower();
    }

    function test_FullSigningSequenceInCorrectOrder() public {
        _verifyAll();

        vm.prank(lender);
        dealContract.signAsLender();

        vm.prank(anchor);
        dealContract.signAsAnchor();

        vm.prank(borrower);
        dealContract.signAsBorrower();

        assertTrue(dealContract.allSigned());
    }

    function test_RevertWhen_SameWalletSignsTwice() public {
        _verifyAll();
        vm.startPrank(lender);
        dealContract.signAsLender();
        vm.expectRevert(DealContract.AlreadySigned.selector);
        dealContract.signAsLender();
        vm.stopPrank();
    }

    // ---------------------------------------------------------------
    // KYC gating — every signature requires isVerified()
    // ---------------------------------------------------------------

    function test_RevertWhen_LenderNotKycVerified() public {
        // Deliberately skip _verifyAll() — lender wallet was never registered.
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(DealContract.NotVerified.selector, lender));
        dealContract.signAsLender();
    }

    function test_RevertWhen_AnchorNotKycVerified() public {
        // Only register lender, leave anchor unverified.
        vm.prank(registryOwner);
        registry.registerWallet(lender, keccak256("kyc-lender"));

        vm.prank(lender);
        dealContract.signAsLender();

        vm.prank(anchor);
        vm.expectRevert(abi.encodeWithSelector(DealContract.NotVerified.selector, anchor));
        dealContract.signAsAnchor();
    }

    function test_RevertWhen_BorrowerNotKycVerified() public {
        vm.startPrank(registryOwner);
        registry.registerWallet(lender, keccak256("kyc-lender"));
        registry.registerWallet(anchor, keccak256("kyc-anchor"));
        vm.stopPrank();

        vm.prank(lender);
        dealContract.signAsLender();
        vm.prank(anchor);
        dealContract.signAsAnchor();

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(DealContract.NotVerified.selector, borrower));
        dealContract.signAsBorrower();
    }

    // ---------------------------------------------------------------
    // Wrong-caller checks (e.g. random address pretending to be a party)
    // ---------------------------------------------------------------

    function test_RevertWhen_RandomCallerSignsAsLender() public {
        _verifyAll();
        vm.prank(randomCaller);
        vm.expectRevert(DealContract.OnlyLender.selector);
        dealContract.signAsLender();
    }

    function test_RevertWhen_RandomCallerSignsAsAnchor() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();

        vm.prank(randomCaller);
        vm.expectRevert(DealContract.OnlyAnchor.selector);
        dealContract.signAsAnchor();
    }

    function test_RevertWhen_RandomCallerSignsAsBorrower() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();
        vm.prank(anchor);
        dealContract.signAsAnchor();

        vm.prank(randomCaller);
        vm.expectRevert(DealContract.OnlyBorrower.selector);
        dealContract.signAsBorrower();
    }

    // ---------------------------------------------------------------
    // markActive() — callback from the Escrow Contract, replaces the old
    // fundDeal() flow (funding logic now lives entirely on
    // EscrowSettlement.sol; see test/EscrowSettlement.t.sol for the real
    // fund-pulling/disbursement tests). This contract only needs to
    // verify the callback's own access control and state transition.
    // ---------------------------------------------------------------

    function test_RevertWhen_MarkActiveCalledBeforeAllSigned() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();
        // Anchor and Borrower have not signed yet.

        vm.prank(escrow);
        vm.expectRevert(DealContract.NotAllSigned.selector);
        dealContract.markActive();
    }

    function test_RevertWhen_MarkActiveCalledByNonEscrow() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();
        vm.prank(anchor);
        dealContract.signAsAnchor();
        vm.prank(borrower);
        dealContract.signAsBorrower();

        // Even the Lender, who legitimately drove signing, cannot call
        // markActive() directly — only the registered escrowAddress can.
        vm.prank(lender);
        vm.expectRevert(DealContract.OnlyEscrow.selector);
        dealContract.markActive();

        vm.prank(randomCaller);
        vm.expectRevert(DealContract.OnlyEscrow.selector);
        dealContract.markActive();
    }

    function test_MarkActiveActivatesDealAfterAllSigned() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();
        vm.prank(anchor);
        dealContract.signAsAnchor();
        vm.prank(borrower);
        dealContract.signAsBorrower();

        vm.prank(escrow);
        dealContract.markActive();

        assertEq(uint8(dealContract.status()), uint8(DealContract.Status.ACTIVE));
    }

    function test_RevertWhen_SigningAfterActive() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();
        vm.prank(anchor);
        dealContract.signAsAnchor();
        vm.prank(borrower);
        dealContract.signAsBorrower();
        vm.prank(escrow);
        dealContract.markActive();

        // Re-attempting any signature post-ACTIVE must revert via the
        // DealNotPending gate, confirming immutability of an ACTIVE dealContract.
        vm.prank(lender);
        vm.expectRevert(DealContract.DealNotPending.selector);
        dealContract.signAsLender();
    }

    // ---------------------------------------------------------------
    // Expiry / cancellation — 7 calendar days
    // ---------------------------------------------------------------

    function test_RevertWhen_CancelBeforeWindowExpires() public {
        vm.expectRevert(DealContract.SigningWindowNotExpired.selector);
        dealContract.cancelDeal();
    }

    function test_RevertWhen_CancelOneSecondBeforeExpiry() public {
        vm.warp(block.timestamp + 7 days - 1);
        vm.expectRevert(DealContract.SigningWindowNotExpired.selector);
        dealContract.cancelDeal();
    }

    function test_CancelSucceedsExactlyAtWindowExpiry() public {
        vm.warp(block.timestamp + 7 days);
        dealContract.cancelDeal();
        assertEq(uint8(dealContract.status()), uint8(DealContract.Status.CANCELLED));
    }

    function test_CancelCallableByAnyone() public {
        vm.warp(block.timestamp + 7 days);
        vm.prank(randomCaller);
        dealContract.cancelDeal();
        assertEq(uint8(dealContract.status()), uint8(DealContract.Status.CANCELLED));
    }

    function test_RevertWhen_CancellingAlreadyActiveDeal() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();
        vm.prank(anchor);
        dealContract.signAsAnchor();
        vm.prank(borrower);
        dealContract.signAsBorrower();
        vm.prank(escrow);
        dealContract.markActive();

        vm.warp(block.timestamp + 7 days);
        vm.expectRevert(DealContract.DealNotPending.selector);
        dealContract.cancelDeal();
    }

    function test_RevertWhen_CancellingAlreadyCancelledDeal() public {
        vm.warp(block.timestamp + 7 days);
        dealContract.cancelDeal();

        vm.expectRevert(DealContract.DealNotPending.selector);
        dealContract.cancelDeal();
    }

    function test_PartiallySignedDealCanStillBeCancelledAfterExpiry() public {
        _verifyAll();
        vm.prank(lender);
        dealContract.signAsLender();
        // Anchor and Borrower never sign.

        vm.warp(block.timestamp + 7 days);
        dealContract.cancelDeal();
        assertEq(uint8(dealContract.status()), uint8(DealContract.Status.CANCELLED));
    }

    // ---------------------------------------------------------------
    // No on-chain fee logic on cancellation (explicit design confirmation)
    // ---------------------------------------------------------------

    function test_CancelDealHasNoStablecoinTransferLogic() public {
        // This test exists to document/lock the explicit decision that
        // cancelDeal() moves no funds and charges no protocol fee. There
        // is no stablecoin contract wired into DealContract at all, so
        // this is really a compile-time/architectural guarantee — this
        // test asserts the dealContract's faceValue and escrow address are
        // unchanged by cancellation, the only state cancelDeal() is
        // permitted to touch is `status`.
        vm.warp(block.timestamp + 7 days);
        dealContract.cancelDeal();

        assertEq(dealContract.faceValue(), FACE_VALUE);
        assertEq(dealContract.escrowAddress(), escrow);
    }
}
