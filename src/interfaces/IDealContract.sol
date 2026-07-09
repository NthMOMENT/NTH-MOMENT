// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IDealContract
/// @notice Minimal interface the Escrow Settlement contract needs from a
///         Deal Contract: read-only access to immutable deal terms, the
///         signature-completion check, and the one callback Escrow is
///         permitted to invoke (markActive). Deliberately excludes the
///         signAsLender/signAsAnchor/signAsBorrower/cancelDeal functions —
///         the Escrow Contract has no business calling any of those, and
///         this interface makes that compile-time impossible, not just a
///         convention.
interface IDealContract {
    function borrower() external view returns (address);
    function anchor() external view returns (address);
    function lender() external view returns (address);
    function faceValue() external view returns (uint256);
    function rate() external view returns (uint256);
    function maturityDate() external view returns (uint256);
    function allSigned() external view returns (bool);
    function markActive() external;
}
