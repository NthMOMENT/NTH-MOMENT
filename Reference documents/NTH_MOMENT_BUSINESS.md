# Nth Moment — Business Reference Document

**Status:** Pre-build, planning locked. Six-month build window in progress.
**Last updated:** 19 June 2026
**Domains owned:** nthmoment.xyz, nthmoment.in

---

## 1. Founder profile

- 10 years experience in Indian banking, asset/credit/risk side. Deep underwriting background, near-Moody's-certificate level credit expertise.
- Operates as a partnership firm, DUNS registered.
- Solo founder. Zero outside capital. No co-founders, no partners being sought at this stage.
- Working with an AI assistant (Claude) acting as technical co-founder for architecture, build planning, and document drafting — not a legal or licensed advisory relationship.
- Two unrelated ETH-paid projects running in parallel as personal income/runway during the six-month build window — low risk, straightforward, not connected to Nth Moment.
- Geographic experience gap: deep India credit market knowledge, zero direct US/EU trade finance market experience or contacts. This is an acknowledged, actively-being-closed gap (see Section 8).
- Stated posture on professional credentialing: will pursue formal certification (e.g. a Moody's-style exam) later if the business's growth requires it — not a prerequisite to building.
- Stated posture on lawyers: skeptical of over-scoped legal engagement; will use targeted, paid, narrow-scope legal review only at specific checkpoints (e.g. tri-party agreement template before first real-money deal), not as a blanket dependency.

---

## 2. The core thesis

DeFi lending today is almost entirely overcollateralised (Aave, Compound, MakerDAO model — 150-200%+ collateral required). This excludes the entire category of TradFi short-tenure, self-liquidating trade credit: invoice discounting, reverse factoring, escrow-based project finance. No DeFi protocol has successfully built this because:

1. It requires real credit underwriting expertise (TradFi domain knowledge), which crypto-native teams lack.
2. It requires legal enforceability against real-world counterparties, which prior attempts (Goldfinch, Maple Finance) never solved.
3. It requires distinguishing borrower credit risk (weak, hard to verify) from buyer/Anchor payment obligation risk (strong, verifiable, lower risk).

Nth Moment's differentiation: tokenize the **Anchor's (buyer's) payment obligation**, not the Borrower's (seller's) promise. This is structurally equivalent to reverse factoring / supply chain finance in TradFi — a known, court-tested credit structure — applied on-chain with KYC-bound legal enforceability.

### Why Goldfinch and Maple Finance failed (cautionary precedent)
- Both separated credit risk from legal enforceability — real-world borrowers, no on-chain teeth.
- Goldfinch: community-vote underwriting (no domain expertise), pseudonymous borrowers, no collateral, zero legal enforcement. ~$20M unrecovered defaults (2023, Stratos/Tugende).
- Maple Finance: crypto-native delegate underwriting (not credit analysts), concentrated in crypto trading firms, minimal collateral, weak legal wrapper. ~$52M unrecovered (2022, Orthogonal Trading fraud, triggered by FTX collapse).
- Shared fatal flaw: credit risk was real-world, enforcement was on-chain, the two never connected.

---

## 3. Product structure

### 3.1 Deal type
**Reverse factoring with tri-party agreement** (not plain invoice discounting). Three parties per deal:
- **Borrower** (Seller) — holds the receivable, seeks early liquidity.
- **Anchor** (Buyer) — owes the payment obligation underlying the receivable. The actual credit risk in the deal.
- **Lender** (Funder) — provides capital against the receivable, earns yield via discount rate.

Deal types in scope: discounting of receivables (invoice discounting / reverse factoring), escrow-based project finance. Tenure: under 120 days (typically 30-90 days). These are self-liquidating credit instruments — repayment source is built into the transaction structure itself.

### 3.2 Nth Moment's role
Nth Moment is **not a lender**. It does not lend its own capital and does not hold credit risk on its balance sheet. It is **protocol infrastructure** — providing underwriting assessment, legal-template tri-party agreement execution, and non-custodial escrow/settlement rails. Lenders fund deals directly and independently bear the credit risk. This structural choice is also what keeps Nth Moment outside money-transmitter licensing scope (see Section 6).

### 3.3 Revenue model
Protocol fees, not interest income — two fee events per deal:
- **Underwriting fee** at credit decision: ~25-75 bps of face value.
- **Origination fee** at disbursement: ~50-100 bps of face value.
- Example: $500K invoice discounting deal → $3,750-$8,750 protocol revenue, realized in 30-90 days, with zero direct credit risk to the protocol.
- Fees are collected automatically via smart contract logic at the point of disbursement/settlement — never invoiced or collected manually (critical for custody/licensing posture, see Section 6).

---

## 4. Risk controls (immutable for first 100 deals)

These two controls are locked as hard underwriting gates for the first 100 deals on the protocol. They are not configurable per-deal during this period.

### 4.1 Anchor rating floor
- Minimum **B+** rating from S&P (or equivalent — Moody's/Fitch) required for the Anchor (buyer) on every deal.
- Applies to listed, rated companies only in this initial phase.
- Verified manually by founder during V1 (public filings/ratings are accessible, even free, for listed companies).
- Hard gate — no deal proceeds without this being satisfied.

### 4.2 Borrower concentration cap — 40%
- The Borrower's receivables exposure to any single Anchor cannot exceed **40%** of the Borrower's total revenue, measured on a **rolling 12-month basis ending at the date of application** (not calendar year, not fiscal year — true rolling window, matching CRISIL convention from the founder's India experience).
- **Formula:** (12-month revenue from this Anchor) ÷ (12-month total revenue) ≤ 40% to pass.
- **Verification method — three-way triangulation** (not self-attestation, which is unverifiable):
  1. **Sales ledger** — Borrower-provided, claimed revenue by Anchor.
  2. **Bank statements** — actual cash received, timing and amounts, last 12 months.
  3. **Tax filings** — US sales tax filings or EU VAT returns, last 4 quarters. Chosen specifically because these are filed to a government authority and carry criminal exposure for falsification, making them the hardest of the three sources to fake.
- All three sources should roughly reconcile on total revenue and revenue attributable to the specific Anchor.
- **V1 reality check:** This is real forensic accounting labor, not a form field. Enterprise trade finance software (e.g. Demica, Taulia) that automates this exists but costs real money the founder does not have at V1. For the first 1-3 pilot deals, this will be done **manually by the founder** using spreadsheet reconciliation — this manual process is itself the proof of underwriting competence and becomes training data for the future automated risk-scoring pillar of the AI underwriting engine.
- **Document request list given to every Borrower at application:** 12-month sales ledger; 12-month bank statements; last 4 quarterly sales tax/VAT filings.

---

## 5. Target market and geography

- **Geography:** US and EU only. Explicitly **not** India, by founder's deliberate choice ("No India and never India").
- **Borrower segment:** Institutions/DAOs and real-world businesses (exporters, contractors, SMEs) with receivables from creditworthy corporate buyers — initially leaning toward crypto-native or crypto-comfortable counterparties to reduce the US/EU market-knowledge gap during early deals.
- **Currency/rails:**
  - US deals: USDC primary (deepest institutional liquidity, ~$45B market cap as of early 2026). USDT accepted as secondary only — not built into core escrow settlement logic due to higher counterparty risk profile.
  - EU deals: EURC primary — the dominant MiCA-compliant euro stablecoin (~41-42% of euro stablecoin market cap as of mid-2026, issued by Circle, EMT-licensed in France since July 2024). USDT's euro variant (EURT) is non-compliant under MiCA and excluded.
  - **Important EU constraint:** under MiCA, Electronic Money Tokens (including EURC) are prohibited from offering remuneration/yield to holders while idle. This means lender yield on EU deals must be fully priced into the discount rate at deal origination — there is no idle-balance interest mechanism available on the EUR rail. USD rail does not have this constraint (idle USDC could theoretically earn yield via on-chain money markets, though this is not core to V1).
  - **Sequencing:** Build and launch USD rail first. EUR rail liquidity is thinner today but structurally improving — a nine-bank European consortium (UniCredit, ING, SEB, et al.) has announced a new compliant euro stablecoin expected in late 2026, which should deepen EUR liquidity over time. Revisit EUR rail prioritization as that market matures.
  - **Cross-border deals** (e.g. US Anchor, EU Borrower): default to US governing law / USD settlement regardless of Anchor geography, since UCC-9 enforcement is faster and more predictable than EU cross-border proceedings. Never operate two governing-law frameworks simultaneously on one deal.

---

## 6. Regulatory and legal posture

### 6.1 Money transmitter licensing — the central constraint
This is the single most important regulatory finding from initial research and it is a **hard architectural constraint**, not a future consideration.

- US money transmitter licensing applies to businesses that transmit money, funds, payment instruments, stored value, or digital assets **"on behalf of customers."** That phrase is the legal trigger.
- Licensing costs are prohibitive for a zero-capital founder: state-by-state, $30,000-$525,000+ per state in total costs (application fees, surety bonds, etc.); California alone requires surety bonds from $250,000 to $7 million; 49 of 50 US states require some form of MTL.
- **Nth Moment's structural answer:** the protocol must be architected as genuinely **non-custodial**. If money flows automatically by smart contract code — Anchor wallet directly to escrow contract, escrow contract directly to Lender and Treasury wallets — with no human-controlled wallet or company account ever sitting in the payment path, there is a strong argument the protocol is not "transmitting money on behalf of customers." This is the same legal logic that allows non-custodial DeFi protocols like Uniswap and Aave to operate without MTLs.
- **This produces hard, non-negotiable design rules** (see Section 6.2 for the canonical custody boundary).
- Regulators are explicitly intolerant of "build first, license later" — this constraint must be respected from the very first line of contract code, not retrofitted.

### 6.2 The custody boundary — canonical test
**The test for every future feature or operational decision:** "Does a human or a controllable wallet ever sit between the payer and the payee?" If yes — even briefly, even with good intent, even to "help" — it is custody, and the flow must be redesigned. Code-only paths between parties, always.

**Safe (non-custodial) patterns:**
- Anchor pays the escrow smart contract directly — no Nth Moment wallet in the path.
- Protocol fee is auto-deducted by contract logic at settlement — never invoiced or collected manually.
- No admin override/key exists on the escrow contract that can redirect funds — contract logic alone moves money, immutable rules, no human discretion, even "just in case."
- Founder publishes a risk opinion/score on-chain; the Lender independently decides whether to fund. The protocol never auto-allocates Lender capital without per-deal consent.
- Founder never personally holds, touches, or has signing authority over deal funds, under any circumstance, including emergencies.

**Dangerous (custodial, must never happen):**
- Anchor pays a company/founder-controlled wallet, which then forwards to the Lender.
- Founder invoices the Borrower separately and collects the protocol fee manually.
- An admin key exists that can redirect or pause escrow funds.
- The protocol auto-matches/allocates Lender capital without the Lender's explicit per-deal consent (starts to resemble discretionary fund management).
- Founder personally facilitates a stuck transfer "just this once."

### 6.3 Underwriting licensing
- Founder does not hold a formal underwriting/credit-rating license (e.g. no Moody's-style certification yet).
- Working legal theory: Nth Moment provides a **risk assessment opinion**, not a binding credit decision. The Lender, by independently signing the tri-party agreement and funding the escrow themselves, makes their own credit decision with Nth Moment's analysis as input. This positions Nth Moment closer to a credit-analyst/ratings-opinion function than a regulated underwriter — reinforced by the non-custodial, non-lending structure in Section 3.2.
- Founder's stated posture: pursue formal credentialing later if/when the business's scale or counterparties require it, not as a prerequisite to building.

### 6.4 Electronic signature / wallet-as-signature legal basis
- Fully on-chain execution model: **the smart contract is the agreement.** All three parties sign with KYC-locked wallets — no separate wet-ink or e-sign-only process.
- Legal basis in the US: E-SIGN Act (2000) and UETA give electronic signatures, including wallet signatures, equivalent legal weight to wet ink, provided intent to sign is established.
- Legal basis in the EU: eIDAS Regulation. UK: Electronic Communications Act 2000.
- **The KYC lock is the bridge** that transforms a pseudonymous crypto wallet signature into a legally binding electronic signature of a named party. Without KYC, a wallet signature is ambiguous as to intent and identity. With KYC, it is a named legal entity signing a contract.
- All three wallets (Borrower, Anchor, Lender) must be KYC-verified before any tri-party agreement signature is accepted by the Deal Contract.

### 6.5 Escrow / settlement mechanics (legal logic)
- The Anchor does **not** pay the Borrower directly at maturity. The Anchor pays the protocol's **escrow smart contract**, which then automatically distributes: principal + yield to the Lender, protocol fee to the Treasury, residual (if any) to the Borrower.
- This is the mechanism that gives Nth Moment legal "teeth" that Goldfinch/Maple never had — there is no point in the payment flow where a human party can redirect funds away from the agreed distribution.
- Document hash anchoring: the full tri-party agreement document is hashed (SHA-256); the hash is stored on-chain. Wallet signatures constitute cryptographic proof that the signer agreed to that exact document. This is the technical bridge that makes "the smart contract IS the agreement" legally meaningful — without it, the contract and the legal document would have no provable connection.
- Governing law is elected explicitly at deal creation (tagged by the underwriting process) and a deal never operates under two governing-law frameworks simultaneously.
- **Anchor default scenario (known open risk):** if the Anchor fails to pay at maturity, the escrow contract has no automatic recovery mechanism — this is where the governing-law election and the legal enforceability of the tri-party agreement (UCC-9 in the US, equivalent EU frameworks) become the actual recovery path. This is acknowledged as the area where Nth Moment must be strongest, since it's exactly where Goldfinch/Maple had nothing.

### 6.6 Legal corpus scope (for future AI underwriting engine, see tech stack doc)
The legal-layer underwriting only needs to cover known, finite frameworks initially:
- US: UCC Article 9 (receivables assignment/enforceability), E-SIGN Act.
- UK: Bills of Exchange Act, Electronic Communications Act 2000.
- EU: Late Payment Directive, eIDAS Regulation, MiCA (for stablecoin/EMT-specific rules).
This is described as a "finite, trainable problem" rather than an open-ended global legal challenge — a deliberate scoping decision to keep V1's legal corpus buildable.

---

## 7. Build sequencing and roadmap (six-month window)

Founder-set window: six months from build start to first real pilot deal, run in parallel with two unrelated ETH-paid projects providing personal runway.

**Agreed build order for foundational work (locked):** Custody boundary definition → Tri-party legal agreement template → Smart contract architecture → Pilot deal sourcing strategy. (I.e., know the legal/regulatory line first, encode it in the agreement template second, build the code third, then go find counterparties.)

### Month 1 — Dev environment + Identity Registry contract
- Solidity/Foundry setup, OpenZeppelin audited base contracts.
- KYC provider integration (off-the-shelf — Persona, Sumsub, or similar; do not build in-house for V1).
- Testnet deployment of Identity Registry contract (KYC-gated wallet whitelisting).

### Month 2 — Deal Contract + Escrow Settlement contract; parallel legal drafting
- Tri-party signing logic, document hash anchoring, USDC/EURC settlement logic, full testnet integration of all three contracts.
- Parallel: draft the tri-party agreement legal template (adapted from an existing factoring/receivables purchase agreement template — founder's banking background makes this competently draftable solo), embedding the B+ rating and 40% concentration clauses from Section 4. One paid lawyer review pass on this template specifically, once drafted, before it is used on a real deal — not before.

### Month 3 — Security: dual independent static analysis; parallel market study begins
- Run Slither and Mythril **independently** (triangulation, per founder's explicit instruction), fix all findings, re-run until clean, document every finding and fix.
- Note: these are static analysis tools, not formal verification — they catch known vulnerability patterns (reentrancy, overflow, access control) but not business-logic bugs (e.g. an off-by-one in the 40% concentration math, a maturity-date comparison bug). A custom test suite simulating the full deal lifecycle (including edge cases: early payment, late payment, partial KYC failure) is required in addition to static analysis, before month 4.
- Parallel: US/EU market study begins — UCC-9, factoring industry reports, typical discount rate benchmarks, payment-culture norms, MiCA detail.

### Month 4 — Mainnet deployment prep + dry run; parallel advisor calls
- Deploy contracts to mainnet (chain: see tech stack doc) with zero real funds; run a full simulated deal cycle end-to-end using test wallets.
- Parallel: 1-2 paid, narrowly-scoped advisor calls with a US/EU trade finance veteran, specifically to validate underwriting assumptions and sense-check the model against real market texture — not a partnership, not equity, hours only.

### Month 5 — Active pilot deal sourcing begins; parallel lender lining-up
- Outreach to founder's existing banking/trade-finance network, trade finance broker communities, and crypto-native firms/DAOs needing working capital (smallest market-knowledge gap, since founder already understands crypto-native counterparties).
- Document request list (Section 4.2) ready to issue to any candidate Borrower.
- Parallel: line up 1-3 known/network Lenders (crypto-native individuals or small funds who trust the founder's credit judgment personally) — not a public/open liquidity pool at this stage.

### Month 6 — First real pilot deal: full underwriting + execution
- B+ Anchor rating verified, 40% concentration check completed manually (ledger/bank/tax triangulation), tri-party agreement signed on-chain by all three KYC-locked wallets, deal funded into escrow, settled automatically at maturity.
- This single clean, end-to-end deal cycle is the proof of concept — intended to be more valuable for credibility, future fundraising, and legal precedent than a year of theoretical architecture work.

### Month 7+ (not yet detailed)
Scale from one proven deal — use it as proof for either fundraising or sourcing deal #2. Not yet planned in detail; revisit after Month 6 outcome is known.

---

## 8. Known open risks and gaps (acknowledged, not yet solved)

1. **US/EU market knowledge gap.** Founder's 10 years of credit experience is entirely India-market. Credit risk pattern recognition (cash flow analysis, fraud signals, structural red flags, document analysis discipline, deal-structuring instinct) is judged to transfer directly. Counterparty reputation knowledge, default recovery mechanics under US/EU law, and local market texture (typical rates, payment culture, what's normal vs. a red flag) do **not** transfer and must be actively built during the six-month window via study (Month 3) and paid advisor calls (Month 4). Assessed as a sequencing gap, not a structural blocker.
2. **Anchor default / non-payment recovery path is not yet fully designed.** The escrow contract by itself has no automatic recovery mechanism if an Anchor simply fails to pay; recovery depends on the legal enforceability of the off-chain governing-law election and tri-party agreement. This is flagged as the area requiring the most legal rigor, precisely because it's where Goldfinch/Maple had nothing.
3. **40% concentration check is currently a manual, founder-performed process** for V1 (1-3 pilot deals). It does not scale without either hired underwriting staff or the future AI risk-scoring pillar (see tech stack doc) — both of which require capital or proven deal volume Nth Moment does not yet have.
4. **Anchor rating data sourcing.** Currently assumed public/free for listed, rated companies; no paid ratings-data subscription has been budgeted or arranged.
5. **EUR rail liquidity is currently thin** relative to USD rail; sequencing deliberately starts USD-first for this reason.
6. **No formal legal opinion has yet been obtained** on the non-custodial/MTL-avoidance architecture described in Section 6.1-6.2. This is the founder's own analysis plus AI-assisted research, not a substitute for one targeted legal review before real money moves through the system. This is flagged once in this document as a standing caveat — not a blocking dependency for early build work, but a checkpoint to clear before the Month 6 real pilot deal.

---

## 9. Naming and positioning

- **Name:** Nth Moment.
- **Domains:** nthmoment.xyz, nthmoment.in (both owned by founder).
- **One-line pitch:** "We tokenize the buyer's payment obligation, not the seller's promise — turning invoices and escrow-based project finance into self-liquidating, on-chain credit instruments, underwritten by a credit professional and enforced by KYC-locked tri-party smart contracts."
- This positioning is deliberately built to differentiate from both (a) Aave-style overcollateralised DeFi lending, and (b) Goldfinch/Maple-style unsecured, unenforceable DeFi credit — placing the founder's actual underwriting background as the first differentiator a reader encounters.
