#[test_only]
module academy_world_v0::world_v0_checks_tests;

use academy_core::core::{Self, Academy, AcademyAdminCap, ClaimTicket, Quest, Requirement};
use academy_rewards::badge;
use academy_test_support::world_setup as ws;
use academy_world_v0::world_v0;
use std::string::utf8;
use sui::{clock, test_scenario::{Self as ts, Scenario}};
use world::{
    access::OwnerCap,
    character::Character,
    gate::Gate,
    killmail::Killmail,
    storage_unit::StorageUnit,
    turret::Turret
};

const AUTHOR: address = @0xA1;
const IMAGE: vector<u8> = b"https://example.org/check.png";
const SSU_ITEM: u64 = 7001;
const GATE_ITEM: u64 = 7002;
const TURRET_ITEM: u64 = 7003;
const KILL_TS: u64 = 1_700_000_000;
const TRIBE: u32 = 777;

fun create_quest_with(s: &mut Scenario, check: Requirement): ID {
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
        vector[check],
        vector[badge::requirement(utf8(IMAGE))],
        utf8(b"ipfs://quest"),
        x"",
        s.ctx(),
    );
    s.return_to_sender(cap);
    ts::return_shared(academy);
    quest_id
}

fun finish_claim(t: ClaimTicket, quest: &mut Quest, s: &mut Scenario) {
    let clock = clock::create_for_testing(s.ctx());
    let mut rt = core::complete(t, quest);
    badge::issue(&mut rt, &clock, s.ctx());
    core::finish(rt);
    clock.destroy_for_testing();
}

fun assert_evidence(s: &mut Scenario, quest_id: ID, evidence: ID) {
    s.next_tx(ws::user_a());
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.claims() == 1);
    assert!(quest.is_evidence_used(evidence));
    ts::return_shared(quest);
}

fun claim_storage_unit(
    s: &mut Scenario,
    sender: address,
    quest_id: ID,
    character_id: ID,
    target: ID,
    cap_of: ID,
) {
    s.next_tx(sender);
    let su = s.take_shared_by_id<StorageUnit>(cap_of);
    let owner_cap_id = su.owner_cap_id();
    ts::return_shared(su);

    s.next_tx(sender);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<StorageUnit>>(owner_cap_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut character = s.take_shared_by_id<Character>(character_id);
    let su = s.take_shared_by_id<StorageUnit>(target);
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    let (cap, receipt) = character.borrow_owner_cap<StorageUnit>(ticket, s.ctx());
    world_v0::check_storage_unit_online(&mut t, &su, &cap);
    character.return_owner_cap(cap, receipt);
    finish_claim(t, &mut quest, s);
    ts::return_shared(quest);
    ts::return_shared(character);
    ts::return_shared(su);
}

fun claim_gate(s: &mut Scenario, quest_id: ID, character_id: ID, gate_id: ID) {
    s.next_tx(ws::user_a());
    let g = s.take_shared_by_id<Gate>(gate_id);
    let owner_cap_id = g.owner_cap_id();
    ts::return_shared(g);

    s.next_tx(ws::user_a());
    let ticket = ts::receiving_ticket_by_id<OwnerCap<Gate>>(owner_cap_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut character = s.take_shared_by_id<Character>(character_id);
    let g = s.take_shared_by_id<Gate>(gate_id);
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    let (cap, receipt) = character.borrow_owner_cap<Gate>(ticket, s.ctx());
    world_v0::check_gate_online(&mut t, &g, &cap);
    character.return_owner_cap(cap, receipt);
    finish_claim(t, &mut quest, s);
    ts::return_shared(quest);
    ts::return_shared(character);
    ts::return_shared(g);
}

fun claim_turret(s: &mut Scenario, quest_id: ID, character_id: ID, turret_id: ID) {
    s.next_tx(ws::user_a());
    let tr = s.take_shared_by_id<Turret>(turret_id);
    let owner_cap_id = tr.owner_cap_id();
    ts::return_shared(tr);

    s.next_tx(ws::user_a());
    let ticket = ts::receiving_ticket_by_id<OwnerCap<Turret>>(owner_cap_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut character = s.take_shared_by_id<Character>(character_id);
    let tr = s.take_shared_by_id<Turret>(turret_id);
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    let (cap, receipt) = character.borrow_owner_cap<Turret>(ticket, s.ctx());
    world_v0::check_turret_online(&mut t, &tr, &cap);
    character.return_owner_cap(cap, receipt);
    finish_claim(t, &mut quest, s);
    ts::return_shared(quest);
    ts::return_shared(character);
    ts::return_shared(tr);
}

#[test]
fun storage_unit_online_claim_records_evidence() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = ws::setup_online_storage_unit(&mut s, ws::user_a(), character_id, nwn_id, SSU_ITEM);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_storage_unit()));
    claim_storage_unit(&mut s, ws::user_a(), quest_id, character_id, su_id, su_id);
    assert_evidence(&mut s, quest_id, su_id);
    s.end();
}

#[test]
fun gate_online_claim_records_evidence() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let gate_id = ws::setup_online_gate(&mut s, character_id, nwn_id, GATE_ITEM);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_gate()));
    claim_gate(&mut s, quest_id, character_id, gate_id);
    assert_evidence(&mut s, quest_id, gate_id);
    s.end();
}

#[test]
fun turret_online_claim_records_evidence() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let turret_id = ws::setup_online_turret(&mut s, ws::user_a(), character_id, nwn_id, TURRET_ITEM);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_turret()));
    claim_turret(&mut s, quest_id, character_id, turret_id);
    assert_evidence(&mut s, quest_id, turret_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EAssemblyOffline)]
fun offline_storage_unit_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = ws::create_storage_unit(&mut s, character_id, nwn_id, SSU_ITEM);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_storage_unit()));
    claim_storage_unit(&mut s, ws::user_a(), quest_id, character_id, su_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EAssemblyOffline)]
fun offline_gate_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let gate_id = ws::create_gate(&mut s, character_id, nwn_id, GATE_ITEM);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_gate()));
    claim_gate(&mut s, quest_id, character_id, gate_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EAssemblyOffline)]
fun offline_turret_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let turret_id = ws::create_turret(&mut s, character_id, nwn_id, TURRET_ITEM);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_turret()));
    claim_turret(&mut s, quest_id, character_id, turret_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EAssemblyNotAuthorized)]
fun foreign_storage_unit_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let own_su = ws::create_storage_unit(&mut s, character_id, nwn_id, SSU_ITEM);
    let other_id = ws::create_character(&mut s, ws::user_b(), 202);
    let other_nwn = ws::create_network_node(&mut s, other_id, 5002);
    ws::bring_network_node_online(&mut s, ws::user_b(), other_id, other_nwn);
    let other_su = ws::setup_online_storage_unit(&mut s, ws::user_b(), other_id, other_nwn, 7101);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_storage_unit()));
    claim_storage_unit(&mut s, ws::user_a(), quest_id, character_id, other_su, own_su);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EWrongAssemblyKind)]
fun storage_unit_for_gate_quest_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = ws::setup_online_storage_unit(&mut s, ws::user_a(), character_id, nwn_id, SSU_ITEM);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_gate()));
    claim_storage_unit(&mut s, ws::user_a(), quest_id, character_id, su_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EWrongAssemblyKind)]
fun turret_for_storage_unit_quest_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let turret_id = ws::setup_online_turret(&mut s, ws::user_a(), character_id, nwn_id, TURRET_ITEM);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_storage_unit()));
    claim_turret(&mut s, quest_id, character_id, turret_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EInvalidAssemblyKind)]
fun assembly_online_kind_zero_rejected() {
    let _ = world_v0::assembly_online(0);
}

#[test, expected_failure(abort_code = world_v0::EInvalidAssemblyKind)]
fun assembly_online_unknown_kind_rejected() {
    let _ = world_v0::assembly_online(4);
}

#[test, expected_failure(abort_code = core::EEvidenceUsed)]
fun storage_unit_transferred_to_other_character_counts_once() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = ws::setup_online_storage_unit(&mut s, ws::user_a(), character_id, nwn_id, SSU_ITEM);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_storage_unit()));
    claim_storage_unit(&mut s, ws::user_a(), quest_id, character_id, su_id, su_id);

    let other_id = ws::create_character(&mut s, ws::user_b(), 202);
    s.next_tx(ws::user_a());
    let su = s.take_shared_by_id<StorageUnit>(su_id);
    let owner_cap_id = su.owner_cap_id();
    ts::return_shared(su);
    s.next_tx(ws::user_a());
    let mut character = s.take_shared_by_id<Character>(character_id);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<StorageUnit>>(owner_cap_id);
    let (cap, receipt) = character.borrow_owner_cap<StorageUnit>(ticket, s.ctx());
    world::access::transfer_owner_cap_with_receipt(cap, receipt, object::id_to_address(&other_id), s.ctx());
    ts::return_shared(character);

    claim_storage_unit(&mut s, ws::user_b(), quest_id, other_id, su_id, su_id);
    s.end();
}

fun claim_kill(s: &mut Scenario, quest_id: ID, character_id: ID, killmail_id: ID) {
    s.next_tx(ws::user_a());
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let character = s.take_shared_by_id<Character>(character_id);
    let km = s.take_shared_by_id<Killmail>(killmail_id);
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    world_v0::check_kill(&mut t, &km);
    finish_claim(t, &mut quest, s);
    ts::return_shared(quest);
    ts::return_shared(character);
    ts::return_shared(km);
}

#[test]
fun kill_claim_records_evidence() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    let killer = ws::character_item_id() as u64;
    let km = ws::create_killmail(&mut s, character_id, 9001, killer, 555, KILL_TS);
    let quest_id = create_quest_with(&mut s, world_v0::kill(KILL_TS));
    claim_kill(&mut s, quest_id, character_id, km);
    assert_evidence(&mut s, quest_id, km);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ENotKiller)]
fun killmail_where_player_is_victim_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    let player = ws::character_item_id() as u64;
    let km = ws::create_killmail(&mut s, character_id, 9001, 555, player, KILL_TS);
    let quest_id = create_quest_with(&mut s, world_v0::kill(0));
    claim_kill(&mut s, quest_id, character_id, km);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ENotKiller)]
fun killmail_from_other_tenant_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    let reporter = ws::create_character_in_tenant(&mut s, ws::user_b(), 303, utf8(b"OTHER"));
    let km = ws::create_killmail(&mut s, reporter, 9001, ws::character_item_id() as u64, 555, KILL_TS);
    let quest_id = create_quest_with(&mut s, world_v0::kill(0));
    claim_kill(&mut s, quest_id, character_id, km);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ESelfKill)]
fun killmail_where_player_killed_self_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    let player = ws::character_item_id() as u64;
    let km = ws::create_killmail(&mut s, character_id, 9001, player, player, KILL_TS);
    let quest_id = create_quest_with(&mut s, world_v0::kill(0));
    claim_kill(&mut s, quest_id, character_id, km);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EKillTooOld)]
fun killmail_older_than_min_ts_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    let km = ws::create_killmail(&mut s, character_id, 9001, ws::character_item_id() as u64, 555, KILL_TS);
    let quest_id = create_quest_with(&mut s, world_v0::kill(KILL_TS + 1));
    claim_kill(&mut s, quest_id, character_id, km);
    s.end();
}

fun claim_tribe(s: &mut Scenario, quest_id: ID, character_id: ID, presented_id: ID) {
    s.next_tx(ws::user_a());
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let character = s.take_shared_by_id<Character>(character_id);
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    if (presented_id == character_id) {
        world_v0::check_in_tribe(&mut t, &character);
    } else {
        let presented = s.take_shared_by_id<Character>(presented_id);
        world_v0::check_in_tribe(&mut t, &presented);
        ts::return_shared(presented);
    };
    finish_claim(t, &mut quest, s);
    ts::return_shared(quest);
    ts::return_shared(character);
}

#[test]
fun in_tribe_claim_succeeds() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    ws::set_tribe(&mut s, character_id, TRIBE);
    let quest_id = create_quest_with(&mut s, world_v0::in_tribe(TRIBE));
    claim_tribe(&mut s, quest_id, character_id, character_id);
    s.next_tx(ws::user_a());
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.claims() == 1);
    ts::return_shared(quest);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EWrongTribe)]
fun wrong_tribe_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    let quest_id = create_quest_with(&mut s, world_v0::in_tribe(TRIBE));
    claim_tribe(&mut s, quest_id, character_id, character_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ECharacterMismatch)]
fun foreign_character_in_tribe_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    let other_id = ws::create_character(&mut s, ws::user_b(), 202);
    ws::set_tribe(&mut s, other_id, TRIBE);
    let quest_id = create_quest_with(&mut s, world_v0::in_tribe(TRIBE));
    claim_tribe(&mut s, quest_id, character_id, other_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EInvalidTribe)]
fun in_tribe_zero_rejected() {
    let _ = world_v0::in_tribe(0);
}
