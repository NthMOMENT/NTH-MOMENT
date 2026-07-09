# Nth Moment Protocol

**On-chain reverse factoring. Where buyer's obligation matters and not the seller's promise.**

---

## The problem in one paragraph

A supplier ships goods to a large corporate buyer. The buyer says "I'll pay in 90 days." The supplier needs cash today. Banks charge high rates and take weeks to process. Traditional supply chain finance (SCF) platforms like Taulia and Demica solve this, with a catch. The solution exists only for large suppliers with existing bank relationships, behind closed software that costs millions to license, with a bank sitting in the middle holding everyone's money.

Nth Moment removes the bank in the middle. The same SCF structure, reverse factoring, runs on a smart contract that no single entity controls.

---

## How reverse factoring actually works (for the 12th grader)

Imagine you sold $500,000 worth of goods to a large corporate buyer. They will pay you in 90 days. You need money now to pay your workers.

A Lender says: *"I'll give you $482,500 today. In 90 days, the buyer pays me the full $500,000 directly. My profit is the $17,500 difference."*

That's it. The Lender is betting on **the buyer paying** not on you being creditworthy. The buyer is a rated, reliable corporate. The risk is the buyer's payment obligation, not your financial health.

Nth Moment puts this entire structure on a blockchain. The contract holds the agreement. The contract moves the money. No bank account in the middle. No human can redirect the funds.

---

## Why the buyer (Anchor) is the credit risk and not the seller (Borrower)

This is the core underwriting insight. In traditional lending, you assess the borrower. In reverse factoring, you assess the **buyer**.

| Traditional Loan | Nth Moment |
|---|---|
| Risk = Can the Borrower repay? | Risk = Will the Anchor (buyer) pay its invoice? |
| Collateral = Borrower's assets | Collateral = Anchor's payment obligation |
| Hard to verify | Verifiable, Anchor is a rated corporate |

The Anchor must have a minimum **BBB- credit rating** (S&P / Moody's / Fitch). No rating, no deal. It's a hard gate and not a guideline.

The Borrower must pass a **40% concentration check**: no more than 40% of their rolling 12 month revenue can come from the Anchor they are discounting against. Verified via three independent sources: sales ledger, bank statements, and tax filings. All three must reconcile. Self attestation is not accepted.

---

## The three parties in every deal

```
LENDER
  Provides capital. Earns yield via discount.
  Bears repayment risk if Anchor doesn't pay.
        |
        v
  [SMART CONTRACT — Escrow + Deal]
  No human controls funds inside here.
        ^
        |
BORROWER                          ANCHOR
  Holds the receivable.           The buyer. Owes the payment.
  Gets early liquidity.           Pays face value at maturity.
  Already delivered goods.        This is where the credit risk lives.
```

---

## The money flow: step by step

**Step 1: Underwriting (off-chain)**
Lender verifies Anchor rating (BBB- minimum) and Borrower concentration (40% cap). Document check: ledger + bank statements + tax filings. Both gates must pass before any on-chain action.

**Step 2: Signing (on-chain)**
All three parties sign using KYC verified wallets. Strict order enforced by the contract:
1. Lender signs first: commits to the terms
2. Anchor signs second: acknowledges the payment obligation
3. Borrower signs last: assigns the receivable

The SHA-256 hash of the full legal agreement is stored on-chain. Each wallet signature is cryptographic proof that party agreed to that exact document.

**Step 3: Disbursement (on-chain, atomic)**
Lender calls `fundDeal()`. One transaction:
- `fundedAmount` (face value minus discount) → Borrower immediately
- `protocolFee` → Treasury immediately
- Contract holds nothing after this step

**Step 4: Settlement (on-chain)**
At maturity, Anchor pays face value into the Escrow Contract directly.

**Step 5: Distribution (on-chain, waterfall)**
- Lender receives first: up to full face value (principal + yield[negotiable]).
- Borrower receives any excess beyond face value. 
- Shortfall (e.g. demurrage deduction): Lender absorbs entirely. Borrower receives zero.

**Escrow Contract balance after every completed deal: exactly zero.**

---

## Why non-custodial matters

In the US, holding or transmitting money "on behalf of customers" requires a Money Transmitter License, state by state, $30,000–$525,000+ per state, 49 states require it.

Nth Moment avoids this: **the protocol never holds customer funds in a company controlled account.** Money moves from wallet to smart contract to wallet, by code alone. No human has signing authority over deal funds. No company bank account sits in the payment path.

This is not a workaround. It is the central architectural constraint. Every design decision in the codebase flows from it.

---
## Legal / Entity

Nth Moment is a DUNS registered entity. DUNS:772435720 .

## The contracts

### `IdentityRegistry.sol`
KYC whitelist. Bridges a crypto wallet to a verified legal identity. The Deal Contract checks this before accepting any signature. Holds zero funds.

**Live on Arbitrum One:** `0x8a6A11B9d24B34EE8bcbf1b3F870e82f04B2C34a`

### `DealContract.sol`
Encodes deal terms and manages the tri-party signature flow. Enforces signing order. Expires after 7 calendar days if unsigned and unfunded. Once ACTIVE, terms are immutable — no admin can alter them.

### `EscrowSettlement.sol`
The only contract that touches money. Pass through router at disbursement. Waterfall distributor at settlement. Has no admin override, no pause function, no upgrade proxy, permanently.

---

## Security

| Check | Result |
|---|---|
| Slither 101 detectors, source level | 1 real finding fixed (missing interface inheritance). 3 timestamp warnings documented non issues (day granularity deadlines, no exploitable window). |
| Mythril symbolic execution, bytecode | Same timestamp findings confirmed. SWC-123 on external calls expected, intended revert propagation behavior. |
| Test suite | 76 tests, 0 failures. Covers signing order, KYC gating, waterfall (full / shortfall / excess), early payment, late payment, maturity boundary conditions. |
| Reentrancy | ReentrancyGuard on all fund-moving functions + checks effects interactions enforced throughout. |

---

## Getting started

```bash
# Prerequisites: Foundry (https://getfoundry.sh)
git clone https://github.com/NthMOMENT/NTH-MOMENT.git
cd NTH-MOMENT
forge install OpenZeppelin/openzeppelin-contracts@v5.6.1
forge build
forge test -vv
```

Expected: `76 tests passed, 0 failed`

---

## Current status

```
[x] DUNS Registered        772435720
[x] Identity Registry      deployed + verified, Arbitrum One mainnet
[x] Deal Contract          built, tested
[x] Escrow Settlement      built, tested
[x] Security pass          Slither + Mythril complete
[x] MIT License            open source
[ ] Tri-party legal template
[ ] KYC provider integration
[ ] First pilot deal
```

**Pre-pilot. Infrastructure built and verified. Not yet processing real deals.**

---

## License

MIT [LICENSE](./LICENSE)

---

*Built by a credit professional with 10 years of Indian banking experience in asset, credit, and risk underwriting. The underwriting judgment is the product. The smart contracts are the rails.*
