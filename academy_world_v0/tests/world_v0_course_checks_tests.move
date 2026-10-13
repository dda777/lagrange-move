#[test_only]
module academy_world_v0::world_v0_course_checks_tests;

use academy_core::core::{Self, Academy, AcademyAdminCap, ClaimTicket, Quest, Requirement};
use academy_rewards::badge;
use academy_test_support::world_setup as ws;
use academy_world_v0::world_v0;
use std::string::utf8;
use sui::{clock, test_scenario::{Self as ts, Scenario}};
use world::{
    access::OwnerCap,
    assembly::Assembly,
    character::Character,
    location::LocationRegistry,
    storage_unit::StorageUnit
};

const AUTHOR: address = @0xA1;
const IMAGE: vector<u8> = b"https://example.org/check.png";
const REFINERY: u64 = 88063;
const HEAVY_REFINERY: u64 = 88064;
const MINI_PRINTER: u64 = 87119;
const ASM_ITEM: u64 = 7401;
const SSU_ITEM: u64 = 7402;
const POINT_URL: vector<u8> = b"https://lagrange.social/?from=point";
const HOST: vector<u8> = b"lagrange.social";

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

fun refinery_types(): vector<u64> { vector[REFINERY, HEAVY_REFINERY] }

fun claim_assembly(s: &mut Scenario, quest_id: ID, character_id: ID, target: ID, cap_of: ID) {
    s.next_tx(ws::user_a());
    let a = s.take_shared_by_id<Assembly>(cap_of);
    let owner_cap_id = a.owner_cap_id();
    ts::return_shared(a);

    s.next_tx(ws::user_a());
    let ticket = ts::receiving_ticket_by_id<OwnerCap<Assembly>>(owner_cap_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut character = s.take_shared_by_id<Character>(character_id);
    let a = s.take_shared_by_id<Assembly>(target);
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    let (cap, receipt) = character.borrow_owner_cap<Assembly>(ticket, s.ctx());
    world_v0::check_assembly_type_online(&mut t, &a, &cap);
    character.return_owner_cap(cap, receipt);
    finish_claim(t, &mut quest, s);
    ts::return_shared(quest);
    ts::return_shared(character);
    ts::return_shared(a);
}

fun claim_dapp_link(s: &mut Scenario, quest_id: ID, character_id: ID, target: ID, cap_of: ID) {
    s.next_tx(ws::user_a());
    let su = s.take_shared_by_id<StorageUnit>(cap_of);
    let owner_cap_id = su.owner_cap_id();
    ts::return_shared(su);

    s.next_tx(ws::user_a());
    let ticket = ts::receiving_ticket_by_id<OwnerCap<StorageUnit>>(owner_cap_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut character = s.take_shared_by_id<Character>(character_id);
    let su = s.take_shared_by_id<StorageUnit>(target);
    let registry = s.take_shared<LocationRegistry>();
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    let (cap, receipt) = character.borrow_owner_cap<StorageUnit>(ticket, s.ctx());
    world_v0::check_storage_dapp_link(&mut t, &su, &cap, &registry);
    character.return_owner_cap(cap, receipt);
    finish_claim(t, &mut quest, s);
    ts::return_shared(registry);
    ts::return_shared(quest);
    ts::return_shared(character);
    ts::return_shared(su);
}

fun claim_storage_online(s: &mut Scenario, quest_id: ID, character_id: ID, su_id: ID) {
    s.next_tx(ws::user_a());
    let su = s.take_shared_by_id<StorageUnit>(su_id);
    let owner_cap_id = su.owner_cap_id();
    ts::return_shared(su);

    s.next_tx(ws::user_a());
    let ticket = ts::receiving_ticket_by_id<OwnerCap<StorageUnit>>(owner_cap_id);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut character = s.take_shared_by_id<Character>(character_id);
    let su = s.take_shared_by_id<StorageUnit>(su_id);
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

fun claim_player_tribe(s: &mut Scenario, quest_id: ID, character_id: ID, presented_id: ID) {
    s.next_tx(ws::user_a());
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let character = s.take_shared_by_id<Character>(character_id);
    let mut t = core::begin_claim(&quest);
    world_v0::bind(&mut t, &character, s.ctx());
    if (presented_id == character_id) {
        world_v0::check_in_player_tribe(&mut t, &character);
    } else {
        let presented = s.take_shared_by_id<Character>(presented_id);
        world_v0::check_in_player_tribe(&mut t, &presented);
        ts::return_shared(presented);
    };
    finish_claim(t, &mut quest, s);
    ts::return_shared(quest);
    ts::return_shared(character);
}

fun point_storage(s: &mut Scenario, character_id: ID, nwn_id: ID, item: u64, url: vector<u8>, reveal: bool, online: bool): ID {
    let su_id = if (online) ws::setup_online_storage_unit(s, ws::user_a(), character_id, nwn_id, item)
        else ws::create_storage_unit(s, character_id, nwn_id, item);
    ws::set_storage_unit_metadata(s, ws::user_a(), character_id, su_id, b"Academy", b"", url);
    if (reveal) ws::reveal_storage_unit_location(s, su_id);
    su_id
}

#[test]
fun player_tribe_boundary_passes() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    ws::set_tribe(&mut s, character_id, 98_000_000);
    let quest_id = create_quest_with(&mut s, world_v0::in_player_tribe());
    claim_player_tribe(&mut s, quest_id, character_id, character_id);
    s.next_tx(ws::user_a());
    let quest = s.take_shared_by_id<Quest>(quest_id);
    assert!(quest.claims() == 1);
    ts::return_shared(quest);
    assert!(world_v0::player_tribe_min_id() == 98_000_000);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ENotInPlayerTribe)]
fun npc_corp_boundary_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    ws::set_tribe(&mut s, character_id, 97_999_999);
    let quest_id = create_quest_with(&mut s, world_v0::in_player_tribe());
    claim_player_tribe(&mut s, quest_id, character_id, character_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ENotInPlayerTribe)]
fun starting_tribe_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    let quest_id = create_quest_with(&mut s, world_v0::in_player_tribe());
    claim_player_tribe(&mut s, quest_id, character_id, character_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ECharacterMismatch)]
fun foreign_character_in_player_tribe_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, _nwn) = ws::setup_character_with_online_node(&mut s);
    let other_id = ws::create_character(&mut s, ws::user_b(), 202);
    ws::set_tribe(&mut s, other_id, 98_000_551);
    let quest_id = create_quest_with(&mut s, world_v0::in_player_tribe());
    claim_player_tribe(&mut s, quest_id, character_id, other_id);
    s.end();
}

#[test]
fun refinery_online_claim_records_evidence() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let asm_id = ws::setup_online_assembly(&mut s, ws::user_a(), character_id, nwn_id, ASM_ITEM, REFINERY);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_type_online(refinery_types()));
    claim_assembly(&mut s, quest_id, character_id, asm_id, asm_id);
    assert_evidence(&mut s, quest_id, asm_id);
    s.end();
}

#[test]
fun heavy_refinery_counts() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let asm_id = ws::setup_online_assembly(&mut s, ws::user_a(), character_id, nwn_id, ASM_ITEM, HEAVY_REFINERY);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_type_online(refinery_types()));
    claim_assembly(&mut s, quest_id, character_id, asm_id, asm_id);
    assert_evidence(&mut s, quest_id, asm_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EWrongAssemblyType)]
fun printer_for_refinery_quest_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let asm_id = ws::setup_online_assembly(&mut s, ws::user_a(), character_id, nwn_id, ASM_ITEM, MINI_PRINTER);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_type_online(refinery_types()));
    claim_assembly(&mut s, quest_id, character_id, asm_id, asm_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EAssemblyOffline)]
fun offline_refinery_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let asm_id = ws::create_assembly(&mut s, character_id, nwn_id, ASM_ITEM, REFINERY);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_type_online(refinery_types()));
    claim_assembly(&mut s, quest_id, character_id, asm_id, asm_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EAssemblyNotAuthorized)]
fun foreign_assembly_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let own = ws::create_assembly(&mut s, character_id, nwn_id, ASM_ITEM, MINI_PRINTER);
    let other_id = ws::create_character(&mut s, ws::user_b(), 202);
    let other_nwn = ws::create_network_node(&mut s, other_id, 5002);
    ws::bring_network_node_online(&mut s, ws::user_b(), other_id, other_nwn);
    let other_refinery = ws::setup_online_assembly(&mut s, ws::user_b(), other_id, other_nwn, 7499, REFINERY);
    let quest_id = create_quest_with(&mut s, world_v0::assembly_type_online(refinery_types()));
    claim_assembly(&mut s, quest_id, character_id, other_refinery, own);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EInvalidAssemblyTypes)]
fun assembly_type_online_empty_rejected() {
    let _ = world_v0::assembly_type_online(vector[]);
}

#[test, expected_failure(abort_code = world_v0::EInvalidAssemblyTypes)]
fun assembly_type_online_zero_rejected() {
    let _ = world_v0::assembly_type_online(vector[REFINERY, 0]);
}

#[test, expected_failure(abort_code = world_v0::EInvalidAssemblyTypes)]
fun assembly_type_online_too_many_rejected() {
    let _ = world_v0::assembly_type_online(vector[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]);
}

#[test]
fun dapp_link_claim_records_evidence() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, POINT_URL, true, true);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, su_id, su_id);
    assert_evidence(&mut s, quest_id, su_id);
    s.end();
}

#[test]
fun dapp_link_offline_storage_and_bare_host_pass() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, b"https://lagrange.social", true, false);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, su_id, su_id);
    assert_evidence(&mut s, quest_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EDappUrlMismatch)]
fun dapp_link_without_url_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, b"", true, true);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, su_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EDappUrlMismatch)]
fun dapp_link_lookalike_host_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, b"https://lagrange.social.evil.com/?from=point", true, true);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, su_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EDappUrlMismatch)]
fun dapp_link_http_scheme_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, b"http://lagrange.social/?from=point", true, true);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, su_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::ELocationNotPublic)]
fun dapp_link_unpublished_location_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, POINT_URL, false, true);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, su_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EAssemblyNotAuthorized)]
fun foreign_dapp_link_storage_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let own = ws::create_storage_unit(&mut s, character_id, nwn_id, SSU_ITEM);
    let other_id = ws::create_character(&mut s, ws::user_b(), 202);
    let other_nwn = ws::create_network_node(&mut s, other_id, 5002);
    ws::bring_network_node_online(&mut s, ws::user_b(), other_id, other_nwn);
    let other_su = ws::setup_online_storage_unit(&mut s, ws::user_b(), other_id, other_nwn, 7499);
    ws::set_storage_unit_metadata(&mut s, ws::user_b(), other_id, other_su, b"Academy", b"", POINT_URL);
    ws::reveal_storage_unit_location(&mut s, other_su);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, other_su, own);
    s.end();
}

#[test]
fun same_storage_counts_in_assembly_online_and_dapp_link_quests() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, POINT_URL, true, true);
    let storage_quest = create_quest_with(&mut s, world_v0::assembly_online(world_v0::kind_storage_unit()));
    let point_quest = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_storage_online(&mut s, storage_quest, character_id, su_id);
    claim_dapp_link(&mut s, point_quest, character_id, su_id, su_id);
    assert_evidence(&mut s, storage_quest, su_id);
    assert_evidence(&mut s, point_quest, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EInvalidHost)]
fun storage_dapp_link_empty_host_rejected() {
    let _ = world_v0::storage_dapp_link(b"");
}

#[test, expected_failure(abort_code = world_v0::EInvalidHost)]
fun storage_dapp_link_uppercase_host_rejected() {
    let _ = world_v0::storage_dapp_link(b"Lagrange.social");
}

#[test, expected_failure(abort_code = world_v0::EInvalidHost)]
fun storage_dapp_link_host_with_path_rejected() {
    let _ = world_v0::storage_dapp_link(b"lagrange.social/");
}

#[test, expected_failure(abort_code = world_v0::EDappUrlMismatch)]
fun dapp_link_port_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, b"https://lagrange.social:443/", true, true);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, su_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EDappUrlMismatch)]
fun dapp_link_userinfo_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, b"https://x@lagrange.social/", true, true);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, su_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EDappUrlMismatch)]
fun dapp_link_trailing_dot_fails() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = point_storage(&mut s, character_id, nwn_id, SSU_ITEM, b"https://lagrange.social./", true, true);
    let quest_id = create_quest_with(&mut s, world_v0::storage_dapp_link(HOST));
    claim_dapp_link(&mut s, quest_id, character_id, su_id, su_id);
    s.end();
}

#[test, expected_failure(abort_code = world_v0::EInvalidHost)]
fun storage_dapp_link_host_with_port_rejected() {
    let _ = world_v0::storage_dapp_link(b"lagrange.social:443");
}

#[test, expected_failure(abort_code = world_v0::EInvalidHost)]
fun storage_dapp_link_host_with_underscore_rejected() {
    let _ = world_v0::storage_dapp_link(b"lagrange_social");
}

fun host_of_len(n: u64): vector<u8> {
    let mut h = vector[];
    n.do!(|_| h.push_back(0x61));
    h
}

#[test, expected_failure(abort_code = world_v0::EInvalidHost)]
fun storage_dapp_link_254_char_host_rejected() {
    let _ = world_v0::storage_dapp_link(host_of_len(254));
}

#[test]
fun storage_dapp_link_valid_hosts_accepted() {
    let _ = world_v0::storage_dapp_link(host_of_len(253));
    let _ = world_v0::storage_dapp_link(host_of_len(1));
    let _ = world_v0::storage_dapp_link(HOST);
    let _ = world_v0::storage_dapp_link(b"a-b.c9");
}
