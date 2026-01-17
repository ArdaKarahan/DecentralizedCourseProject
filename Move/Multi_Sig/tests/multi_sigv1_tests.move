// multisigv1_tests.move
// Test Suite for v1 Contract - DEMONSTRATES VULNERABILITIES
// These tests show the security gaps that v2 fixes
// Expected behavior: Tests fail or exhibit dangerous behavior

#[test_only]
module multi_sig::multisigv1_tests;

use multi_sig::multisigv1::{Self, MultisigWallet, Proposal};
use std::option;
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};

// Test addresses
const ALICE: address = @0xA;
const BOB: address = @0xB;
const CHARLIE: address = @0xC;
const RECIPIENT: address = @0xD;

// Helper: Create test clock at timestamp 1000 seconds
fun create_test_clock(scenario: &mut Scenario): Clock {
    ts::next_tx(scenario, ALICE);
    let mut clock = clock::create_for_testing(ts::ctx(scenario));
    clock::set_for_testing(&mut clock, 1000000); // 1000 seconds in ms
    clock
}

// Helper: Mint test SUI coins
fun mint_sui(amount: u64, scenario: &mut Scenario): Coin<SUI> {
    coin::mint_for_testing<SUI>(amount, ts::ctx(scenario))
}

// ========================================
// VULNERABILITY 1: Last Owner Removal (CRITICAL)
// ========================================

#[test]
fun test_v1_remove_last_owner_locks_wallet() {
    let mut scenario = ts::begin(ALICE);

    // Setup: Create 2-owner wallet with funds
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv1::create_wallet(
            owners,
            multisigv1::wallet_type_plurality(),
            ts::ctx(&mut scenario),
        );
    };

    // Deposit 1000 SUI
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = mint_sui(1000_000_000_000, &mut scenario); // 1000 SUI in MIST
        multisigv1::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    // Step 1: Remove BOB (allowed - still have 2 owners)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv1::create_proposal(
            &wallet,
            multisigv1::action_remove_owner(),
            BOB,
            0,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // Both approve
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // Execute - BOB removed
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        // Verify: Now only ALICE remains
        let owner_count = multisigv1::get_wallet_owner_count(&wallet);
        assert!(owner_count == 1, 0);

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // Step 2: Create proposal to remove ALICE (the LAST owner!)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv1::create_proposal(
            &wallet,
            multisigv1::action_remove_owner(),
            ALICE,
            0,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // ALICE votes yes (100% for 1 owner)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // ⚠️ VULNERABILITY: v1 allows removing the last owner!
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        multisigv1::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        // DANGER: Wallet now has 0 owners, 1000 SUI locked forever!
        let owner_count = multisigv1::get_wallet_owner_count(&wallet);
        assert!(owner_count == 0, 1); // This succeeds in v1 - BAD!

        let balance = multisigv1::get_wallet_balance(&wallet);
        assert!(balance == 1000_000_000_000, 2); // Funds trapped!

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// VULNERABILITY 2: Duplicate Owners (CRITICAL)
// ========================================

#[test]
fun test_v1_accepts_duplicate_owners() {
    let mut scenario = ts::begin(ALICE);

    // ⚠️ VULNERABILITY: v1 accepts duplicate addresses!
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, ALICE, BOB]; // ALICE appears twice!

        // This succeeds in v1 (should fail!)
        multisigv1::create_wallet(
            owners,
            multisigv1::wallet_type_plurality(),
            ts::ctx(&mut scenario),
        );
    };

    // Verify the wallet was created with duplicates
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);

        let owners = multisigv1::get_wallet_owners(&wallet);
        let owner_count = multisigv1::get_wallet_owner_count(&wallet);

        // Wallet has 3 "owners" but only 2 unique addresses
        assert!(owner_count == 3, 0); // v1 counts duplicates
        assert!(vector::length(&owners) == 3, 1);

        ts::return_shared(wallet);
    };

    ts::end(scenario);
}

// ========================================
// VULNERABILITY 3: Insufficient Balance (MAJOR)
// ========================================

#[test]
#[expected_failure] // Fails during execution, wasting voter gas
fun test_v1_insufficient_balance_no_early_check() {
    let mut scenario = ts::begin(ALICE);

    // Create wallet
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv1::create_wallet(
            owners,
            multisigv1::wallet_type_plurality(),
            ts::ctx(&mut scenario),
        );
    };

    // Deposit only 50 SUI
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = mint_sui(50_000_000_000, &mut scenario); // 50 SUI
        multisigv1::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    // ⚠️ VULNERABILITY: Can create proposal for 1000 SUI (more than balance!)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);

        // v1 accepts this proposal without checking balance
        multisigv1::create_proposal(
            &wallet,
            multisigv1::action_send_sui(),
            RECIPIENT,
            1000_000_000_000, // 1000 SUI - way more than 50!
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // Both owners vote yes (wasting gas on a doomed proposal)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // ⚠️ Execution fails here with generic error (not clear why)
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        // Fails inside coin::take() - unclear error message
        multisigv1::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// VULNERABILITY 4: Expiry Race Condition (MAJOR)
// ========================================

#[test]
fun test_v1_executes_after_expiry() {
    let mut scenario = ts::begin(ALICE);

    // Create wallet with funds
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv1::create_wallet(
            owners,
            multisigv1::wallet_type_plurality(),
            ts::ctx(&mut scenario),
        );
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = mint_sui(1000_000_000_000, &mut scenario);
        multisigv1::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let mut clock = create_test_clock(&mut scenario);

    // Create proposal with 24-hour expiry (86400000 ms)
    let expiry_time = 1000000 + 86400000;
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv1::create_proposal(
            &wallet,
            multisigv1::action_send_sui(),
            RECIPIENT,
            500_000_000_000, // 500 SUI
            option::some(expiry_time),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // Advance clock to 23:59 (just before expiry)
    clock::increment_for_testing(&mut clock, 86399000);

    // ALICE votes
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // BOB votes
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // Advance clock to 24:01 (AFTER expiry)
    clock::increment_for_testing(&mut clock, 2000);

    // ⚠️ VULNERABILITY: v1 executes even though proposal expired!
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        // This succeeds in v1 - expired proposal executes!
        multisigv1::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        // Funds were transferred even though time limit passed
        let status = multisigv1::get_proposal_status(&proposal);
        assert!(status == multisigv1::status_executed(), 0);

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // Verify RECIPIENT got the funds (even though proposal expired)
    {
        ts::next_tx(&mut scenario, RECIPIENT);
        let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&coin) == 500_000_000_000, 1);
        ts::return_to_sender(&scenario, coin);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// VULNERABILITY 5: State Update After Interaction (MEDIUM)
// ========================================

#[test]
fun test_v1_updates_status_after_transfer() {
    // This test documents the wrong ordering pattern in v1
    // While Sui prevents traditional reentrancy, updating state
    // after external calls is bad practice

    let mut scenario = ts::begin(ALICE);

    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv1::create_wallet(
            owners,
            multisigv1::wallet_type_unanimity(),
            ts::ctx(&mut scenario),
        );
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = mint_sui(1000_000_000_000, &mut scenario);
        multisigv1::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv1::create_proposal(
            &wallet,
            multisigv1::action_send_sui(),
            RECIPIENT,
            500_000_000_000,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // ⚠️ In v1: Execution order is:
    // 1. coin::take() - external interaction
    // 2. transfer::public_transfer() - external interaction
    // 3. proposal.status = EXECUTED - state update
    //
    // This violates Checks-Effects-Interactions pattern
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        multisigv1::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// POSITIVE TEST: v1 Features That Work
// ========================================

#[test]
fun test_v1_snapshot_security_works() {
    // This test shows that snapshot security DOES work in v1
    let mut scenario = ts::begin(ALICE);

    // Create 3-owner wallet
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB, CHARLIE];
        multisigv1::create_wallet(
            owners,
            multisigv1::wallet_type_plurality(),
            ts::ctx(&mut scenario),
        );
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = mint_sui(1000_000_000_000, &mut scenario);
        multisigv1::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    // Proposal 1: Send funds (created when all 3 are owners)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv1::create_proposal(
            &wallet,
            multisigv1::action_send_sui(),
            RECIPIENT,
            100_000_000_000,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };
    
    let proposal1_id = {
        ts::next_tx(&mut scenario, ALICE);
        let proposal = ts::take_shared<Proposal>(&scenario);
        let id = object::id(&proposal);
        ts::return_shared(proposal);
        id
    };

    // Proposal 2: Remove CHARLIE
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv1::create_proposal(
            &wallet,
            multisigv1::action_remove_owner(),
            CHARLIE,
            0,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };
    
    let proposal2_id = {
        ts::next_tx(&mut scenario, BOB);
        let proposal = ts::take_shared<Proposal>(&scenario);
        let id = object::id(&proposal);
        ts::return_shared(proposal);
        id
    };

    // Execute Proposal 2 first (remove CHARLIE)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared_by_id<Proposal>(
            &scenario,
            proposal2_id,
        );
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared_by_id<Proposal>(
            &scenario,
            proposal2_id,
        );
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared_by_id<Proposal>(
            &scenario,
            proposal2_id,
        );
        multisigv1::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        // CHARLIE is now removed from wallet
        let is_owner = multisigv1::is_wallet_owner(&wallet, CHARLIE);
        assert!(!is_owner, 0);

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // ✅ SNAPSHOT SECURITY: CHARLIE can still vote on Proposal 1!
    {
        ts::next_tx(&mut scenario, CHARLIE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared_by_id<Proposal>(
            &scenario,
            proposal1_id,
        );

        // CHARLIE is in the snapshot, even though removed from wallet
        let can_vote = multisigv1::can_vote(&proposal, CHARLIE);
        assert!(can_vote, 1);

        // Vote succeeds!
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_v1_unanimity_voting_works() {
    let mut scenario = ts::begin(ALICE);

    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv1::create_wallet(
            owners,
            multisigv1::wallet_type_unanimity(),
            ts::ctx(&mut scenario),
        );
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = mint_sui(1000_000_000_000, &mut scenario);
        multisigv1::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv1::create_proposal(
            &wallet,
            multisigv1::action_send_sui(),
            RECIPIENT,
            300_000_000_000,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // ALICE votes yes
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // ✅ BOB votes NO - Unanimity requires 100%, one rejection kills it
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv1::vote(&wallet, &mut proposal, false, &clock, ts::ctx(&mut scenario));

        // Proposal immediately rejected
        let status = multisigv1::get_proposal_status(&proposal);
        assert!(status == multisigv1::status_rejected(), 0);

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}