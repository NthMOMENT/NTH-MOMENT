// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IIdentityRegistry
/// @notice Minimal read-only interface the Deal Contract needs from the
///         Identity Registry. Deliberately excludes registerWallet() and
///         owner-only functions — the Deal Contract should never be able
///         to call anything except the permissionless isVerified() read.
///         This is a small defense-in-depth choice: even if DealContract
///         had a bug, it has no compiled ability to call registry-mutating
///         functions, because this interface doesn't expose them.
interface IIdentityRegistry {
    /// @notice Returns whether a wallet has completed KYC registration.
    function isVerified(address wallet) external view returns (bool);
}
