// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title IdentityRegistry
/// @notice KYC-gated wallet whitelist. Bridges a pseudonymous wallet signature
///         into a named legal entity's binding electronic signature (see
///         NTH_MOMENT_BUSINESS.md Section 6.4). The Deal Contract calls
///         `isVerified()` before accepting any party's signature.
/// @dev Custody boundary: this contract NEVER touches deal funds. The owner
///      role here is identity-attestation only — it writes a KYC result
///      on-chain after an off-chain KYC provider (Persona/Sumsub/equivalent,
///      provider TBD — see tech doc Section 8.1) completes verification.
///      This is a deliberately narrow privileged role, structurally separate
///      from the Escrow Settlement contract's fund-distribution logic, which
///      has no admin/owner function at all.
///
///      V1 SCOPE: verify-only. No revocation function exists yet — a wallet,
///      once registered, stays verified for the lifetime of this contract
///      deployment. Revocation (fraud flag, sanctions hit, KYC expiry) is an
///      explicit known gap, deferred to a future version. Do not assume
///      revocation exists when building the Deal Contract on top of this.
contract IdentityRegistry is Ownable {
    /// @notice Emitted when a wallet is successfully registered as KYC-verified.
    /// @param wallet The address being registered.
    /// @param kycHash Off-chain reference hash (e.g. hash of the KYC provider's
    ///        verification record/session ID). This is NOT the person's PII —
    ///        it's a pointer the founder can use to look up the underlying
    ///        verification record off-chain if ever needed (audit, dispute).
    event WalletRegistered(address indexed wallet, bytes32 kycHash);

    /// @notice kycHash recorded per wallet. Zero value = never registered.
    mapping(address => bytes32) private _kycHash;

    /// @notice Whether a wallet has completed KYC registration.
    mapping(address => bool) private _verified;

    /// @dev Thrown when attempting to register a wallet that is already verified.
    error AlreadyRegistered(address wallet);

    /// @dev Thrown when attempting to register the zero address.
    error ZeroAddress();

    /// @dev Thrown when kycHash is left as the zero value — registering with
    ///      an empty hash would make the on-chain record meaningless (no way
    ///      to tie it back to an off-chain verification record).
    error EmptyKycHash();

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Registers a wallet as KYC-verified. Owner-gated.
    /// @dev Called by the founder (or, later, an automated off-chain KYC
    ///      webhook relay controlled by the founder's key) after the off-chain
    ///      KYC provider confirms identity. This function only ever writes
    ///      identity status — it has no knowledge of, or interaction with,
    ///      deal funds, escrow, or any token.
    /// @param wallet The wallet address to register.
    /// @param kycHash Reference hash pointing to the off-chain KYC verification
    ///        record. Must be non-zero.
    function registerWallet(address wallet, bytes32 kycHash) external onlyOwner {
        if (wallet == address(0)) revert ZeroAddress();
        if (kycHash == bytes32(0)) revert EmptyKycHash();
        if (_verified[wallet]) revert AlreadyRegistered(wallet);

        _verified[wallet] = true;
        _kycHash[wallet] = kycHash;

        emit WalletRegistered(wallet, kycHash);
    }

    /// @notice Returns whether a wallet has completed KYC registration.
    /// @dev Called by the Deal Contract to gate signAsBorrower/signAsAnchor/
    ///      signAsLender. Public, unrestricted read — verification status is
    ///      not sensitive in itself (it reveals nothing about identity, only
    ///      a boolean), and the Deal Contract needs to call this permissionlessly.
    /// @param wallet The wallet address to check.
    /// @return True if the wallet is KYC-verified.
    function isVerified(address wallet) external view returns (bool) {
        return _verified[wallet];
    }

    /// @notice Returns the KYC reference hash recorded for a wallet.
    /// @dev Returns bytes32(0) if the wallet was never registered. Useful for
    ///      off-chain audit/dispute resolution — ties an on-chain registration
    ///      event back to the specific KYC provider verification record.
    /// @param wallet The wallet address to query.
    /// @return The kycHash recorded at registration time.
    function getKycHash(address wallet) external view returns (bytes32) {
        return _kycHash[wallet];
    }
}
