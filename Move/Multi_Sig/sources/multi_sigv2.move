module multi_sig::multisigv2;

use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;
use sui::sui::SUI;
use sui::vec_set::{Self, VecSet};

// --- Constants: Wallet Types ---
const WALLET_TYPE_PLURALITY: u8 = 0; // > 50%
const WALLET_TYPE_UNANIMITY: u8 = 1; // 100%

// --- Constants: Statuses ---
const STATUS_PENDING: u8 = 0;
const STATUS_EXECUTED: u8 = 1;
const STATUS_REJECTED: u8 = 2;
const STATUS_EXPIRED: u8 = 3;

// --- Constants: Action Types ---
const ACTION_SEND_SUI: u8 = 0;
const ACTION_ADD_OWNER: u8 = 1;
const ACTION_REMOVE_OWNER: u8 = 2;

// --- Errors ---
const ENotAnOwner: u64 = 0;
const EAlreadyVoted: u64 = 1;
const EProposalNotActive: u64 = 2;
const EProposalExpired: u64 = 3;
// const EOwnerExists: u64 = 4;     // Unused - we allow silent skip
// const EOwnerNotFound: u64 = 5;   // Unused - we allow silent skip
const EInvalidThreshold: u64 = 6;
const EInvalidWalletType: u64 = 7;
const EThresholdNotMet: u64 = 8;
const ECannotRemoveLastOwner: u64 = 9;
const EDuplicateOwner: u64 = 10;
const EInsufficientBalance: u64 = 11;

/// The main wallet object.
public struct MultisigWallet has key, store {
    id: UID,
    owners: vector<address>,
    balance: Balance<SUI>,
    wallet_type: u8,
}

/// The Proposal object with "Snapshot" security.
public struct Proposal has key, store {
    id: UID,
    wallet_id: ID,
    creator: address,
    // Action Data
    action_type: u8,
    target_address: address,
    amount: u64,
    // Security & Voting
    snapshot_owners: vector<address>,
    voters: VecSet<address>,
    approval_count: u64,
    rejection_count: u64,
    status: u8,
    expiry_ms: Option<u64>,
}

// --- Events ---
public struct WalletCreated has copy, drop {
    wallet_id: ID,
    owners: vector<address>,
    wallet_type: u8,
}

public struct ProposalCreated has copy, drop {
    proposal_id: ID,
    wallet_id: ID,
    creator: address,
    action_type: u8,
    expiry: Option<u64>,
}

public struct VoteCast has copy, drop {
    proposal_id: ID,
    voter: address,
    vote: bool,
}

public struct ProposalStatusChanged has copy, drop {
    proposal_id: ID,
    new_status: u8,
}

// --- Core Functions ---

/// Create a new wallet.
/// `wallet_type`: 0 for Plurality (51%), 1 for Unanimity (100%).
public fun create_wallet(owners: vector<address>, wallet_type: u8, ctx: &mut TxContext) {
    assert!(vector::length(&owners) > 0, EInvalidThreshold);
    assert!(
        wallet_type == WALLET_TYPE_PLURALITY || wallet_type == WALLET_TYPE_UNANIMITY,
        EInvalidWalletType,
    );

    // ✅ FIX #9: Check for Duplicate Owners
    let mut i = 0;
    let len = vector::length(&owners);
    let mut seen = vec_set::empty<address>();
    while (i < len) {
        let addr = *vector::borrow(&owners, i);
        assert!(!vec_set::contains(&seen, &addr), EDuplicateOwner);
        vec_set::insert(&mut seen, addr);
        i = i + 1;
    };

    let wallet = MultisigWallet {
        id: object::new(ctx),
        owners,
        balance: balance::zero(),
        wallet_type,
    };

    event::emit(WalletCreated {
        wallet_id: object::id(&wallet),
        owners: wallet.owners,
        wallet_type,
    });

    transfer::share_object(wallet);
}

public entry fun deposit(wallet: &mut MultisigWallet, coin: Coin<SUI>, _ctx: &mut TxContext) {
    balance::join(&mut wallet.balance, coin::into_balance(coin));
}

/// Create a proposal. Snapshots the current wallet owners into the proposal.
public fun create_proposal(
    wallet: &MultisigWallet,
    action_type: u8,
    target_address: address,
    amount: u64,
    expiry_ms: Option<u64>,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    assert!(vector::contains(&wallet.owners, &sender), ENotAnOwner);

    let proposal = Proposal {
        id: object::new(ctx),
        wallet_id: object::id(wallet),
        creator: sender,
        action_type,
        target_address,
        amount,
        snapshot_owners: wallet.owners,
        voters: vec_set::empty(),
        approval_count: 0,
        rejection_count: 0,
        status: STATUS_PENDING,
        expiry_ms,
    };

    event::emit(ProposalCreated {
        proposal_id: object::id(&proposal),
        wallet_id: object::id(wallet),
        creator: sender,
        action_type,
        expiry: expiry_ms,
    });

    transfer::share_object(proposal);
}

/// Vote on a proposal.
/// Handles logic for Unanimity vs Plurality rejection conditions.
public entry fun vote(
    wallet: &MultisigWallet,
    proposal: &mut Proposal,
    approve: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);

    assert!(proposal.status == STATUS_PENDING, EProposalNotActive);
    assert!(vector::contains(&proposal.snapshot_owners, &sender), ENotAnOwner);
    assert!(!vec_set::contains(&proposal.voters, &sender), EAlreadyVoted);

    // Expiry Check
    if (option::is_some(&proposal.expiry_ms)) {
        let deadline = *option::borrow(&proposal.expiry_ms);
        if (clock::timestamp_ms(clock) > deadline) {
            proposal.status = STATUS_EXPIRED;
            event::emit(ProposalStatusChanged {
                proposal_id: object::id(proposal),
                new_status: STATUS_EXPIRED,
            });
            abort EProposalExpired
        };
    };

    vec_set::insert(&mut proposal.voters, sender);
    event::emit(VoteCast {
        proposal_id: object::id(proposal),
        voter: sender,
        vote: approve,
    });

    if (approve) {
        proposal.approval_count = proposal.approval_count + 1;
    } else {
        proposal.rejection_count = proposal.rejection_count + 1;
    };

    let total_owners = vector::length(&proposal.snapshot_owners);

    if (wallet.wallet_type == WALLET_TYPE_UNANIMITY) {
        if (!approve) {
            proposal.status = STATUS_REJECTED;
            event::emit(ProposalStatusChanged {
                proposal_id: object::id(proposal),
                new_status: STATUS_REJECTED,
            });
        }
    } else {
        if (proposal.rejection_count > (total_owners / 2)) {
            proposal.status = STATUS_REJECTED;
            event::emit(ProposalStatusChanged {
                proposal_id: object::id(proposal),
                new_status: STATUS_REJECTED,
            });
        }
    };
}

/// Execute a proposal. Can be called by anyone.
public entry fun execute_proposal(
    wallet: &mut MultisigWallet,
    proposal: &mut Proposal,
    clock: &Clock, // ✅ FIX #8: Added Clock parameter
    ctx: &mut TxContext,
) {
    assert!(proposal.status == STATUS_PENDING, EProposalNotActive);
    assert!(object::id(wallet) == proposal.wallet_id, 0);

    // ✅ FIX #8: Expiry Check in Execution
    if (option::is_some(&proposal.expiry_ms)) {
        let deadline = *option::borrow(&proposal.expiry_ms);
        assert!(clock::timestamp_ms(clock) <= deadline, EProposalExpired);
    };

    let total_owners = vector::length(&proposal.snapshot_owners);
    let mut passed = false;

    if (wallet.wallet_type == WALLET_TYPE_UNANIMITY) {
        if (proposal.approval_count == total_owners) {
            passed = true;
        };
    } else {
        if (proposal.approval_count > (total_owners / 2)) {
            passed = true;
        };
    };

    assert!(passed, EThresholdNotMet);

    // ✅ FIX #7: Effects BEFORE Interactions (Reentrancy protection)
    proposal.status = STATUS_EXECUTED;
    event::emit(ProposalStatusChanged {
        proposal_id: object::id(proposal),
        new_status: STATUS_EXECUTED,
    });

    // Perform Action
    if (proposal.action_type == ACTION_SEND_SUI) {
        // ✅ FIX #5: Check balance before execution
        assert!(balance::value(&wallet.balance) >= proposal.amount, EInsufficientBalance);
        let coin = coin::take(&mut wallet.balance, proposal.amount, ctx);
        transfer::public_transfer(coin, proposal.target_address);
    } else if (proposal.action_type == ACTION_ADD_OWNER) {
        // Silent Success: If owner exists, do nothing but proposal is still "Executed"
        if (!vector::contains(&wallet.owners, &proposal.target_address)) {
            vector::push_back(&mut wallet.owners, proposal.target_address);
        }
    } else if (proposal.action_type == ACTION_REMOVE_OWNER) {
        let (found, index) = vector::index_of(&wallet.owners, &proposal.target_address);
        if (found) {
            // ✅ FIX #3: CRITICAL - Prevent removing last owner
            assert!(vector::length(&wallet.owners) > 1, ECannotRemoveLastOwner);
            vector::remove(&mut wallet.owners, index);
        }
    };
}

// ========================================
// GETTER FUNCTIONS - For Frontend & Tests
// ========================================

// --- Constant Getters (for tests and frontend logic) ---

/// Returns the wallet type constant for Plurality (>50% approval)
public fun wallet_type_plurality(): u8 { WALLET_TYPE_PLURALITY }

/// Returns the wallet type constant for Unanimity (100% approval)
public fun wallet_type_unanimity(): u8 { WALLET_TYPE_UNANIMITY }

/// Returns the status constant for Pending proposals
public fun status_pending(): u8 { STATUS_PENDING }

/// Returns the status constant for Executed proposals
public fun status_executed(): u8 { STATUS_EXECUTED }

/// Returns the status constant for Rejected proposals
public fun status_rejected(): u8 { STATUS_REJECTED }

/// Returns the status constant for Expired proposals
public fun status_expired(): u8 { STATUS_EXPIRED }

/// Returns the action type constant for sending SUI
public fun action_send_sui(): u8 { ACTION_SEND_SUI }

/// Returns the action type constant for adding an owner
public fun action_add_owner(): u8 { ACTION_ADD_OWNER }

/// Returns the action type constant for removing an owner
public fun action_remove_owner(): u8 { ACTION_REMOVE_OWNER }

// --- Error Code Getters (for frontend error handling) ---

public fun e_not_an_owner(): u64 { ENotAnOwner }

public fun e_already_voted(): u64 { EAlreadyVoted }

public fun e_proposal_not_active(): u64 { EProposalNotActive }

public fun e_proposal_expired(): u64 { EProposalExpired }

public fun e_invalid_threshold(): u64 { EInvalidThreshold }

public fun e_invalid_wallet_type(): u64 { EInvalidWalletType }

public fun e_threshold_not_met(): u64 { EThresholdNotMet }

public fun e_cannot_remove_last_owner(): u64 { ECannotRemoveLastOwner }

public fun e_duplicate_owner(): u64 { EDuplicateOwner }

public fun e_insufficient_balance(): u64 { EInsufficientBalance }

// --- Wallet State Getters (for frontend display) ---

/// Get the list of current wallet owners
/// Frontend use: Display owner list, check if user is owner
public fun get_wallet_owners(wallet: &MultisigWallet): vector<address> {
    wallet.owners
}

/// Get the wallet's SUI balance in MIST (1 SUI = 1,000,000,000 MIST)
/// Frontend use: Display available balance, validate proposal amounts
public fun get_wallet_balance(wallet: &MultisigWallet): u64 {
    balance::value(&wallet.balance)
}

/// Get the wallet's governance type (0 = Plurality, 1 = Unanimity)
/// Frontend use: Display governance model, calculate required approvals
public fun get_wallet_type(wallet: &MultisigWallet): u8 {
    wallet.wallet_type
}

/// Get the number of owners in the wallet
/// Frontend use: Calculate voting thresholds, display member count
public fun get_wallet_owner_count(wallet: &MultisigWallet): u64 {
    vector::length(&wallet.owners)
}

/// Check if an address is an owner of the wallet
/// Frontend use: Enable/disable UI elements based on ownership
public fun is_wallet_owner(wallet: &MultisigWallet, addr: address): bool {
    vector::contains(&wallet.owners, &addr)
}

// --- Proposal State Getters (for frontend display) ---

/// Get the wallet ID this proposal belongs to
/// Frontend use: Filter proposals by wallet
public fun get_proposal_wallet_id(proposal: &Proposal): ID {
    proposal.wallet_id
}

/// Get the address of who created the proposal
/// Frontend use: Display proposal creator
public fun get_proposal_creator(proposal: &Proposal): address {
    proposal.creator
}

/// Get the action type (0=Send, 1=AddOwner, 2=RemoveOwner)
/// Frontend use: Display proposal type badge/icon
public fun get_proposal_action_type(proposal: &Proposal): u8 {
    proposal.action_type
}

/// Get the target address (recipient for Send, owner for Add/Remove)
/// Frontend use: Display who receives funds or who's being added/removed
public fun get_proposal_target_address(proposal: &Proposal): address {
    proposal.target_address
}

/// Get the amount of SUI to send (in MIST, 0 for non-Send proposals)
/// Frontend use: Display transfer amount
public fun get_proposal_amount(proposal: &Proposal): u64 {
    proposal.amount
}

/// Get the current approval count
/// Frontend use: Show voting progress (e.g., "2/3 approvals")
public fun get_proposal_approval_count(proposal: &Proposal): u64 {
    proposal.approval_count
}

/// Get the current rejection count
/// Frontend use: Show voting progress (e.g., "1 rejection")
public fun get_proposal_rejection_count(proposal: &Proposal): u64 {
    proposal.rejection_count
}

/// Get the proposal status (0=Pending, 1=Executed, 2=Rejected, 3=Expired)
/// Frontend use: Filter proposals, show status badges
public fun get_proposal_status(proposal: &Proposal): u8 {
    proposal.status
}

/// Get the expiry timestamp in milliseconds (None if no expiry)
/// Frontend use: Display countdown timer, check if expired
public fun get_proposal_expiry(proposal: &Proposal): Option<u64> {
    proposal.expiry_ms
}

/// Get the snapshot of owners who can vote on this proposal
/// Frontend use: Display eligible voters, check voting eligibility
public fun get_proposal_snapshot_owners(proposal: &Proposal): vector<address> {
    proposal.snapshot_owners
}

/// Get the number of snapshot owners (voter count)
/// Frontend use: Calculate voting thresholds
public fun get_proposal_voter_count(proposal: &Proposal): u64 {
    vector::length(&proposal.snapshot_owners)
}

/// Check if an address has already voted on this proposal
/// Frontend use: Disable vote button if already voted
public fun has_voted(proposal: &Proposal, addr: address): bool {
    vec_set::contains(&proposal.voters, &addr)
}

/// Check if an address is eligible to vote (in snapshot)
/// Frontend use: Show/hide vote buttons based on eligibility
public fun can_vote(proposal: &Proposal, addr: address): bool {
    vector::contains(&proposal.snapshot_owners, &addr)
}

// --- Computed Helper Getters (for frontend logic) ---

/// Calculate required approvals for a proposal to pass
/// Returns the minimum number of approvals needed based on wallet type
/// Frontend use: Display "Needs X more approvals"
public fun get_required_approvals(wallet: &MultisigWallet, proposal: &Proposal): u64 {
    let total_voters = vector::length(&proposal.snapshot_owners);

    if (wallet.wallet_type == WALLET_TYPE_UNANIMITY) {
        // Unanimity: needs 100%
        total_voters
    } else {
        // Plurality: needs > 50%
        (total_voters / 2) + 1
    }
}

/// Check if a proposal can be executed right now
/// Returns true if approval threshold is met and status is pending
/// Frontend use: Enable/disable "Execute" button
public fun can_execute(wallet: &MultisigWallet, proposal: &Proposal, clock: &Clock): bool {
    // Must be pending
    if (proposal.status != STATUS_PENDING) {
        return false
    };

    // Check if expired
    if (option::is_some(&proposal.expiry_ms)) {
        let deadline = *option::borrow(&proposal.expiry_ms);
        if (clock::timestamp_ms(clock) > deadline) {
            return false
        };
    };

    // Check if threshold met
    let total_voters = vector::length(&proposal.snapshot_owners);
    if (wallet.wallet_type == WALLET_TYPE_UNANIMITY) {
        proposal.approval_count == total_voters
    } else {
        proposal.approval_count > (total_voters / 2)
    }
}

/// Check if a proposal is still active (can receive votes)
/// Frontend use: Show/hide voting UI
public fun is_proposal_active(proposal: &Proposal, clock: &Clock): bool {
    if (proposal.status != STATUS_PENDING) {
        return false
    };

    if (option::is_some(&proposal.expiry_ms)) {
        let deadline = *option::borrow(&proposal.expiry_ms);
        if (clock::timestamp_ms(clock) > deadline) {
            return false
        };
    };

    true
}

/// Get voting progress as a percentage (0-100)
/// Frontend use: Display progress bars
public fun get_approval_percentage(proposal: &Proposal): u64 {
    let total = vector::length(&proposal.snapshot_owners);
    if (total == 0) { return 0 };

    (proposal.approval_count * 100) / total
}
