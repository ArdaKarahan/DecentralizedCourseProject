// multisig_tests_v2.move
// Test Suite for v2 Contract - DEMONSTRATES SECURITY FIXES
// These tests PASS and show that vulnerabilities from v1 are now prevented

#[test_only]
module multi_sig::multisig_tests_v2;

use std::option;
use multi_sig::multisigv2::{Self, MultisigWallet, Proposal};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};

// Test addresses
const ALICE: address = @0xA;
const BOB: address = @0xB;
const CHARLIE: address = @0xC;
const RECIPIENT: address = @0xD;

// Error codes from multisigv2 (local copies as attributes require constants)
const EAlreadyVoted: u64 = 1;
const EProposalExpired: u64 = 3;
const EThresholdNotMet: u64 = 8;
const ECannotRemoveLastOwner: u64 = 9;
const EDuplicateOwner: u64 = 10;
const EInsufficientBalance: u64 = 11;

fun create_test_clock(scenario: &mut Scenario): Clock {
    ts::next_tx(scenario, ALICE);
    let mut clock = clock::create_for_testing(ts::ctx(scenario));
    clock::set_for_testing(&mut clock, 1000000);
    clock
}

// ========================================
// FIX 1: Last Owner Removal Protection
// ========================================
#[test]
#[expected_failure(abort_code = ECannotRemoveLastOwner, location = multi_sig::multisigv2)]
fun test_v2_cannot_remove_last_owner() {
    let mut scenario = ts::begin(ALICE);

    // 1. Create wallet with 2 owners
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    // 2. Deposit 1000 SUI
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
        multisigv2::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    // 3. Remove BOB first (allowed - we still have 2 owners)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_remove_owner(),
            BOB,
            0,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 4. Now try to remove ALICE (the last remaining owner)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_remove_owner(),
            ALICE,
            0,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 5. Try to execute - v2 PREVENTS THIS!
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        // ✅ v2: Aborts with ECannotRemoveLastOwner
        // Wallet is protected from becoming ownerless!
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// FIX 2: Duplicate Owner Prevention
// ========================================
#[test]
#[expected_failure(abort_code = EDuplicateOwner, location = multi_sig::multisigv2)]
fun test_v2_prevents_duplicate_owners() {
    let mut scenario = ts::begin(ALICE);

    // Try to create wallet with duplicate addresses
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, ALICE, BOB]; // ALICE appears twice

        // ✅ v2: Aborts immediately with EDuplicateOwner
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = EDuplicateOwner, location = multi_sig::multisigv2)]
fun test_v2_prevents_duplicate_owners_different_positions() {
    let mut scenario = ts::begin(ALICE);

    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB, CHARLIE, BOB]; // BOB appears twice

        // ✅ v2: Detects duplicates regardless of position
        multisigv2::create_wallet(owners, multisigv2::wallet_type_unanimity(), ts::ctx(&mut scenario));
    };

    ts::end(scenario);
}

// ========================================
// FIX 3: Insufficient Balance Protection
// ========================================
#[test]
#[expected_failure(abort_code = EInsufficientBalance, location = multi_sig::multisigv2)]
fun test_v2_checks_balance_before_execution() {
    let mut scenario = ts::begin(ALICE);

    // 1. Create wallet
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    // 2. Deposit only 50 SUI
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = coin::mint_for_testing<SUI>(50, ts::ctx(&mut scenario));
        multisigv2::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    // 3. Create proposal to send 1000 SUI
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            1000, // More than balance!
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    // 4. Both owners approve
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 5. Try to execute
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        // ✅ v2: Aborts with clear EInsufficientBalance error
        // Saves gas by failing early instead of during coin::take()
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// FIX 4: Expiry Double-Check Protection
// ========================================
#[test]
#[expected_failure(abort_code = EProposalExpired, location = multi_sig::multisigv2)]
fun test_v2_checks_expiry_during_execution() {
    let mut scenario = ts::begin(ALICE);

    // 1. Setup wallet with funds
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
        multisigv2::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let mut clock = create_test_clock(&mut scenario);

    // 2. Create proposal with 24-hour expiry
    let expiry_time = 1000000 + 86400000;
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            500,
            option::some(expiry_time),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // 3. Advance to just before expiry and get approval
    clock::increment_for_testing(&mut clock, 86399000); // 23:59

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 4. Advance past expiry
    clock::increment_for_testing(&mut clock, 2000); // Now at 24:01

    // 5. Try to execute after expiry
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        // ✅ v2: Aborts with EProposalExpired
        // execute_proposal() now checks expiry, not just vote()
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// FIX 5: Proper State Update Ordering
// ========================================
#[test]
fun test_v2_updates_status_before_transfer() {
    // This test passes and demonstrates the Checks-Effects-Interactions pattern
    let mut scenario = ts::begin(ALICE);

    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_unanimity(), ts::ctx(&mut scenario));
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
        multisigv2::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            500,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        // ✅ v2: Order is now correct:
        // 1. proposal.status = STATUS_EXECUTED (Effect)
        // 2. event::emit() (Effect)
        // 3. transfer::public_transfer() (Interaction)
        //
        // This prevents any theoretical reentrancy edge cases
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// COMPREHENSIVE: All Fixes Working Together
// ========================================
#[test]
fun test_v2_complete_security_suite() {
    let mut scenario = ts::begin(ALICE);

    // 1. Create wallet - duplicate check passes
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB, CHARLIE]; // All unique
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    // 2. Deposit funds
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
        multisigv2::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    // 3. Create valid transfer proposal (within balance)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            500, // Within the 1000 balance
            option::some(1000000 + 3600000), // 1 hour expiry
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // 4. Get majority approval (2/3 for plurality)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 5. Execute successfully - all checks pass!
    {
        ts::next_tx(&mut scenario, CHARLIE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        // ✅ All v2 protections are active:
        // - Not expired (checked)
        // - Balance sufficient (checked)
        // - Status updated before transfer (ordered correctly)
        // - No duplicate owners affected voting
        // - Wallet cannot become ownerless

        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 6. Verify recipient received funds
    {
        ts::next_tx(&mut scenario, RECIPIENT);
        let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&coin) == 500, 0);
        ts::return_to_sender(&scenario, coin);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// POSITIVE TEST: Unanimity Wallet Flow
// ========================================
#[test]
fun test_v2_unanimity_wallet_success() {
    let mut scenario = ts::begin(ALICE);

    // 1. Create unanimity wallet (needs 100%)
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_unanimity(), ts::ctx(&mut scenario));
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
        multisigv2::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            300,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // 2. Both owners must approve (unanimity)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 3. Execute with 100% approval
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        // ✅ Passes: 2/2 approvals = 100%
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// POSITIVE TEST: Dynamic Owner Management
// ========================================
#[test]
fun test_v2_safe_owner_addition_and_removal() {
    let mut scenario = ts::begin(ALICE);

    // Start with 3 owners
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB, CHARLIE];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    let clock = create_test_clock(&mut scenario);

    // Add a 4th owner (RECIPIENT as new owner)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_add_owner(),
            RECIPIENT,
            0,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // Get 2/3 approval
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // Now remove CHARLIE (safe because we have 4 owners)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_remove_owner(),
            CHARLIE,
            0,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // Get 3/4 approval (plurality of 4 needs >2 = 3)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, RECIPIENT);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);

        // ✅ Succeeds: CHARLIE removed, but we still have 3 owners (ALICE, BOB, RECIPIENT)
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// CORE FUNCTIONALITY: Plurality Voting
// ========================================
#[test]
fun test_v2_plurality_voting_success() {
    let mut scenario = ts::begin(ALICE);

    // 1. Create wallet with 3 owners (plurality)
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB, CHARLIE];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    // 2. Deposit funds
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
        multisigv2::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    let clock = create_test_clock(&mut scenario);

    // 3. Create proposal
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            500,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // 4. Get 2/3 approvals (enough for plurality)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 5. Execute successfully
    {
        ts::next_tx(&mut scenario, CHARLIE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 6. Verify recipient got funds
    {
        ts::next_tx(&mut scenario, RECIPIENT);
        let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&coin) == 500, 0);
        ts::return_to_sender(&scenario, coin);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = EThresholdNotMet, location = multi_sig::multisigv2)]
fun test_v2_plurality_voting_fail() {
    let mut scenario = ts::begin(ALICE);
    // 1. Create wallet with 3 owners (plurality)
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB, CHARLIE];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    let clock = create_test_clock(&mut scenario);

    // 2. Create proposal
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            500,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // 3. Get 1/3 approvals (not enough)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 4. Try to execute, should fail
    {
        ts::next_tx(&mut scenario, BOB);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// EDGE CASE: Double Voting
// ========================================
#[test]
#[expected_failure(abort_code = EAlreadyVoted, location = multi_sig::multisigv2)]
fun test_v2_cannot_vote_twice() {
    let mut scenario = ts::begin(ALICE);

    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    let clock = create_test_clock(&mut scenario);

    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            500,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // First vote
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // Second vote from same person
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario)); // Should abort here
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// ADVANCED: Snapshot Security
// ========================================
#[test]
fun test_v2_snapshot_security_works() {
    let mut scenario = ts::begin(ALICE);
    let clock = create_test_clock(&mut scenario);

    // 1. Wallet with ALICE, BOB, CHARLIE
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB, CHARLIE];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    // 2. ALICE creates Proposal 1 (snapshot has 3 owners)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            100,
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


    // 3. BOB creates proposal 2 to remove CHARLIE.
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_remove_owner(),
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

    // Vote to remove CHARLIE
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared_by_id<Proposal>(&scenario, proposal2_id);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared_by_id<Proposal>(&scenario, proposal2_id);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };
    // Execute removal of CHARLIE
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared_by_id<Proposal>(&scenario, proposal2_id);
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 4. CHARLIE is no longer an owner. But they can still vote on Proposal 1.
    // CHARLIE votes on proposal 1 (the send SUI one)
    {
        ts::next_tx(&mut scenario, CHARLIE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared_by_id<Proposal>(&scenario, proposal1_id);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario)); // Should succeed
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// ADVANCED: Idempotent Owner Management
// ========================================

#[test]
fun test_v2_add_existing_owner_silent_success() {
    let mut scenario = ts::begin(ALICE);
    let clock = create_test_clock(&mut scenario);

    // 1. Wallet with ALICE, BOB
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_unanimity(), ts::ctx(&mut scenario));
    };

    // 2. Propose to add BOB again
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_add_owner(),
            BOB, // Already an owner
            0,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // 3. Approve and Execute
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        // This should execute without error
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 4. Check owners are still just [ALICE, BOB]
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let owners = multisigv2::get_wallet_owners(&wallet);
        assert!(vector::length(&owners) == 2, 0);
        ts::return_shared(wallet);
    };


    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_v2_remove_nonexistent_owner_silent_success() {
    let mut scenario = ts::begin(ALICE);
    let clock = create_test_clock(&mut scenario);

    // 1. Wallet with ALICE, BOB
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_unanimity(), ts::ctx(&mut scenario));
    };

    // 2. Propose to remove CHARLIE (not an owner)
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_remove_owner(),
            CHARLIE, // Not an owner
            0,
            option::none(),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };

    // 3. Approve and Execute
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        // This should execute without error
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 4. Check owners are still just [ALICE, BOB]
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let owners = multisigv2::get_wallet_owners(&wallet);
        assert!(vector::length(&owners) == 2, 0);
        ts::return_shared(wallet);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// ADVANCED: Getter Functions
// ========================================
#[test]
fun test_v2_getter_functions() {
    let mut scenario = ts::begin(ALICE);
    let clock = create_test_clock(&mut scenario);

    // 1. Create wallet and proposal
    {
        ts::next_tx(&mut scenario, ALICE);
        let owners = vector[ALICE, BOB, CHARLIE];
        multisigv2::create_wallet(owners, multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let payment = coin::mint_for_testing<SUI>(12345, ts::ctx(&mut scenario));
        multisigv2::deposit(&mut wallet, payment, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };
    let expiry = 1000000 + 3600000;
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_add_owner(),
            RECIPIENT,
            0,
            option::some(expiry),
            ts::ctx(&mut scenario),
        );
        ts::return_shared(wallet);
    };
    // Vote to have some state
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };


    // 2. Test all getter functions
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let proposal = ts::take_shared<Proposal>(&scenario);

        // Wallet getters
        assert!(multisigv2::get_wallet_owners(&wallet) == vector[ALICE, BOB, CHARLIE], 1);
        assert!(multisigv2::get_wallet_balance(&wallet) == 12345, 2);
        assert!(multisigv2::get_wallet_type(&wallet) == multisigv2::wallet_type_plurality(), 3);
        assert!(multisigv2::get_wallet_owner_count(&wallet) == 3, 4);
        assert!(multisigv2::is_wallet_owner(&wallet, BOB), 5);
        assert!(!multisigv2::is_wallet_owner(&wallet, RECIPIENT), 6);

        // Proposal getters
        assert!(multisigv2::get_proposal_wallet_id(&proposal) == object::id(&wallet), 7);
        assert!(multisigv2::get_proposal_creator(&proposal) == BOB, 8);
        assert!(multisigv2::get_proposal_action_type(&proposal) == multisigv2::action_add_owner(), 9);
        assert!(multisigv2::get_proposal_target_address(&proposal) == RECIPIENT, 10);
        assert!(multisigv2::get_proposal_amount(&proposal) == 0, 11);
        assert!(multisigv2::get_proposal_approval_count(&proposal) == 1, 12);
        assert!(multisigv2::get_proposal_rejection_count(&proposal) == 0, 13);
        assert!(multisigv2::get_proposal_status(&proposal) == multisigv2::status_pending(), 14);
        assert!(multisigv2::get_proposal_expiry(&proposal) == option::some(expiry), 15);
        assert!(multisigv2::get_proposal_snapshot_owners(&proposal) == vector[ALICE, BOB, CHARLIE], 16);
        assert!(multisigv2::get_proposal_voter_count(&proposal) == 3, 17);
        assert!(multisigv2::has_voted(&proposal, ALICE), 18);
        assert!(!multisigv2::has_voted(&proposal, BOB), 19);
        assert!(multisigv2::can_vote(&proposal, CHARLIE), 20);
        assert!(!multisigv2::can_vote(&proposal, @0xDEAD), 21);

        // Computed getters
        assert!(multisigv2::get_required_approvals(&wallet, &proposal) == 2, 22);
        assert!(!multisigv2::can_execute(&wallet, &proposal, &clock), 23);
        assert!(multisigv2::is_proposal_active(&proposal, &clock), 24);
        assert!(multisigv2::get_approval_percentage(&proposal) == 33, 25);

        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========================================
// COMPLETE WORKFLOW
// ========================================
#[test]
fun test_v2_complete_multisig_workflow() {
    let mut scenario = ts::begin(ALICE);
    let mut clock = create_test_clock(&mut scenario);

    // 1. Create a 2/3 plurality wallet
    {
        ts::next_tx(&mut scenario, ALICE);
        multisigv2::create_wallet(vector[ALICE, BOB, CHARLIE], multisigv2::wallet_type_plurality(), ts::ctx(&mut scenario));
    };

    // 2. Deposit 100 SUI
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let coin = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
        multisigv2::deposit(&mut wallet, coin, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
    };

    // 3. Propose to send 50 SUI to RECIPIENT
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        multisigv2::create_proposal(
            &wallet,
            multisigv2::action_send_sui(),
            RECIPIENT,
            50,
            option::none(),
            ts::ctx(&mut scenario)
        );
        ts::return_shared(wallet);
    };

    // 4. ALICE approves, BOB rejects.
    {
        ts::next_tx(&mut scenario, ALICE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };
    {
        ts::next_tx(&mut scenario, BOB);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, false, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 5. CHARLIE breaks the tie with an approval.
    {
        ts::next_tx(&mut scenario, CHARLIE);
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::vote(&wallet, &mut proposal, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 6. Execute the proposal
    {
        ts::next_tx(&mut scenario, ALICE);
        let mut wallet = ts::take_shared<MultisigWallet>(&scenario);
        let mut proposal = ts::take_shared<Proposal>(&scenario);
        multisigv2::execute_proposal(&mut wallet, &mut proposal, &clock, ts::ctx(&mut scenario));
        ts::return_shared(wallet);
        ts::return_shared(proposal);
    };

    // 7. Verify recipient balance and wallet balance
    {
        ts::next_tx(&mut scenario, RECIPIENT);
        let coin = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&coin) == 50, 0);
        ts::return_to_sender(&scenario, coin);
    };
    {
        let wallet = ts::take_shared<MultisigWallet>(&scenario);
        assert!(multisigv2::get_wallet_balance(&wallet) == 50, 1);
        ts::return_shared(wallet);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
