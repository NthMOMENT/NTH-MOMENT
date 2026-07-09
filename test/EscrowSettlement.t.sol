// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {DealContract} from "../src/DealContract.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {EscrowSettlement} from "../src/EscrowSettlement.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract EscrowSettlementTest is Test {
    IdentityRegistry registry;
    DealContract dealContract;
    EscrowSettlement escrow;
    MockUSDC usdc;

    address registryOwner = makeAddr("registryOwner");
    address borrower = makeAddr("borrower");
    address anchor = makeAddr("anchor");
    address lender = makeAddr("lender");
    address treasury = makeAddr("treasury");
    address randomCaller = makeAddr("randomCaller");

    uint256 constant FACE_VALUE = 500_000e6; // 500k USDC
    uint256 constant RATE_BPS = 350; // 3.5% discount -> Lender's yield
    uint256 constant FEE_BPS = 100; // 1% protocol fee, within business doc's 75-175bps combined range
    bytes32 constant DOC_HASH = keccak256("tri-party-agreement-v1");

    uint256 maturityDate;

    uint256 constant DISCOUNT = (FACE_VALUE * RATE_BPS) / 10_000; // 17,500e6
    uint256 constant FUNDED_AMOUNT = FACE_VALUE - DISCOUNT; // 482,500e6
    uint256 constant PROTOCOL_FEE = (FACE_VALUE * FEE_BPS) / 10_000; // 5,000e6

    function setUp() public {
        registry = new IdentityRegistry(registryOwner);
        usdc = new MockUSDC();
        maturityDate = block.timestamp + 60 days;

        // Deployment order matches tech doc Section 4.4: Identity Registry
        // -> Deal Contract -> Escrow Settlement. Since DealContract's
        // constructor requires escrowAddress up front, we predict Escrow's
        // create-address before deploying Deal, matching how this would
        // work in a real deploy script.
        address predictedDealAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        uint256 nonceAfterDeal = vm.getNonce(address(this)) + 1;
        address predictedEscrowAddr = vm.computeCreateAddress(address(this), nonceAfterDeal);

        dealContract = new DealContract(
            address(registry), borrower, anchor, lender,
            FACE_VALUE, RATE_BPS, maturityDate, DOC_HASH, predictedEscrowAddr
        );
        require(address(dealContract) == predictedDealAddr, "dealContract address prediction mismatch");

        escrow = new EscrowSettlement(address(dealContract), address(usdc), treasury, FEE_BPS);
        require(address(escrow) == predictedEscrowAddr, "escrow address prediction mismatch");

        usdc.mint(lender, 10_000_000e6);
        usdc.mint(anchor, 10_000_000e6);
    }

    function _signAll() internal {
        vm.startPrank(registryOwner);
        registry.registerWallet(lender, keccak256("kyc-lender"));
        registry.registerWallet(anchor, keccak256("kyc-anchor"));
        registry.registerWallet(borrower, keccak256("kyc-borrower"));
        vm.stopPrank();

        vm.prank(lender);
        dealContract.signAsLender();
        vm.prank(anchor);
        dealContract.signAsAnchor();
        vm.prank(borrower);
        dealContract.signAsBorrower();
    }

    function _fundDeal() internal {
        _signAll();
        vm.prank(lender);
        usdc.approve(address(escrow), FUNDED_AMOUNT + PROTOCOL_FEE);
        vm.prank(lender);
        escrow.fundDeal();
    }

    // ---------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------

    function test_ConstructorSetsCorrectState() public view {
        assertEq(address(escrow.deal()), address(dealContract));
        assertEq(address(escrow.settlementToken()), address(usdc));
        assertEq(escrow.treasury(), treasury);
        assertEq(escrow.feeRateBps(), FEE_BPS);
        assertFalse(escrow.funded());
    }

    function test_RevertWhen_FeeRateExceedsCap() public {
        vm.expectRevert(EscrowSettlement.FeeRateTooHigh.selector);
        new EscrowSettlement(address(dealContract), address(usdc), treasury, 501);
    }

    function test_RevertWhen_ZeroTreasuryAddress() public {
        vm.expectRevert(EscrowSettlement.ZeroAddress.selector);
        new EscrowSettlement(address(dealContract), address(usdc), address(0), FEE_BPS);
    }

    // ---------------------------------------------------------------
    // Disbursement (fundDeal)
    // ---------------------------------------------------------------

    function test_RevertWhen_FundDealBeforeAllSigned() public {
        vm.prank(registryOwner);
        registry.registerWallet(lender, keccak256("kyc-lender"));
        vm.prank(lender);
        dealContract.signAsLender();

        vm.prank(lender);
        vm.expectRevert(EscrowSettlement.DealTermsNotSigned.selector);
        escrow.fundDeal();
    }

    function test_RevertWhen_NonLenderCallsFundDeal() public {
        _signAll();
        vm.prank(randomCaller);
        vm.expectRevert(EscrowSettlement.NotLender.selector);
        escrow.fundDeal();
    }

    function test_RevertWhen_FundDealCalledWithoutApproval() public {
        _signAll();
        vm.prank(lender);
        vm.expectRevert();
        escrow.fundDeal();
    }

    function test_FundDealCorrectSplit() public {
        _signAll();

        uint256 lenderBalBefore = usdc.balanceOf(lender);
        uint256 borrowerBalBefore = usdc.balanceOf(borrower);
        uint256 treasuryBalBefore = usdc.balanceOf(treasury);

        vm.prank(lender);
        usdc.approve(address(escrow), FUNDED_AMOUNT + PROTOCOL_FEE);
        vm.prank(lender);
        escrow.fundDeal();

        assertEq(usdc.balanceOf(lender), lenderBalBefore - FUNDED_AMOUNT - PROTOCOL_FEE);
        assertEq(usdc.balanceOf(borrower), borrowerBalBefore + FUNDED_AMOUNT);
        assertEq(usdc.balanceOf(treasury), treasuryBalBefore + PROTOCOL_FEE);
        assertEq(usdc.balanceOf(address(escrow)), 0);

        assertTrue(escrow.funded());
        assertEq(escrow.fundedAmount(), FUNDED_AMOUNT);
        assertEq(escrow.protocolFeeCollected(), PROTOCOL_FEE);
    }

    function test_FundDealMarksDealActive() public {
        _signAll();
        vm.prank(lender);
        usdc.approve(address(escrow), FUNDED_AMOUNT + PROTOCOL_FEE);
        vm.prank(lender);
        escrow.fundDeal();

        assertEq(uint8(dealContract.status()), uint8(DealContract.Status.ACTIVE));
    }

    function test_RevertWhen_FundDealCalledTwice() public {
        _fundDeal();

        vm.prank(lender);
        usdc.approve(address(escrow), FUNDED_AMOUNT + PROTOCOL_FEE);
        vm.prank(lender);
        vm.expectRevert(EscrowSettlement.AlreadyFunded.selector);
        escrow.fundDeal();
    }

    // ---------------------------------------------------------------
    // markActive() access control (defense in depth, tested from Deal side)
    // ---------------------------------------------------------------

    function test_RevertWhen_NonEscrowCallsMarkActive() public {
        vm.prank(randomCaller);
        vm.expectRevert(DealContract.OnlyEscrow.selector);
        dealContract.markActive();
    }

    function test_RevertWhen_LenderDirectlyCallsMarkActive() public {
        _signAll();
        vm.prank(lender);
        vm.expectRevert(DealContract.OnlyEscrow.selector);
        dealContract.markActive();
    }

    // ---------------------------------------------------------------
    // Settlement (receivePayment) — permissionless by design
    // ---------------------------------------------------------------

    function test_RevertWhen_ReceivePaymentBeforeFunded() public {
        vm.prank(anchor);
        vm.expectRevert(EscrowSettlement.NotYetFunded.selector);
        escrow.receivePayment(FACE_VALUE);
    }

    function test_ReceivePaymentRecordsCorrectAmount() public {
        _fundDeal();

        vm.warp(maturityDate);
        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        assertTrue(escrow.paymentReceived());
        assertEq(escrow.actualAmountReceived(), FACE_VALUE);
    }

    function test_RevertWhen_ReceivePaymentCalledTwice() public {
        _fundDeal();
        vm.warp(maturityDate);
        vm.startPrank(anchor);
        usdc.approve(address(escrow), FACE_VALUE * 2);
        escrow.receivePayment(FACE_VALUE);

        vm.expectRevert(EscrowSettlement.AlreadyPaymentReceived.selector);
        escrow.receivePayment(FACE_VALUE);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------
    // Tech doc Section 6.2, item 1: Early payment — Anchor pays before
    // maturity. receivePayment() has no maturity-date gate by design
    // (business doc Section 3.1 notes Anchor payment can occur "before
    // due too"), but this was never previously exercised by a test —
    // an untested-but-presumed-correct path is exactly what this section
    // of the tech doc warns against.
    // ---------------------------------------------------------------

    function test_EarlyPayment_WellBeforeMaturity() public {
        _fundDeal();

        // Deliberately do NOT warp time forward — block.timestamp is still
        // at deal creation time, far short of the 60-day maturityDate.
        assertLt(block.timestamp, maturityDate);

        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        assertTrue(escrow.paymentReceived());
        assertEq(escrow.actualAmountReceived(), FACE_VALUE);
    }

    function test_EarlyPayment_OneSecondBeforeMaturity() public {
        _fundDeal();
        vm.warp(maturityDate - 1);

        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        assertTrue(escrow.paymentReceived());
    }

    function test_EarlyPayment_ThenDistributeWorksNormally() public {
        // Confirms the full lifecycle completes correctly even when
        // payment arrives early — distribute() doesn't implicitly assume
        // maturity has passed.
        _fundDeal();
        // No warp — payment arrives immediately after funding.

        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        uint256 lenderBalBefore = usdc.balanceOf(lender);
        escrow.distribute();

        assertEq(usdc.balanceOf(lender), lenderBalBefore + FACE_VALUE);
        assertTrue(escrow.distributed());
    }

    // ---------------------------------------------------------------
    // Tech doc Section 6.2, item 2: Late payment — Anchor pays after
    // maturity but before any default action (handleDefault() never
    // called). Previously every test only exercised payment AT exactly
    // maturity; "after maturity, default not yet flagged" was untested.
    // ---------------------------------------------------------------

    function test_LatePayment_AfterMaturityBeforeDefaultFlagged() public {
        _fundDeal();
        vm.warp(maturityDate + 3 days); // realistically late, e.g. a few days overdue

        // Confirm handleDefault() has NOT been called — this is exactly
        // the "before any default action" condition from the tech doc.
        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        assertTrue(escrow.paymentReceived());
        assertEq(escrow.actualAmountReceived(), FACE_VALUE);
    }

    function test_LatePayment_ThenDistributeStillWorksNormally() public {
        _fundDeal();
        vm.warp(maturityDate + 3 days);

        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        uint256 lenderBalBefore = usdc.balanceOf(lender);
        escrow.distribute();

        // Late payment still settles correctly — being late does not, by
        // itself, trigger any penalty in the current contract logic (no
        // late-fee mechanism exists in V1; this test documents that
        // absence as confirmed-correct-as-designed, not an oversight).
        assertEq(usdc.balanceOf(lender), lenderBalBefore + FACE_VALUE);
    }

    function test_LatePayment_HandleDefaultStillCallableButHarmlessOnceArrived() public {
        // Edge case: payment arrives late, but the deal also independently
        // becomes eligible for handleDefault() in the same window. Confirm
        // handleDefault() correctly refuses once payment has landed — this
        // is the PaymentAlreadyReceived guard, exercised specifically in
        // the "late payment" context rather than the immediate-default
        // context already covered elsewhere.
        _fundDeal();
        vm.warp(maturityDate + 3 days);

        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        vm.expectRevert(EscrowSettlement.PaymentAlreadyReceived.selector);
        escrow.handleDefault();
    }

    // ---------------------------------------------------------------
    // Tech doc Section 6.2, item 4: boundary conditions on maturity-date
    // comparison logic, specifically for handleDefault()'s
    // `block.timestamp <= deal.maturityDate()` check. Previously only
    // tested far from the boundary (immediately at deal creation); the
    // exact transition point was never confirmed.
    // ---------------------------------------------------------------

    function test_RevertWhen_HandleDefaultExactlyAtMaturity() public {
        // At block.timestamp == maturityDate, the check `<=` means this
        // is NOT yet a default — maturity has not been exceeded, only
        // reached. Must still revert.
        _fundDeal();
        vm.warp(maturityDate);

        vm.expectRevert(EscrowSettlement.MaturityNotYetReached.selector);
        escrow.handleDefault();
    }

    function test_HandleDefaultSucceedsOneSecondAfterMaturity() public {
        // The exact transition point: maturityDate + 1 is the first
        // timestamp at which handleDefault() should succeed.
        _fundDeal();
        vm.warp(maturityDate + 1);

        // Should not revert.
        escrow.handleDefault();
    }

    // ---------------------------------------------------------------
    // Distribution — the waterfall, including the shortfall case
    // ---------------------------------------------------------------

    function test_RevertWhen_DistributeBeforePaymentReceived() public {
        _fundDeal();
        vm.expectRevert(EscrowSettlement.PaymentNotYetReceived.selector);
        escrow.distribute();
    }

    function test_DistributeFullPayment_LenderGetsFaceValue_BorrowerGetsZero() public {
        _fundDeal();
        vm.warp(maturityDate);
        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        uint256 lenderBalBefore = usdc.balanceOf(lender);
        uint256 borrowerBalBefore = usdc.balanceOf(borrower);

        escrow.distribute();

        assertEq(usdc.balanceOf(lender), lenderBalBefore + FACE_VALUE);
        assertEq(usdc.balanceOf(borrower), borrowerBalBefore);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_DistributeShortfall_LenderAbsorbsEntireShortfall() public {
        _fundDeal();
        vm.warp(maturityDate);

        uint256 shortfallAmount = FACE_VALUE - 25_000e6;

        vm.prank(anchor);
        usdc.approve(address(escrow), shortfallAmount);
        vm.prank(anchor);
        escrow.receivePayment(shortfallAmount);

        uint256 lenderBalBefore = usdc.balanceOf(lender);
        uint256 borrowerBalBefore = usdc.balanceOf(borrower);

        escrow.distribute();

        assertEq(usdc.balanceOf(lender), lenderBalBefore + shortfallAmount);
        assertEq(usdc.balanceOf(borrower), borrowerBalBefore);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_DistributeExcess_BorrowerGetsResidual() public {
        _fundDeal();
        vm.warp(maturityDate);

        uint256 excessAmount = FACE_VALUE + 10_000e6;

        vm.prank(anchor);
        usdc.approve(address(escrow), excessAmount);
        vm.prank(anchor);
        escrow.receivePayment(excessAmount);

        uint256 lenderBalBefore = usdc.balanceOf(lender);
        uint256 borrowerBalBefore = usdc.balanceOf(borrower);

        escrow.distribute();

        assertEq(usdc.balanceOf(lender), lenderBalBefore + FACE_VALUE);
        assertEq(usdc.balanceOf(borrower), borrowerBalBefore + 10_000e6);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_RevertWhen_DistributeCalledTwice() public {
        _fundDeal();
        vm.warp(maturityDate);
        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        escrow.distribute();

        vm.expectRevert(EscrowSettlement.AlreadyDistributed.selector);
        escrow.distribute();
    }

    function test_DistributeCallableByAnyone() public {
        _fundDeal();
        vm.warp(maturityDate);
        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        vm.prank(randomCaller);
        escrow.distribute();

        assertTrue(escrow.distributed());
    }

    // ---------------------------------------------------------------
    // Default flagging
    // ---------------------------------------------------------------

    function test_RevertWhen_HandleDefaultBeforeMaturity() public {
        _fundDeal();
        vm.expectRevert(EscrowSettlement.MaturityNotYetReached.selector);
        escrow.handleDefault();
    }

    function test_HandleDefaultDoesNotMoveFunds() public {
        _fundDeal();
        vm.warp(maturityDate + 1);

        uint256 escrowBalBefore = usdc.balanceOf(address(escrow));
        escrow.handleDefault();
        assertEq(usdc.balanceOf(address(escrow)), escrowBalBefore);
    }

    function test_RevertWhen_HandleDefaultAfterPaymentReceived() public {
        _fundDeal();
        vm.warp(maturityDate);
        vm.prank(anchor);
        usdc.approve(address(escrow), FACE_VALUE);
        vm.prank(anchor);
        escrow.receivePayment(FACE_VALUE);

        vm.warp(maturityDate + 1);
        vm.expectRevert(EscrowSettlement.PaymentAlreadyReceived.selector);
        escrow.handleDefault();
    }
}
