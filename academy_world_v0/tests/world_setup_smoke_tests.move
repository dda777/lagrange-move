#[test_only]
module academy_world_v0::world_setup_smoke_tests;

use academy_test_support::world_setup;
use sui::test_scenario as ts;

#[test]
fun shared_world_setup_brings_character_and_node_online() {
    let mut scenario = ts::begin(world_setup::admin());
    let (character_id, nwn_id) = world_setup::setup_character_with_online_node(&mut scenario);
    let gate_id = world_setup::setup_online_gate(&mut scenario, character_id, nwn_id, 7001);

    assert!(character_id != nwn_id, 0);
    assert!(gate_id != nwn_id, 1);

    scenario.end();
}
