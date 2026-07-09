// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";

/// @title DealContract
/// @notice Encodes one tri-party reverse-factoring agreement (Borrower /
///         Anchor / Lender) and its KYC-gated signature flow. On-chain
///         representation of the legal agreement described in
///         NTH_MOMENT_BUSINESS.md Section 6.5.
/// @dev V1 deployment model: manual, one DealContract instance per deal,
///      deployed directly by the founder (no factory). See tech doc
///      Section 4.2.
///
///      Custody boundary (business doc Section 6.2): this contract NEVER
///      holds deal funds and never moves them. All fund movement —
///      Lender's disbursement to the Borrower, Anchor's settlement
///      payment, the waterfall distribution — happens entirely on the
///      separately-deployed Escrow Settlement contract (escrowAddress).
///      This contract's only job is coordinating the 3-party signature
///      flow and recording immutable deal terms. Once all signatures are
///      complete, the Escrow Contract reads this contract's terms
///      (faceValue, rate, parties) directly and, upon successfully
///      processing the Lender's disbursement, calls back into
///      `markActive()` here — the only state-mutating call this contract
///      accepts from an external contract, and it is restricted to
///      `escrowAddress` alone.
///
///      Signing order (locked, founder's explicit underwriting logic):
///      Lender signs first (sanctions the loan) -> Anchor signs second
///      (the credit risk in the deal must agree to terms before the
///      Borrower is brought in) -> Borrower signs last. Out-of-order
///      signature attempts revert.
///
///      Funding timing: the Lender's capital is NOT locked at sign-time.
///      Funding (on the Escrow Contract) is only possible after all three
///      signatures are in place, minimizing the Lender's capital lockup
///      window.
///
///      Expiry: if all three signatures + funding are not complete within
///      7 calendar days of deal creation, anyone may call cancelDeal().
///      This is a SIMPLE calendar-day window (7 * 1 days), not a true
///      banking "working day" calculation — Solidity has no native
///      calendar/holiday awareness, and building one was judged
///      unnecessary complexity for 1-3 manually-run V1 pilot deals. No
///      protocol fee is charged on cancellation; the only cost is the
///      normal network gas paid by whoever calls cancelDeal().
contract DealContract {
    enum Status {
        PENDING, // created, signatures in progress
        ACTIVE, // all 3 signed and funded
        CANCELLED // expired without completing signing + funding
    }

    /// @notice KYC registry used to gate every signature.
    IIdentityRegistry public immutable identityRegistry;

    address public immutable borrower;
    address public immutable anchor;
    address public immutable lender;

    uint256 public immutable faceValue;
    uint256 public immutable rate; // discount rate, basis points
    uint256 public immutable maturityDate; // unix timestamp
    bytes32 public immutable docHash; // SHA-256 hash of the tri-party legal agreement
    address public immutable escrowAddress; // pre-deployed, non-custodial Escrow Settlement contract

    uint256 public immutable createdAt;
    uint256 public constant SIGNING_WINDOW = 7 days;

    bool public lenderSigned;
    bool public anchorSigned;
    bool public borrowerSigned;

    Status public status;

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
    event LenderSigned(address indexed lender);
    event AnchorSigned(address indexed anchor);
    event BorrowerSigned(address indexed borrower);
    event DealFunded(address indexed lender, address indexed escrowAddress, uint256 faceValue);
    event DealCancelled(address indexed caller, uint256 timestamp);

    error NotVerified(address wallet);
    error OnlyLender();
    error OnlyEscrow();
    error OnlyAnchor();
    error OnlyBorrower();
    error WrongSigningOrder();
    error AlreadySigned();
    error NotAllSigned();
    error DealNotPending();
    error SigningWindowNotExpired();
    error MaturityMustBeFuture();
    error ZeroAddress();
    error ZeroFaceValue();
    error EmptyDocHash();

    /// @param _identityRegistry Address of the deployed Identity Registry.
    /// @param _borrower Borrower (Seller) wallet — must be KYC-verified before signing.
    /// @param _anchor Anchor (Buyer) wallet — must be KYC-verified before signing.
    /// @param _lender Lender (Funder) wallet — must be KYC-verified before signing.
    /// @param _faceValue Face value of the receivable, in the settlement stablecoin's smallest unit.
    /// @param _rate Discount rate, in basis points.
    /// @param _maturityDate Unix timestamp the Anchor's payment is due. Must be in the future.
    /// @param _docHash SHA-256 hash of the full tri-party legal agreement document.
    /// @param _escrowAddress Address of the pre-deployed, non-custodial Escrow Settlement
    ///        contract for this deal. This contract never holds funds itself.
    constructor(
        address _identityRegistry,
        address _borrower,
        address _anchor,
        address _lender,
        uint256 _faceValue,
        uint256 _rate,
        uint256 _maturityDate,
        bytes32 _docHash,
        address _escrowAddress
    ) {
        if (
            _identityRegistry == address(0) ||
            _borrower == address(0) ||
            _anchor == address(0) ||
            _lender == address(0) ||
            _escrowAddress == address(0)
        ) revert ZeroAddress();
        if (_faceValue == 0) revert ZeroFaceValue();
        if (_docHash == bytes32(0)) revert EmptyDocHash();
        if (_maturityDate <= block.timestamp) revert MaturityMustBeFuture();

        identityRegistry = IIdentityRegistry(_identityRegistry);
        borrower = _borrower;
        anchor = _anchor;
        lender = _lender;
        faceValue = _faceValue;
        rate = _rate;
        maturityDate = _maturityDate;
        docHash = _docHash;
        escrowAddress = _escrowAddress;

        createdAt = block.timestamp;
        status = Status.PENDING;

        emit DealCreated(_borrower, _anchor, _lender, _faceValue, _rate, _maturityDate, _docHash, _escrowAddress);
    }

    /// @notice Lender signs the tri-party agreement. Must be called first.
    /// @dev Per business doc Section 6.3/6.4: this signature is the Lender's
    ///      own, independent credit decision and acceptance of the deal
    ///      terms (including Nth Moment's off-chain B+ rating and 40%
    ///      concentration checks) — there is deliberately no separate
    ///      on-chain "underwriting approved" flag. This signature alone is
    ///      the attestation.
    function signAsLender() external {
        if (status != Status.PENDING) revert DealNotPending();
        if (msg.sender != lender) revert OnlyLender();
        if (!identityRegistry.isVerified(msg.sender)) revert NotVerified(msg.sender);
        if (lenderSigned) revert AlreadySigned();

        lenderSigned = true;
        emit LenderSigned(msg.sender);
    }

    /// @notice Anchor signs the tri-party agreement. Must be called after the Lender.
    function signAsAnchor() external {
        if (status != Status.PENDING) revert DealNotPending();
        if (msg.sender != anchor) revert OnlyAnchor();
        if (!identityRegistry.isVerified(msg.sender)) revert NotVerified(msg.sender);
        if (!lenderSigned) revert WrongSigningOrder();
        if (anchorSigned) revert AlreadySigned();

        anchorSigned = true;
        emit AnchorSigned(msg.sender);
    }

    /// @notice Borrower signs the tri-party agreement. Must be called after the Anchor.
    function signAsBorrower() external {
        if (status != Status.PENDING) revert DealNotPending();
        if (msg.sender != borrower) revert OnlyBorrower();
        if (!identityRegistry.isVerified(msg.sender)) revert NotVerified(msg.sender);
        if (!anchorSigned) revert WrongSigningOrder();
        if (borrowerSigned) revert AlreadySigned();

        borrowerSigned = true;
        emit BorrowerSigned(msg.sender);
    }

    /// @notice Returns true once all three parties have signed, in order.
    function allSigned() public view returns (bool) {
        return lenderSigned && anchorSigned && borrowerSigned;
    }

    /// @notice Callback invoked by the Escrow Settlement contract once it
    ///         has successfully pulled and forwarded the Lender's
    ///         disbursement (principal to Borrower, protocol fee to
    ///         Treasury). Flips this deal's status to ACTIVE.
    /// @dev Restricted to `escrowAddress` alone — no other address, not
    ///      even the founder, can call this. This is the one external
    ///      call this contract accepts, and it only ever sets `status`;
    ///      it cannot move funds, alter terms, or touch the Identity
    ///      Registry. Reverts if not all three parties have signed, as a
    ///      defense-in-depth check even though the Escrow Contract is
    ///      expected to enforce this on its own side too.
    function markActive() external {
        if (msg.sender != escrowAddress) revert OnlyEscrow();
        if (status != Status.PENDING) revert DealNotPending();
        if (!allSigned()) revert NotAllSigned();

        status = Status.ACTIVE;
        emit DealFunded(lender, escrowAddress, faceValue);
    }

    /// @notice Cancels a deal that failed to complete signing + funding
    ///         within the 7-calendar-day signing window. Callable by anyone.
    /// @dev No protocol fee is charged. The only cost incurred is the
    ///      normal network gas paid by whoever calls this function.
    function cancelDeal() external {
        if (status != Status.PENDING) revert DealNotPending();
        if (block.timestamp < createdAt + SIGNING_WINDOW) revert SigningWindowNotExpired();

        status = Status.CANCELLED;
        emit DealCancelled(msg.sender, block.timestamp);
    }
}
