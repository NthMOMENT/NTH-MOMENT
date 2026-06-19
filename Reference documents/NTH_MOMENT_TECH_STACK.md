# Nth Moment — Technical Reference Document

**Status:** Pre-build, architecture locked. No code written yet as of this document's creation.
**Last updated:** 19 June 2026
**Companion document:** NTH_MOMENT_BUSINESS.md (business context, risk controls, regulatory posture — read first; this document assumes that context)

---

## 1. Architectural philosophy — read this first

Every technical decision below is downstream of one constraint: **the protocol must be genuinely non-custodial**, because the founder is building with zero capital and cannot afford money-transmitter licensing (state-by-state US costs run $30K-$525K+ per state). See NTH_MOMENT_BUSINESS.md Section 6 for the full regulatory reasoning.

**The canonical test applied to every contract function, every feature, every operational decision:** "Does a human or a controllable wallet ever sit between the payer and the payee?" If yes, redesign. No exceptions, including emergencies, including "just to help."

This single constraint shapes the smart contract design (no admin withdraw functions, no pause on fund-holding logic, no upgrade proxy on the escrow contract), the fee mechanism (auto-deducted by code, never invoiced), and the founder's own operational conduct (never personally touches deal funds).

---

## 2. Chain selection

### Decision: Base or Arbitrum (Ethereum L2) for V1
**Not** XDC Network, despite XDC being purpose-built for trade finance (delegated PoS, near-zero fees, built-in compliance layers, ISO 20022/MLETR interoperability, already used for tokenizing trade invoices and private credit).

**Reasoning:** zero-capital, solo/small-team build cannot afford to fight two uphill battles simultaneously (product-market fit AND new-chain adoption). V1 priorities, in order: cheapest possible developer hiring/tooling pool, deepest USDC/EURC liquidity, most audited smart contract libraries (OpenZeppelin), most legal/audit precedent. Ethereum L2s win on all four for a zero-capital build, even though XDC is architecturally more elegant for the specific use case.

**Comparison summary (researched January-June 2026 timeframe):**

| Factor | Ethereum + L2 | XDC Network | Plume |
|---|---|---|---|
| USDC/EURC liquidity | Deepest, native | Bridged, growing | Bridged, modest |
| Trade finance / MLETR fit | Generic, none built-in | Purpose-built | RWA-general, not trade-specific |
| Settlement gas cost | Low on L2 | Near-zero, dPoS | Low, EVM-compatible |
| Built-in compliance layer | Build it yourself | Native to protocol | Native, KYC/AML built-in |
| Audit firms / legal precedent | Most mature | Newer, less tested | Newer, less tested |
| Build cost on zero capital | Free tooling, huge community | Smaller dev community | Smaller dev community |

**Migration path:** revisit XDC (or multi-chain deployment) once deal volume and/or raised capital justify it. This is explicitly a V1-only decision, not permanent.

---

## 3. Currency / stablecoin rails

### US rail: USDC primary
- Deepest institutional liquidity (~$45B market cap as of early 2026).
- USDT accepted as a secondary option for Lenders who already hold it, but **not** built into core escrow settlement logic — higher counterparty/regulatory risk profile than USDC.

### EU rail: EURC primary
- Dominant MiCA-compliant euro stablecoin: ~41-42% of euro stablecoin market cap (surged from 17% in roughly 12 months, as of mid-2026 data).
- Issued by Circle (same issuer as USDC); secured EMT (Electronic Money Token) authorization from French regulators in July 2024 — full MiCA compliance from day one.
- EURT (Tether's euro stablecoin) is explicitly **excluded** — non-compliant under MiCA, facing delisting across regulated EU platforms as of 2025.
- **Critical MiCA constraint:** EMTs (including EURC) are legally prohibited from offering remuneration/yield to holders while idle. Practical effect: on EU-rail deals, Lender yield must be **fully priced into the discount rate at deal origination** — there is no mechanism for the escrow contract to earn idle-balance interest on held EURC while waiting for the Anchor's payment. This is a regulatory fact, not a design choice, and it actually simplifies EU-rail pricing (the discount rate IS the yield, fixed and clean at signing).
- USD rail does not share this constraint — idle USDC in escrow could theoretically earn yield via on-chain money markets, though this is not core/required for V1.

### Sequencing
Build and launch USD rail first. EUR rail liquidity is thinner today (~€500M total euro stablecoin market cap vs. USD stablecoin market dominance), though growing fast post-MiCA (transaction volumes up ~899% post-MiCA implementation per industry data) and a nine-bank European consortium (UniCredit, ING, SEB, et al.) has a compliant euro stablecoin expected in late 2026 that should further deepen liquidity. Revisit EUR rail build priority as that market matures — do not block V1 launch on EUR rail readiness.

### Cross-border deals
Default to **US governing law and USD settlement** regardless of Anchor's actual geography, when a deal spans US and EU counterparties. Reasoning: UCC-9 enforcement is faster and more predictable than EU cross-border proceedings. A deal never operates under two governing-law frameworks simultaneously — this is elected explicitly at deal creation and tagged by the underwriting process.

---

## 4. Smart contract system architecture

Three contracts, designed to work together but each independently auditable and each respecting the non-custodial constraint from Section 1.

### 4.1 Contract 1 — Identity Registry
**Purpose:** KYC-gate every wallet before it can participate in any deal. This is the legal bridge that turns a pseudonymous wallet signature into a named party's binding electronic signature (see business doc Section 6.4).

**Core functions:**
- `registerWallet(address, kycHash)` — admin-gated function. The "admin" here is specifically the off-chain KYC provider integration writing a verification result on-chain — this admin role **never touches deal funds**, only identity verification status. This is a deliberately narrow privileged role, separate from any fund-related logic.
- `isVerified(address) → bool` — public read function, called by the Deal Contract to gate signature acceptance.

**KYC provider:** off-the-shelf integration (Persona, Sumsub, or equivalent) for V1 — do not build KYC verification in-house. This is explicitly scoped as month 1 work.

### 4.2 Contract 2 — Deal Contract (one instance per deal)
**Purpose:** encodes the tri-party agreement terms and signature flow. Functions as the on-chain representation of the legal agreement described in business doc Section 6.5.

**Core functions:**
- `createDeal(borrower, anchor, faceValue, rate, maturityDate, docHash)` — initializes deal terms. `docHash` is the SHA-256 hash of the full tri-party legal agreement document (see Section 6 below on document hash anchoring).
- `signAsBorrower()`, `signAsAnchor()`, `signAsLender()` — wallet-signature-only functions. Each requires `isVerified() == true` (checked against the Identity Registry) for the calling wallet before the signature is accepted.
- `fundDeal()` — called by the Lender; sends stablecoin **directly to the Escrow Contract address**, never to a Deal Contract or company-controlled intermediate address.
- Once all three parties have signed AND the deal is funded, deal status becomes `ACTIVE` and is **immutable** — no admin function exists to alter terms after this point.

**Deal terms fields (fixed at signing, per business doc Section 6.5):** invoice/PO reference, face value, discount rate, maturity date, governing law election, currency (USDC/EURC), escrow contract address.

### 4.3 Contract 3 — Escrow Settlement
**Purpose:** the actual fund-holding and distribution logic. This is the contract that must most rigorously satisfy the non-custodial test in Section 1 — it is where real money sits.

**Core functions:**
- `receivePayment()` — the Anchor calls this (or it's triggered by a direct transfer) at maturity, sending the full face value. This function is **not gated to a specific caller** — anyone can technically call it, since the contract logic itself determines correct distribution regardless of who triggers it. This avoids any human discretion in the payment-receipt step.
- On receipt: auto-calculates the split per the terms recorded in the Deal Contract.
- `distribute()` — pays Lender (principal + yield), Treasury (protocol fee), Borrower (residual, if any). This is hardcoded distribution logic, not a human-callable discretionary transfer.
- `handleDefault()` — if maturity date has passed and payment has not been received, this function **flags the deal for off-chain legal recourse only**. It explicitly does **not** redirect funds anywhere — there is no automatic recovery mechanism on-chain. Recovery, if needed, happens through the legal enforceability of the governing-law election and tri-party agreement (see business doc Section 6.5 and Section 8, item 2 — this is a known open risk, not yet fully designed beyond "the legal agreement is the recourse path").

**Hard architectural rules for this contract specifically (non-negotiable, per Section 1):**
- No admin override function that can move funds to an arbitrary address.
- No pause function on fund-holding/distribution logic.
- No upgrade proxy pattern on this contract — it should be immutable once deployed, specifically because upgradability is itself a form of custody-adjacent control that would undermine the non-custodial legal argument.

### 4.4 Build order
Identity Registry first (simplest, fully testable in isolation) → Deal Contract → Escrow Settlement. Use OpenZeppelin's audited base contracts wherever applicable rather than writing primitives from scratch.

---

## 5. Document hash anchoring (the legal-to-code bridge)

This is the specific mechanism that makes "the smart contract IS the agreement" legally meaningful, not just a slogan.

1. The full tri-party legal agreement (see business doc Section 6.2 for drafting approach) is rendered as a complete document (PDF or equivalent).
2. That document is hashed using SHA-256.
3. The resulting hash is stored on-chain as part of the Deal Contract's `createDeal()` call (`docHash` parameter).
4. When each party signs via `signAsBorrower()` / `signAsAnchor()` / `signAsLender()`, their wallet signature constitutes cryptographic proof that they agreed to the **exact document** matching that hash — not a generic or potentially-altered version.

Without this mechanism, the smart contract and the legal document would have no provable connection to each other, undermining the entire "fully on-chain, wallet-signed" execution model the founder specified.

---

## 6. Security and testing

### 6.1 Static analysis — dual independent tool triangulation (founder's explicit instruction)
- Run **Slither** and **Mythril** independently — not as a single combined pass. Triangulate findings between the two tools.
- Fix all findings, re-run until clean, document every finding and the corresponding fix.
- **Important limitation to remember:** these are static analysis tools, not formal verification. They reliably catch known vulnerability *patterns* (reentrancy, integer overflow/underflow, access control gaps, unchecked external calls). They will **not** catch business-logic bugs specific to Nth Moment's rules — for example, an off-by-one error in the 40% concentration calculation, or a maturity-date comparison bug in the Escrow Contract's `handleDefault()` logic.

### 6.2 Custom test suite (required in addition to static analysis)
A test suite simulating the full deal lifecycle multiple times, specifically covering edge cases:
- Early payment (Anchor pays before maturity).
- Late payment (Anchor pays after maturity but before any default action).
- Partial KYC failure (one of three parties fails KYC verification mid-flow).
- Boundary conditions on the maturity-date comparison logic.
- Boundary conditions on any on-chain percentage/concentration math, if such logic is ever moved on-chain (currently the 40% concentration check is an off-chain underwriting input per business doc Section 4.2, not on-chain logic — but if this changes in a future version, boundary testing becomes critical).

### 6.3 Budget-conscious audit options
Given zero capital, full Big-4-style smart contract audits are likely out of reach for V1. Budget-appropriate alternatives to research and use:
- Community-driven audit competitions (e.g. Code4rena-style platforms).
- Careful manual review supplementing the Slither/Mythril static analysis.
- These options cost founder time, not cash — consistent with the zero-capital build constraint throughout this project.

### 6.4 Pre-mainnet checklist (Month 4 per business doc roadmap)
Deploy to chosen L2 mainnet with **zero real funds** first. Run a complete simulated deal cycle end-to-end using test wallets before any real-money deal is attempted. This is the dry run gate before Month 6's actual pilot deal.

---

## 7. Underwriting engine — V1 vs. future state

### 7.1 V1 (manual, founder-performed)
The founder's own credit judgment **is** the V1 underwriting engine. No AI/automated underwriting is required to prove the model. This was an explicit strategic correction made during planning: the founder's biggest asset right now is underwriting judgment, not code — automate only what has been proven to work manually.

V1 manual underwriting covers, per deal:
- Document review (invoice, PO, tri-party agreement terms) — founder reviews personally.
- Anchor rating floor check (B+ minimum, S&P/Moody's/Fitch) — manually verified against public filings/ratings for listed companies.
- Borrower concentration cap check (40%, rolling 12-month) — manual spreadsheet reconciliation of sales ledger, bank statements, and tax filings (see business doc Section 4.2 for full method).
- Legal/jurisdiction assessment — founder applies known frameworks (UCC-9, eIDAS, MiCA, etc. — see business doc Section 6.6 for the scoped legal corpus) manually for V1.

### 7.2 Future state (V2+, post-pilot, capital-dependent)
A three-pillar automated AI underwriting engine, **not** literally "on-chain LLM" (not currently technically feasible in that framing) but rather: AI processing triggered on-chain, executing off-chain, with outputs written back on-chain as a verifiable credit decision (approve/reject + discount rate + risk tag).

**Pillar 1 — Document intelligence:** invoice validation, PO cross-match, tri-party agreement parsing, Anchor signature confirmation, duplicate/fraud flagging.

**Pillar 2 — Risk scoring:** Anchor credit rating lookup/monitoring, payment history tracking, sector concentration risk, tenure-vs-risk curve modeling, discount rate calculation. This pillar is the natural home for automating the 40% concentration check once enough manually-verified deals exist as training data.

**Pillar 3 — Legal layer:** jurisdiction detection, assignability checking, mapping to the scoped legal corpus (UCC-9 / UK Bills of Exchange Act / EU Late Payment Directive / MiCA), governing law tagging, enforcement risk scoring.

**This is explicitly the protocol's defensible IP moat** — not the smart contract code (which is largely standard patterns), but the trained legal corpus plus risk model, built on the founder's 10 years of credit underwriting experience plus deal-flow data accumulated from real pilot deals. Every deal that flows through the protocol adds training data, making the corpus self-reinforcing over time.

**Sequencing note:** do not attempt to build this automated engine before proving the model manually with real pilot deals (per the six-month roadmap in the business document). V1 success with manual underwriting is the prerequisite, not an alternative path.

---

## 8. Open technical questions / not yet decided

These are flagged explicitly as undecided, to avoid silently assuming an answer in future sessions:

1. **Exact KYC provider** — Persona vs. Sumsub vs. alternatives not yet evaluated in detail; Month 1 work.
2. **Anchor rating data source** — whether free public filings suffice for V1 or a paid ratings-data subscription becomes necessary has not been resolved.
3. **Audit competition platform selection** (Section 6.3) — not yet researched in detail.
4. **Whether/how on-chain money-market yield on idle USDC (US rail only) gets implemented** — flagged as "not core to V1," not actively designed.
5. **Exact legal jurisdiction/court for governing-law election on US deals** — "US governing law" has been decided at a high level (vs. EU law for cross-border deals) but the specific state/forum has not been chosen.
6. **Month 7+ plan** — deliberately not yet detailed; to be revisited based on Month 6 pilot outcome.

---

## 9. Explicit non-goals for V1 (do not build these yet)

- No open/public liquidity pool — V1 uses 1-3 known network Lenders only, not automated capital matching.
- No multi-chain deployment — single L2 chain only for V1.
- No automated AI underwriting engine — manual founder underwriting only (Section 7.1).
- No proprietary KYC/identity system — off-the-shelf provider integration only.
- No India-market deals of any kind — explicitly out of scope per founder's stated position.
- No admin pause/upgrade capability on the Escrow Settlement contract, ever, even temporarily for testing convenience on mainnet — this directly conflicts with the non-custodial architecture this entire build depends on.
