# Sui Multi-Signature Governance Wallet

A decentralized multi-signature wallet built on the Sui blockchain, featuring dual governance models, snapshot-based voting security, and event-driven architecture for trustless fund management.

---

## 📋 Project Overview

This project implements a sophisticated multi-signature wallet system on Sui that allows groups to collectively manage funds through on-chain voting. Unlike traditional multi-sig wallets with fixed thresholds, our implementation supports two distinct governance models and employs "snapshot security" to prevent hostile takeovers during active votes.

### Core Features Across All Versions

- **Shared Object Architecture**: Wallet and proposals are accessible to all authorized participants
- **Dynamic Ownership**: Add/remove owners through governance proposals
- **Dual Governance Models**: Choose between Unanimity (100%) or Plurality (>50%) voting
- **Snapshot Security**: Voter eligibility is locked at proposal creation to prevent manipulation
- **Event-Driven State**: Frontend can reconstruct entire history from on-chain events
- **Multi-Action Support**: Send funds, add owners, or remove owners through proposals

---

## 🔄 Version History

### v0: Foundation - Basic Multi-Sig Implementation

**Purpose**: Educational foundation implementing standard multi-sig wallet patterns for the Distributed Systems class project.

#### Architecture

```
MultisigWallet (Shared Object)
├── owners: vector<address>
├── balance: Balance<SUI>
└── threshold: u64  // Fixed numeric threshold

Proposal (Shared Object)
├── wallet_id: ID
├── recipient: address
├── amount: u64
└── approvals: vector<address>  // Simple approval list
```

#### Key Functions

- `create_wallet(owners, threshold)` - Initialize wallet with fixed approval count
- `deposit(wallet, coin)` - Anyone can fund the wallet
- `create_proposal(wallet, recipient, amount)` - Owners propose transfers
- `approve_proposal(wallet, proposal)` - Owners approve (no rejection mechanism)
- `execute_proposal(wallet, proposal)` - Execute when `approvals.length >= threshold`
- `add_owner(wallet, new_owner)` - Direct owner addition (no voting required)
- `remove_owner(wallet, owner)` - Direct owner removal (no voting required)

#### Characteristics

✅ **Simple and Easy to Understand**: Clean implementation of basic multi-sig logic  
✅ **Gas Efficient**: Minimal state storage  
⚠️ **Limited Flexibility**: Fixed threshold, can't adapt to changing group size  
⚠️ **Security Gaps**:

- No rejection voting
- Owner changes bypass governance
- Vulnerable to hostile takeover (owner can be removed during active vote)
- No expiry mechanism

#### Use Case

Perfect for **small, trusted groups** (e.g., 2-of-3 wallet for co-founders) where governance changes are rare and trust is high.

---

### v1: Enhanced Governance - Dual Voting Models

**Purpose**: Production-ready multi-sig with flexible governance, snapshot security, and comprehensive proposal management.

#### Major Changes from v0

##### 1. **Dual Governance Models** 🎯

Replaced fixed `threshold: u64` with dynamic `wallet_type: u8`:

```move
// v0: Static threshold
threshold: 3  // Always needs exactly 3 approvals

// v1: Dynamic governance
wallet_type: WALLET_TYPE_PLURALITY (0)  // Needs > 50% of current owners
wallet_type: WALLET_TYPE_UNANIMITY (1)  // Needs 100% of current owners
```

**Why**: Adapts automatically as owners are added/removed. A 2-of-3 wallet that adds a 4th owner automatically becomes 3-of-4 for Plurality.

##### 2. **Snapshot Security** 🔒

The critical vulnerability fix:

```move
// v0: Checks against CURRENT wallet owners
assert!(is_owner(wallet, sender), ENotAnOwner);

// v1: Checks against SNAPSHOT from proposal creation
snapshot_owners: vector<address>  // Copied at create_proposal()
assert!(vector::contains(&proposal.snapshot_owners, &sender), ENotAnOwner);
```

**Attack Prevented**:

- **Scenario**: Alice, Bob, Charlie share a wallet. Alice proposes sending funds.
- **v0 Vulnerability**: Bob creates another proposal to remove Alice, gets it executed before Alice's vote completes. Alice can no longer vote on her own proposal.
- **v1 Protection**: Alice's proposal has `snapshot_owners = [Alice, Bob, Charlie]`. Even if she's removed from the wallet, she can still vote on that specific proposal.

##### 3. **Rejection Voting** 👎

```move
// v0: Only approval tracking
approvals: vector<address>

// v1: Explicit approval/rejection with different logic per model
approval_count: u64
rejection_count: u64

// Unanimity: First "No" kills the proposal
if (wallet_type == UNANIMITY && !approve) {
    proposal.status = STATUS_REJECTED;
}

// Plurality: Rejection when mathematically impossible to pass
if (rejection_count > (total_owners / 2)) {
    proposal.status = STATUS_REJECTED;
}
```

**Impact**: Proposals can be actively rejected instead of just timing out, providing clear closure.

##### 4. **Status System** 📊

```move
// v0: Implicit states (executed when threshold met)

// v1: Explicit status tracking
const STATUS_PENDING: u8 = 0;
const STATUS_EXECUTED: u8 = 1;
const STATUS_REJECTED: u8 = 2;
const STATUS_EXPIRED: u8 = 3;

status: u8  // in Proposal struct
```

**Benefit**: Frontend can filter proposals by state without complex logic.

##### 5. **Multi-Action Proposals** 🛠️

```move
// v0: Only transfer proposals
recipient: address
amount: u64

// v1: Generic action system
action_type: u8  // ACTION_SEND_SUI, ACTION_ADD_OWNER, ACTION_REMOVE_OWNER
target_address: address  // Multipurpose (recipient OR target owner)
amount: u64  // Used for transfers, 0 for owner actions
```

**Why**: Owner changes now require full governance approval, closing the v0 security gap.

##### 6. **Event-Driven Architecture** 📡

```move
// v0: No events (frontend must poll state)

// v1: Comprehensive event emissions
public struct WalletCreated has copy, drop { ... }
public struct ProposalCreated has copy, drop { ... }
public struct VoteCast has copy, drop { ... }
public struct ProposalStatusChanged has copy, drop { ... }
```

**Impact**:

- Frontend can rebuild entire history from events
- No centralized database needed
- Real-time updates via event subscriptions
- Analytics and dashboards possible

##### 7. **Expiry Mechanism** ⏰

```move
// v0: Proposals live forever

// v1: Optional expiry
expiry_ms: Option<u64>  // Unix timestamp in milliseconds

// Checked during voting
if (clock::timestamp_ms(clock) > deadline) {
    proposal.status = STATUS_EXPIRED;
}
```

**Use Case**: Prevents stale proposals (e.g., "Send funds to contractor" becomes irrelevant after project ends).

##### 8. **Double-Vote Prevention** 🚫

```move
// v0: Basic vector check (linear search)
assert!(!has_approved(proposal, sender), EAlreadyApproved);

// v1: Efficient set-based tracking
voters: VecSet<address>  // O(log n) lookup
assert!(!vec_set::contains(&proposal.voters, &sender), EAlreadyVoted);
```

**Performance**: Better for wallets with many owners (e.g., DAO-style governance).

#### Architecture v1

```
MultisigWallet
├── owners: vector<address>
├── balance: Balance<SUI>
└── wallet_type: u8  // NEW: Governance model

Proposal
├── wallet_id: ID
├── creator: address  // NEW: Attribution
├── action_type: u8  // NEW: Multi-action support
├── target_address: address
├── amount: u64
├── snapshot_owners: vector<address>  // NEW: Security
├── voters: VecSet<address>  // NEW: Efficient tracking
├── approval_count: u64  // NEW: Explicit counts
├── rejection_count: u64
├── status: u8  // NEW: State machine
└── expiry_ms: Option<u64>  // NEW: Time limits
```

---

### v2: Production Hardening - Security & Edge Cases

**Purpose**: Address critical vulnerabilities and edge cases discovered through security audit (Claude AI code review).

#### Critical Fixes from v1

##### 1. **Prevent Last Owner Removal** 🔐 (CRITICAL)

```move
// v1: Could remove all owners, locking wallet forever
vector::remove(&mut wallet.owners, index);

// v2: Enforced minimum owner count
assert!(vector::length(&wallet.owners) > 1, ECannotRemoveLastOwner);
vector::remove(&mut wallet.owners, index);
```

**Attack Prevented**:

- **Scenario**: 3-owner wallet. Malicious proposal removes all 3 owners one by one.
- **v1 Result**: Wallet holds funds but has no owners. Funds permanently locked.
- **v2 Protection**: Cannot execute the final removal. At least 1 owner always remains.

##### 2. **Duplicate Owner Prevention** 🚫 (CRITICAL)

```move
// v1: Could create wallet with duplicate addresses
create_wallet([Alice, Alice, Bob], ...)

// v2: Validation at creation
let mut seen = vec_set::empty<address>();
while (i < len) {
    let addr = *vector::borrow(&owners, i);
    assert!(!vec_set::contains(&seen, &addr), EDuplicateOwner);
    vec_set::insert(&mut seen, addr);
    i = i + 1;
}
```

**Attack Prevented**:

- **v1 Scenario**: Create wallet with `owners = [Alice, Alice, Bob]`. Alice has 2 votes in "Plurality" mode.
- **v2 Protection**: Transaction aborts with `EDuplicateOwner`.

##### 3. **Insufficient Balance Check** 💰 (MAJOR)

```move
// v1: Only discovered during execution (wasted voter gas)
let coin = coin::take(&mut wallet.balance, proposal.amount, ctx);  // Aborts here if insufficient

// v2: Explicit validation with clear error
assert!(balance::value(&wallet.balance) >= proposal.amount, EInsufficientBalance);
let coin = coin::take(&mut wallet.balance, proposal.amount, ctx);
```

**Impact**:

- **v1**: Voters approve a 100 SUI transfer. Wallet only has 50 SUI. Execution fails, but voters already spent gas.
- **v2**: Execution fails fast with clear error message before attempting transfer.

##### 4. **Expiry Check in Execution** ⏰ (MAJOR)

```move
// v1: Only checked during voting
// Problem: Proposal could expire BETWEEN last vote and execution

// v2: Double expiry check
// In vote():
if (clock::timestamp_ms(clock) > deadline) { abort EProposalExpired }

// In execute_proposal():
assert!(clock::timestamp_ms(clock) <= deadline, EProposalExpired);
```

**Edge Case Prevented**:

- **Scenario**: 2-of-3 wallet, 24-hour expiry. At 23:59, second owner approves (passes threshold). At 24:01, someone calls `execute_proposal()`.
- **v1**: Executes successfully (expired proposal goes through)
- **v2**: Aborts with `EProposalExpired`

##### 5. **Reentrancy Protection** 🛡️

```move
// v1: Update state AFTER external call
let coin = coin::take(&mut wallet.balance, proposal.amount, ctx);
transfer::public_transfer(coin, proposal.target_address);  // External interaction
proposal.status = STATUS_EXECUTED;  // THEN update

// v2: Checks-Effects-Interactions pattern
proposal.status = STATUS_EXECUTED;  // Update FIRST
event::emit(ProposalStatusChanged { ... });
// THEN interact
let coin = coin::take(&mut wallet.balance, proposal.amount, ctx);
transfer::public_transfer(coin, proposal.target_address);
```

**Why**: While Sui's object model prevents traditional reentrancy (unlike Ethereum), this follows best practices and prevents edge cases where a receiving contract might behave unexpectedly.

##### 6. **Error Code Organization** 📝

```move
// v1: All errors used
const EOwnerExists: u64 = 4;
const EOwnerNotFound: u64 = 5;

// v2: Strategic commenting (Design Decision)
// const EOwnerExists: u64 = 4;     // Unused - we allow silent skip
// const EOwnerNotFound: u64 = 5;   // Unused - we allow silent skip
const ECannotRemoveLastOwner: u64 = 9;   // NEW
const EDuplicateOwner: u64 = 10;         // NEW
const EInsufficientBalance: u64 = 11;    // NEW
```

#### Design Decision: Silent Success vs Hard Abort 🤔

**The Philosophical Fork**: What happens when a proposal's preconditions are no longer met?

**Scenario**:

- Proposal A: "Add Alice as owner" (created at time T)
- Proposal B: "Add Alice as owner" (created at time T+1)
- Both get approved
- Proposal B executes first → Alice is now an owner
- Proposal A tries to execute → Alice already exists

**Option 1 - Hard Abort (Claude's Recommendation)**:

```move
assert!(!vector::contains(&wallet.owners, &proposal.target_address), EOwnerExists);
vector::push_back(&mut wallet.owners, proposal.target_address);
```

- **Result**: Transaction fails, proposal stays `STATUS_PENDING` forever
- **Pro**: Explicit failure is transparent
- **Con**: Creates "zombie proposals" that clutter UI and can never be executed

**Option 2 - Silent Success (Our Implementation)**:

```move
if (!vector::contains(&wallet.owners, &proposal.target_address)) {
    vector::push_back(&mut wallet.owners, proposal.target_address);
}
// Proposal marks as EXECUTED regardless
```

- **Result**: Transaction succeeds, proposal marked `STATUS_EXECUTED`
- **Pro**: Clean state - voters wanted Alice added, Alice is added, proposal closes
- **Con**: "Executed" status is slightly misleading (no state change occurred)

**Our Choice**: Silent Success
**Rationale**:

1. **Intent Fulfillment**: The voters' goal (Alice being an owner) is met
2. **State Hygiene**: Proposals shouldn't remain open forever due to race conditions
3. **User Experience**: Better to show "Executed (no change needed)" than "Stuck Forever"
4. **Analogy**: Like running `mkdir folder` when folder exists - operation succeeds idempotently

**Same logic applied to**:

- Adding existing owner → Silent skip
- Removing non-existent owner → Silent skip (but PREVENT removing last owner - that's permanent damage)

#### Privacy Note 🔍

The `voters: VecSet<address>` field is **publicly readable** on-chain. Our specification initially mentioned "privacy," but true privacy on public blockchains requires:

- Zero-Knowledge proofs (like Natalius protocol)
- Off-chain computation with on-chain verification
- Substantial complexity and gas costs

**Our pragmatic approach**:

- Store `voters` publicly for **security** (prevent double-voting)
- Emit `VoteCast` events for **transparency**
- Acknowledge that transaction signatures are public anyway (observers can see who called `vote()`)

**Trade-off**: Simple, secure implementation over pseudo-privacy.

---

## 📊 Feature Comparison Matrix

| Feature                  | v0       | v1           | v2                |
| ------------------------ | -------- | ------------ | ----------------- |
| **Governance**           |
| Fixed Threshold          | ✅       | ❌           | ❌                |
| Plurality (>50%)         | ❌       | ✅           | ✅                |
| Unanimity (100%)         | ❌       | ✅           | ✅                |
| **Security**             |
| Snapshot Voting          | ❌       | ✅           | ✅                |
| Double-Vote Prevention   | Basic    | ✅ VecSet    | ✅ VecSet         |
| Last Owner Protection    | ❌       | ❌           | ✅                |
| Duplicate Owner Check    | ❌       | ❌           | ✅                |
| Balance Validation       | ❌       | ❌           | ✅                |
| Reentrancy Protection    | ❌       | ❌           | ✅                |
| **Functionality**        |
| Send Funds               | ✅       | ✅           | ✅                |
| Add/Remove Owners        | Direct   | Via Proposal | Via Proposal      |
| Rejection Voting         | ❌       | ✅           | ✅                |
| Proposal Expiry          | ❌       | ✅           | ✅ (Double-check) |
| Multi-Action Support     | ❌       | ✅           | ✅                |
| **Developer Experience** |
| Event Emissions          | ❌       | ✅ 4 Events  | ✅ 4 Events       |
| Status Tracking          | Implicit | ✅ 4 States  | ✅ 4 States       |
| Error Messages           | 5 codes  | 8 codes      | 11 codes          |
| **Gas Efficiency**       |
| Owner Lookup             | O(n)     | O(log n)     | O(log n)          |
| Duplicate Check          | N/A      | N/A          | O(n) at creation  |

---

## 🎓 Academic Contributions

This project demonstrates advanced Sui Move concepts suitable for a Distributed Systems course:

1. **Shared Object Consensus**: How multiple participants coordinate on mutable state
2. **Snapshot Isolation**: Preventing race conditions in decentralized systems
3. **Event Sourcing**: Rebuilding state from immutable event logs
4. **Byzantine Fault Tolerance**: Handling malicious actors (duplicate owners, removal attacks)
5. **Idempotent Operations**: Silent success pattern for concurrent proposal execution
6. **State Machine Design**: Explicit status transitions with invariant preservation

---

## 🚀 Next Steps (Future Versions)

Potential enhancements for v3+:

- **Weighted Voting**: Owners have different voting power
- **Proposal Delegation**: Owner A can authorize Owner B to vote on their behalf
- **Multi-Token Support**: Manage tokens beyond SUI (custom coins)
- **Batch Proposals**: Execute multiple actions atomically
- **Veto Power**: Special "admin" owner can block proposals
- **Time Locks**: Delay execution after approval (security buffer)
- **Proposal Cancellation**: Creator can cancel before threshold met
- **Gas Optimization**: Pack status/action_type into single byte

---

## 📝 License & Attribution

Developed as part of a Distributed Systems course project. Security improvements guided by Claude AI code review.

**Team**: [Arda Karahan]  
**Timeline**: 3-day sprint implementation  
**Stack**: Sui Move, React, @mysten/dapp-kit

---

## 🙏 Acknowledgments

- **Sui Foundation**: For excellent Move documentation
- **Claude AI**: For security audit and architectural recommendations
- **Mysten Labs**: For dapp-kit and developer tools
- **Course Instructor**: For the challenging project constraints

---

**Note**: This README documents the evolution of our implementation choices. Each version represents a deliberate trade-off between simplicity, security, and functionality. The "silent success" pattern in v2 is a conscious design decision, not an oversight.
