#[test_only]
module academy_world_v0::world_v0_tests;

use academy_core::core::{Self, Academy, AcademyAdminCap, Quest};
use academy_rewards::badge::{Self, Badge};
use academy_test_support::world_setup as ws;
use academy_world_v0::world_v0;
use std::string::utf8;
use sui::{clock, test_scenario::{Self as ts, Scenario}};
use world::{access::OwnerCap, character::Character, network_node::NetworkNode};

const AUTHOR: address = @0xA1;
const IMAGE: vector<u8> = b"https://example.org/node.png";

fun create_node_quest(s: &mut Scenario): ID {
    s.next_tx(AUTHOR);
    let cap = core::create_academy(utf8(b"Academy"), utf8(b""), x"", s.ctx());
    let academy_id = cap.admin_academy_id();
    transfer::public_transfer(cap, AUTHOR);
    s.next_tx(AUTHOR);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let quest_id = core::create_quest(
        &mut academy,
        &cap,
        world_v0::identity(),
        vector[world_v0::node_online()],
        vector[badge::requirement(utf8(IMAGE))],
        utf8(b"ipfs://quest"),
        x"",
        s.ctx(),
    );
    s.return_to_sender(cap);
    ts::return_shared(academy);
    quest_id
}

fun setup(s: &mut Scenario): (ID, ID, ID) {
    let (character_id, nwn_id) = ws::setup_character_with_online_node(s);
    let quest_id = create_node_quest(s);
    (character_id, nwn_id, quest_id)
}

fun claim_with(
    s: &mut Scenario,
    sender: address,
    quest_id: ID,
    character_id: ID,
    nwn_id: ID,
    cap_nwn_id: ID,
) {
    s.next_tx(sender);
    let cap_nwn = s.take_shared_by_id<NetworkNode>(cap_nwn_id);
    let owner_cap_id = cap_nwn.owner_cap_id();
    ts::return_shared(cap_nwn);

    s.next_tx(sender);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<NetworkNode>>(owner_cap_id);
    let clock = clock::create_for_testing(s.ctx());
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut character = s.take_shared_by_id<Character>(character_id);
    let nwn = s.take_shared_by_id<NetworkNode>(nwn_id);

    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    let (cap, receipt) = character.borrow_owner_cap<NetworkNode>(ticket, s.ctx());
    world_v0::check_node_online(&mut t, &nwn, &cap);
    character.return_owner_cap(cap, receipt);
    let mut rt = core::complete(t, &mut quest);
    badge::issue(&mut rt, &clock, s.ctx());
    core::finish(rt);

    ts::return_shared(quest);
    ts::return_shared(character);
    ts::return_shared(nwn);
    clock.destroy_for_testing();
}

fun claim(s: &mut Scenario, sender: address, quest_id: ID, character_id: ID, nwn_id: ID) {
    claim_with(s, sender, quest_id, character_id, nwn_id, nwn_id);
}

#[test]
fun tracer_node_online_claim_issues_badge() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id, quest_id) = setup(&mut s);
    claim(&mut s, ws::user_a(), quest_id, character_id, nwn_id);

    s.next_tx(ws::user_a());
    let b = s.take_from_sender<Badge>();
    assert!(b.quest_id() == quest_id);
    assert!(b.tenant() == ws::tenant());
    assert!(b.game_id() == (ws::character_item_id() as u64));
    assert!(b.image_uri() == utf8(IMAGE));
    s.return_to_sender(b);
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.has_player_claimed(ws::tenant(), ws::character_item_id() as u64));
    assert!(quest.has_wallet_claimed(ws::user_a()));
    assert!(quest.is_evidence_used(nwn_id));
    assert!(quest.claims() == 1);
    ts::return_shared(quest);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ENotCharacterOwner)]
fun bind_foreign_character_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn_id, quest_id) = setup(&mut s);
    s.next_tx(ws::user_b());
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let character = s.take_shared_by_id<Character>(character_id);
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    abort
}

#[test, expected_failure(abort_code = core::EIdentityAlreadySet)]
fun bind_twice_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn_id, quest_id) = setup(&mut s);
    let second_id = ws::create_character(&mut s, ws::user_a(), 102);
    s.next_tx(ws::user_a());
    let quest = s.take_shared_by_id<Quest>(quest_id);
    let character = s.take_shared_by_id<Character>(character_id);
    let second = s.take_shared_by_id<Character>(second_id);
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    world_v0::bind(&mut t, &second, s.ctx());
    abort
}

#[test, expected_failure(abort_code = world_v0::ENodeOffline)]
fun offline_node_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn_id, quest_id) = setup(&mut s);
    let offline_id = ws::create_network_node(&mut s, character_id, 5001);
    claim(&mut s, ws::user_a(), quest_id, character_id, offline_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ENotAuthorized)]
fun foreign_node_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id, quest_id) = setup(&mut s);
    let other_id = ws::create_character(&mut s, ws::user_b(), 202);
    let other_nwn = ws::create_network_node(&mut s, other_id, 5002);
    ws::bring_network_node_online(&mut s, ws::user_b(), other_id, other_nwn);
    claim_with(&mut s, ws::user_a(), quest_id, character_id, other_nwn, nwn_id);
    s.end();
}

#[test, expected_failure(abort_code = core::EAlreadyClaimedByPlayer)]
fun second_claim_by_same_character_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id, quest_id) = setup(&mut s);
    claim(&mut s, ws::user_a(), quest_id, character_id, nwn_id);
    claim(&mut s, ws::user_a(), quest_id, character_id, nwn_id);
    s.end();
}

#[test, expected_failure(abort_code = core::EAlreadyClaimedByWallet)]
fun same_wallet_other_character_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id, quest_id) = setup(&mut s);
    claim(&mut s, ws::user_a(), quest_id, character_id, nwn_id);
    let second_id = ws::create_character(&mut s, ws::user_a(), 102);
    let second_nwn = ws::create_network_node(&mut s, second_id, 5003);
    ws::bring_network_node_online(&mut s, ws::user_a(), second_id, second_nwn);
    claim(&mut s, ws::user_a(), quest_id, second_id, second_nwn);
    s.end();
}

#[test, expected_failure(abort_code = core::EWrongRequirement)]
fun node_check_on_quest_without_it_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    s.next_tx(AUTHOR);
    let cap = core::create_academy(utf8(b"A"), utf8(b""), x"", s.ctx());
    let academy_id = cap.admin_academy_id();
    transfer::public_transfer(cap, AUTHOR);
    s.next_tx(AUTHOR);
    let mut academy = s.take_shared_by_id<Academy>(academy_id);
    let cap = s.take_from_sender<AcademyAdminCap>();
    let quest_id = core::create_quest(
        &mut academy,
        &cap,
        world_v0::identity(),
        vector[badge::requirement(utf8(IMAGE))],
        vector[],
        utf8(b""),
        x"",
        s.ctx(),
    );
    s.return_to_sender(cap);
    ts::return_shared(academy);
    claim(&mut s, ws::user_a(), quest_id, character_id, nwn_id);
    s.end();
}

#[test, expected_failure(abort_code = core::EEvidenceUsed)]
fun node_transferred_to_other_character_counts_once() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id, quest_id) = setup(&mut s);
    claim(&mut s, ws::user_a(), quest_id, character_id, nwn_id);

    let other_id = ws::create_character(&mut s, ws::user_b(), 202);
    s.next_tx(ws::user_a());
    let nwn = s.take_shared_by_id<NetworkNode>(nwn_id);
    let owner_cap_id = nwn.owner_cap_id();
    ts::return_shared(nwn);
    s.next_tx(ws::user_a());
    let mut character = s.take_shared_by_id<Character>(character_id);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<NetworkNode>>(owner_cap_id);
    let (cap, receipt) = character.borrow_owner_cap<NetworkNode>(ticket, s.ctx());
    world::access::transfer_owner_cap_with_receipt(cap, receipt, object::id_to_address(&other_id), s.ctx());
    ts::return_shared(character);

    claim(&mut s, ws::user_b(), quest_id, other_id, nwn_id);
    s.end();
}
