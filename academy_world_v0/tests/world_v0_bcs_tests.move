#[test_only]
module academy_world_v0::world_v0_bcs_tests;

use academy_test_support::world_setup as ws;
use academy_world_v0::world_v0;
use sui::test_scenario as ts;
use world::{assembly::Assembly, storage_unit::StorageUnit};

const SSU_ITEM: u64 = 7301;
const ASM_ITEM: u64 = 7302;
const REFINERY: u64 = 88063;

#[test]
fun storage_unit_header_and_url_offsets() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = ws::create_storage_unit(&mut s, character_id, nwn_id, SSU_ITEM);

    s.next_tx(ws::user_a());
    let su = s.take_shared_by_id<StorageUnit>(su_id);
    assert!(world_v0::storage_unit_type_id_for_testing(&su) == ws::ssu_type_id());
    assert!(world_v0::storage_unit_url_for_testing(&su) == b"");
    ts::return_shared(su);

    ws::set_storage_unit_metadata(
        &mut s,
        ws::user_a(),
        character_id,
        su_id,
        b"Academy: free newbie guide",
        b"description-x",
        b"https://lagrange.social/?from=point",
    );
    s.next_tx(ws::user_a());
    let su = s.take_shared_by_id<StorageUnit>(su_id);
    assert!(world_v0::storage_unit_url_for_testing(&su) == b"https://lagrange.social/?from=point");
    assert!(world_v0::storage_unit_type_id_for_testing(&su) == ws::ssu_type_id());
    ts::return_shared(su);
    s.end();
}

#[test]
fun storage_unit_url_offsets_survive_online_and_reveal() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let su_id = ws::setup_online_storage_unit(&mut s, ws::user_a(), character_id, nwn_id, SSU_ITEM);
    ws::set_storage_unit_metadata(&mut s, ws::user_a(), character_id, su_id, b"n", b"d", b"https://lagrange.social");
    ws::reveal_storage_unit_location(&mut s, su_id);
    s.next_tx(ws::user_a());
    let su = s.take_shared_by_id<StorageUnit>(su_id);
    assert!(world_v0::storage_unit_url_for_testing(&su) == b"https://lagrange.social");
    ts::return_shared(su);
    s.end();
}

#[test]
fun assembly_type_id_offset() {
    let mut s = ts::begin(ws::admin());
    let (character_id, nwn_id) = ws::setup_character_with_online_node(&mut s);
    let asm_id = ws::setup_online_assembly(&mut s, ws::user_a(), character_id, nwn_id, ASM_ITEM, REFINERY);
    s.next_tx(ws::user_a());
    let a = s.take_shared_by_id<Assembly>(asm_id);
    assert!(world_v0::assembly_type_id_for_testing(&a) == REFINERY);
    assert!(a.status().is_online());
    ts::return_shared(a);
    s.end();
}

fun h(url: vector<u8>): vector<u8> { world_v0::url_host_for_testing(url) }

#[test]
fun url_host_table() {
    assert!(h(b"https://lagrange.social") == b"lagrange.social");
    assert!(h(b"https://lagrange.social/?from=point") == b"lagrange.social");
    assert!(h(b"https://lagrange.social?x=1") == b"lagrange.social");
    assert!(h(b"https://lagrange.social#top") == b"lagrange.social");
    assert!(h(b"HTTPS://Lagrange.Social/x") == b"lagrange.social");
    assert!(h(b"http://lagrange.social") == b"");
    assert!(h(b"ftp://lagrange.social") == b"");
    assert!(h(b"") == b"");
    assert!(h(b"https:/") == b"");
    assert!(h(b"https://") == b"");
    assert!(h(b"https://a.lagrange.social") == b"a.lagrange.social");
    assert!(h(b"https://lagrange.social.evil.com/") == b"lagrange.social.evil.com");
    assert!(h(b"https://evil.com/lagrange.social") == b"evil.com");
    assert!(h(b"https://lagrange.social@evil.com") == b"lagrange.social@evil.com");
    assert!(h(b"https://lagrange.social:443/") == b"lagrange.social:443");
    assert!(h(b"https://lagrange.social.") == b"lagrange.social.");
    assert!(h(b"https://a_b.example") == b"a_b.example");
    let mut long = b"https://";
    let mut k = 0;
    while (k < 254) { long.push_back(b"a"[0]); k = k + 1; };
    assert!(h(long).length() == 254);
}
