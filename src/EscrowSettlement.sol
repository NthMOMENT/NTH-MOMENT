// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IDealContract} from "./interfaces/IDealContract.sol";

/// @title EscrowSettlement
/// @notice Fund-holding and distribution logic for one Nth Moment deal.
///         This is the contract that must most rigorously satisfy the
///         non-custodial test (NTH_MOMENT_TECH_STACK.md Section 1 / 4.3)
///         — it is where real money sits, even if only briefly.
/// @dev V1 deployment model: manual, one EscrowSettlement instance per
///      deal, deployed by the founder, address then passed into the
///      corresponding DealContract's constructor.
///
///      CASH FLOW MODEL (locked through direct discussion with founder —
///      this is real invoice-discounting economics, not a simplification):
///
///      1. DISBURSEMENT (fundDeal, Lender-only, once, after all 3 parties
///         have signed the Deal Contract):
///         - fundedAmount = faceValue - discount, discount = faceValue * rate / 10000.
///           This is the Lender's actual principal outlay — reverse
///           factoring/invoice discounting means the Lender funds the
///           receivable AT A DISCOUNT, not at face value.
///         - protocolFee = faceValue * feeRateBps / 10000. Per founder's
///           explicit instruction: the Lender pays this fee, not the
///           Borrower or Anchor — "lenders cannot have a free ride." The
///           fee is collected at DISBURSEMENT (not settlement) specifically
///           because the amount the Anchor eventually pays at maturity is
///           NOT guaranteed to equal faceValue (demurrage / delivery
///           penalties can reduce it) — collecting the fee from a fixed,
///           certain amount at disbursement avoids making Treasury's
///           revenue hostage to a later commercial dispute the contract
///           cannot adjudicate.
///         - Lender approves (fundedAmount + protocolFee) on the
///           settlement token, then calls fundDeal(), which pulls via
///           transferFrom() and immediately forwards: fundedAmount to the
///           Borrower (their early liquidity — this IS the product), and
///           protocolFee to the Treasury. This contract holds nothing
///           after fundDeal() completes — it's a pass-through router at
///           this stage, not a holding account.
///         - Calls back into DealContract.markActive() once complete.
///
///      2. SETTLEMENT (receivePayment + distribute, at/after maturity):
///         - Anchor pays actualAmountReceived via receivePayment().
///           This may be LESS than faceValue (demurrage/delivery
///           penalties withheld by the Anchor) — the contract has no way
///           to validate whether a shortfall is legitimate; that is an
///           off-chain commercial/legal question (see business doc
///           Section 6.5, "Anchor default scenario," and Section 8 item 2).
///         - distribute() then pays out via a WATERFALL (founder's
///           explicit choice over flat pro-rata sharing, matching
///           standard structured-finance priority-of-payments practice):
///             Tier 1 — Lender's principal (fundedAmount), paid first.
///             Tier 2 — Lender's yield (discount), paid next, up to the
///                      point the Lender has received fundedAmount + discount
///                      (i.e. the full faceValue) in total.
///             Tier 3 — Borrower's residual: any amount actually received
///                      beyond faceValue (uncommon, but possible).
///           If actualAmountReceived falls short of faceValue, the Lender
///           absorbs the entire shortfall — Borrower receives zero residual
///           in any shortfall scenario. This was a deliberate founder
///           decision: the Lender bears repayment risk because they
///           independently chose to fund based on the Anchor's credit
///           rating; this mirrors the Lender-pays-the-protocol-fee logic.
///
///      Custody boundary compliance: no admin override, no pause function,
///      no upgrade proxy — all forbidden by tech doc Section 4.3's hard
///      rules for this specific contract. Once deployed, behavior is fixed.
contract EscrowSettlement is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The Deal Contract this escrow serves. One escrow per deal.
    IDealContract public immutable deal;

    /// @notice Settlement stablecoin (USDC for V1 US-rail deals).
    IERC20 public immutable settlementToken;

    /// @notice Protocol treasury address. Receives the protocol fee at
    ///         disbursement. Not a founder personal wallet — see business
    ///         doc Section 6.2 custody rules; this is a fixed, disclosed
    ///         protocol-owned address, not a discretionary destination.
    address public immutable treasury;

    /// @notice Protocol fee rate, in basis points, applied to faceValue
    ///         and collected from the Lender at disbursement.
    uint256 public immutable feeRateBps;

    bool public funded;
    bool public paymentReceived;
    bool public distributed;

    uint256 public fundedAmount; // principal actually disbursed to Borrower (faceValue - discount)
    uint256 public protocolFeeCollected;
    uint256 public actualAmountReceived; // what the Anchor actually paid at settlement

    event Funded(address indexed lender, address indexed borrower, uint256 fundedAmount, uint256 protocolFee);
    event PaymentReceived(address indexed anchor, uint256 amount);
    event Distributed(uint256 toLender, uint256 toBorrower);
    event DefaultFlagged(uint256 timestamp);

    error NotLender();
    error AlreadyFunded();
    error DealTermsNotSigned();
    error NotYetFunded();
    error AlreadyPaymentReceived();
    error AlreadyDistributed();
    error PaymentNotYetReceived();
    error MaturityNotYetReached();
    error PaymentAlreadyReceived();
    error ZeroAddress();
    error FeeRateTooHigh();

    /// @param _deal Address of the corresponding Deal Contract. Terms
    ///        (faceValue, rate, parties, signature completion) are read
    ///        from it directly — never duplicated or re-entered here.
    /// @param _settlementToken Address of the settlement stablecoin (USDC
    ///        for V1 US-rail deals; see tech doc Section 3).
    /// @param _treasury Protocol treasury address.
    /// @param _feeRateBps Combined protocol fee rate in basis points,
    ///        collected from the Lender at disbursement. Sanity-capped at
    ///        500 bps (5%) — business doc's stated range is 75-175bps
    ///        combined (25-75 underwriting + 50-100 origination); 500bps
    ///        is a deliberately generous upper sanity bound, not the
    ///        expected operating rate.
    constructor(address _deal, address _settlementToken, address _treasury, uint256 _feeRateBps) {
        if (_deal == address(0) || _settlementToken == address(0) || _treasury == address(0)) {
            revert ZeroAddress();
        }
        if (_feeRateBps > 500) revert FeeRateTooHigh();

        deal = IDealContract(_deal);
        settlementToken = IERC20(_settlementToken);
        treasury = _treasury;
        feeRateBps = _feeRateBps;
    }

    /// @notice Lender disburses the deal. Pulls (fundedAmount + protocolFee)
    ///         from the Lender via transferFrom(), forwards fundedAmount to
    ///         the Borrower and protocolFee to the Treasury, then calls
    ///         back into the Deal Contract to mark it ACTIVE.
    /// @dev Requires the Lender to have called
    ///      settlementToken.approve(address(this), fundedAmount + protocolFee)
    ///      beforehand. Callable exactly once per deal.
    function fundDeal() external nonReentrant {
        if (funded) revert AlreadyFunded();
        if (msg.sender != deal.lender()) revert NotLender();
        if (!deal.allSigned()) revert DealTermsNotSigned();

        uint256 faceValue = deal.faceValue();
        uint256 rate = deal.rate();

        uint256 discount = (faceValue * rate) / 10_000;
        uint256 amountToBorrower = faceValue - discount;
        uint256 fee = (faceValue * feeRateBps) / 10_000;

        funded = true;
        fundedAmount = amountToBorrower;
        protocolFeeCollected = fee;

        // Pull the combined total from the Lender in one transferFrom().
        settlementToken.safeTransferFrom(msg.sender, address(this), amountToBorrower + fee);

        // Forward immediately — this contract holds nothing after this point.
        settlementToken.safeTransfer(deal.borrower(), amountToBorrower);
        settlementToken.safeTransfer(treasury, fee);

        emit Funded(msg.sender, deal.borrower(), amountToBorrower, fee);

        // Notify the Deal Contract so its status reflects reality.
        deal.markActive();
    }

    /// @notice Anchor's settlement payment at/near maturity. Permissionless
    ///         by design (tech doc Section 4.3) — contract logic alone
    ///         determines correct distribution regardless of who triggers
    ///         this call, removing human discretion from the receipt step.
    /// @dev Requires the caller (typically the Anchor, but not enforced)
    ///      to have approved `amount` on the settlement token beforehand.
    ///      May receive less than faceValue — see contract-level docs on
    ///      the waterfall distribution that follows.
    /// @param amount The amount being paid in settlement of this deal.
    function receivePayment(uint256 amount) external nonReentrant {
        if (!funded) revert NotYetFunded();
        if (paymentReceived) revert AlreadyPaymentReceived();

        paymentReceived = true;
        actualAmountReceived = amount;

        settlementToken.safeTransferFrom(msg.sender, address(this), amount);

        emit PaymentReceived(msg.sender, amount);
    }

    /// @notice Distributes the Anchor's settlement payment via the locked
    ///         waterfall: Lender's principal first, then Lender's yield
    ///         (up to full faceValue total to Lender), then any residual
    ///         beyond faceValue to the Borrower. Permissionless.
    function distribute() external nonReentrant {
        if (!paymentReceived) revert PaymentNotYetReceived();
        if (distributed) revert AlreadyDistributed();

        distributed = true;

        uint256 faceValue = deal.faceValue();
        uint256 received = actualAmountReceived;

        // Waterfall: Lender is owed up to faceValue (principal + yield)
        // before the Borrower sees any residual.
        uint256 toLender = received > faceValue ? faceValue : received;
        uint256 toBorrower = received > faceValue ? received - faceValue : 0;

        if (toLender > 0) {
            settlementToken.safeTransfer(deal.lender(), toLender);
        }
        if (toBorrower > 0) {
            settlementToken.safeTransfer(deal.borrower(), toBorrower);
        }

        emit Distributed(toLender, toBorrower);
    }

    /// @notice Flags the deal for off-chain legal recourse if maturity has
    ///         passed without payment. Does NOT move funds or alter any
    ///         balance — there is no automatic on-chain recovery
    ///         mechanism. Recovery, if needed, happens through the
    ///         governing-law election and tri-party agreement enforceability
    ///         (business doc Section 6.5, Section 8 item 2 — acknowledged
    ///         open risk, not yet fully designed beyond "the legal
    ///         agreement is the recourse path").
    function handleDefault() external {
        if (block.timestamp <= deal.maturityDate()) revert MaturityNotYetReached();
        if (paymentReceived) revert PaymentAlreadyReceived();

        emit DefaultFlagged(block.timestamp);
    }
}
