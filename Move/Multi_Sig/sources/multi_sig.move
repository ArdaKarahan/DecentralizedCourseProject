module multi_sig::multisig;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;

/// The main wallet object, shared to be accessible by owners.
/// It holds the list of owners and the SUI balance.
public struct MultisigWallet has key, store {
    id: UID,
    owners: vector<address>,
    balance: Balance<SUI>,
    // The number of approvals required to execute a proposal.
    threshold: u64,
}

/// A proposal to transfer a certain amount to a recipient.
/// It is a shared object to allow owners to find and approve it.
public struct Proposal has key, store {
    id: UID,
    // The wallet this proposal belongs to.
    wallet_id: ID,
    // The address to send funds to.
    recipient: address,
    // The amount of SUI to transfer.
    amount: u64,
    // The addresses of owners who have approved this proposal.
    approvals: vector<address>,
}

// --- Errors ---
/// The sender is not an owner of the wallet.
const ENotAnOwner: u64 = 0;
/// The proposal has already been approved by this owner.
const EAlreadyApproved: u64 = 1;
/// The approval threshold has not been met.
const EThresholdNotMet: u64 = 2;
/// The owner to be added already exists.
const EOwnerExists: u64 = 3;
/// The owner to be removed does not exist.
const EOwnerNotFound: u64 = 4;
/// The threshold must be greater than 0 and less than or equal to the number of owners.
const EInvalidThreshold: u64 = 5;

/// Creates a new multi-sig wallet.
/// The initial owners and the required approval threshold are provided.
public fun create_wallet(owners: vector<address>, threshold: u64, ctx: &mut TxContext) {
    assert!(threshold > 0 && threshold <= vector::length(&owners), EInvalidThreshold);

    let wallet = MultisigWallet {
        id: object::new(ctx),
        owners,
        balance: balance::zero(),
        threshold,
    };
    transfer::share_object(wallet);
}

/// Allows anyone to deposit SUI into the wallet.
public entry fun deposit(wallet: &mut MultisigWallet, coin: Coin<SUI>, _ctx: &mut TxContext) {
    balance::join(&mut wallet.balance, coin::into_balance(coin));
}

/// Creates a new proposal to transfer SUI from the wallet.
/// Only an owner of the wallet can create a proposal.
public fun create_proposal(
    wallet: &MultisigWallet,
    recipient: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(is_owner(wallet, tx_context::sender(ctx)), ENotAnOwner);

    let proposal = Proposal {
        id: object::new(ctx),
        wallet_id: object::id(wallet),
        recipient,
        amount,
        approvals: vector::empty(),
    };
    transfer::share_object(proposal);
}

/// Approves a proposal.
/// Only an owner of the wallet can approve a proposal.
/// An owner can only approve a proposal once.
public entry fun approve_proposal(
    wallet: &MultisigWallet,
    proposal: &mut Proposal,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    assert!(is_owner(wallet, sender), ENotAnOwner);
    assert!(!has_approved(proposal, sender), EAlreadyApproved);

    vector::push_back(&mut proposal.approvals, sender);
}

/// Executes a proposal if the approval threshold has been met.
/// The SUI is transferred to the recipient and the proposal object is deleted.
public entry fun execute_proposal(
    wallet: &mut MultisigWallet,
    proposal: Proposal,
    ctx: &mut TxContext,
) {
    assert!(vector::length(&proposal.approvals) >= wallet.threshold, EThresholdNotMet);
    assert!(object::id(wallet) == proposal.wallet_id, 0); // Ensure proposal is for this wallet

    let Proposal { id, wallet_id: _, recipient, amount, approvals: _ } = proposal;
    object::delete(id);

    let coin = coin::take(&mut wallet.balance, amount, ctx);
    transfer::public_transfer(coin, recipient);
}

/// Adds a new owner to the wallet.
/// This requires the existing owners to create and approve a proposal for this action.
/// For simplicity in this implementation, we allow any existing owner to add a new one.
/// A more robust implementation would use proposals to add/remove owners.
public entry fun add_owner(wallet: &mut MultisigWallet, new_owner: address, ctx: &mut TxContext) {
    assert!(is_owner(wallet, tx_context::sender(ctx)), ENotAnOwner);
    assert!(!is_owner(wallet, new_owner), EOwnerExists);

    vector::push_back(&mut wallet.owners, new_owner);
}

/// Removes an owner from the wallet.
/// Similar to adding an owner, this is simplified and should be handled by proposals in a real-world scenario.
public entry fun remove_owner(
    wallet: &mut MultisigWallet,
    owner_to_remove: address,
    ctx: &mut TxContext,
) {
    assert!(is_owner(wallet, tx_context::sender(ctx)), ENotAnOwner);

    let (found, index) = vector::index_of(&wallet.owners, &owner_to_remove);
    assert!(found, EOwnerNotFound);

    vector::remove(&mut wallet.owners, index);
}

// --- Helper functions ---

/// Checks if an address is an owner of the wallet.
fun is_owner(wallet: &MultisigWallet, addr: address): bool {
    vector::contains(&wallet.owners, &addr)
}

/// Checks if an address has already approved a proposal.
fun has_approved(proposal: &Proposal, addr: address): bool {
    vector::contains(&proposal.approvals, &addr)
}
