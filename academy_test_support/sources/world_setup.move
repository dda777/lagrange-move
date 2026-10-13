#[test_only]
module academy_test_support::world_setup;

use sui::{clock, test_scenario as ts};
use world::{
    access::{Self, AdminACL, OwnerCap, ServerAddressRegistry},
    assembly::{Self, Assembly},
    character::{Self, Character},
    energy::{Self, EnergyConfig},
    fuel::{Self, FuelConfig},
    gate::{Self, Gate, GateConfig},
    killmail,
    killmail_registry::{Self, KillmailRegistry},
    location::{Self, LocationRegistry},
    network_node::{Self, NetworkNode},
    object_registry::{Self, ObjectRegistry},
    storage_unit::{Self, StorageUnit},
    turret::{Self, Turret},
    world::{Self, GovernorCap}
};

const GATE_TYPE_ID: u64 = 8888;
const GATE_TYPE_ENERGY: u64 = 50;
const SSU_TYPE_ID: u64 = 7777;
const SSU_TYPE_ENERGY: u64 = 10;
const SSU_MAX_CAPACITY: u64 = 1000;
const TURRET_TYPE_ID: u64 = 6666;
const TURRET_TYPE_ENERGY: u64 = 10;
const NWN_TYPE_ID: u64 = 111000;
const NWN_ITEM_ID: u64 = 5000;
const FUEL_TYPE_ID: u64 = 1;
const FUEL_EFFICIENCY: u64 = 100;
const FUEL_MAX_CAPACITY: u64 = 1000;
const FUEL_BURN_RATE_IN_MS: u64 = 3600 * 1000;
const MAX_PRODUCTION: u64 = 100;
const CHARACTER_ITEM_ID: u32 = 101;
const DEFAULT_TRIBE_ID: u32 = 100;
const SOLAR_SYSTEM_ID: u64 = 30000001;
const LOSS_TYPE_SHIP: u8 = 1;
const VERIFIED_LOCATION_HASH: vector<u8> =
    x"16217de8ec7330ec3eac32831df5c9cd9b21a255756a5fd5762dd7f49f6cc049";

public fun governor(): address { @0xA }

public fun admin(): address { @0xB }

public fun user_a(): address { @0x202d7d52ab5f8e8824e3e8066c0b7458f84e326c5d77b30254c69d807586a7b0 }

public fun user_b(): address { @0xD }

public fun tenant(): std::string::String { std::string::utf8(b"TEST") }

public fun character_item_id(): u32 { CHARACTER_ITEM_ID }

public fun default_tribe_id(): u32 { DEFAULT_TRIBE_ID }

public fun ssu_type_id(): u64 { SSU_TYPE_ID }

public fun setup_character_with_online_node(ts: &mut ts::Scenario): (ID, ID) {
    init_world(ts);
    let character_id = create_character(ts, user_a(), CHARACTER_ITEM_ID);
    let nwn_id = create_network_node(ts, character_id, NWN_ITEM_ID);
    bring_network_node_online(ts, user_a(), character_id, nwn_id);
    (character_id, nwn_id)
}

public fun setup_online_gate(ts: &mut ts::Scenario, character_id: ID, nwn_id: ID, item_id: u64): ID {
    let gate_id = create_gate(ts, character_id, nwn_id, item_id);
    bring_gate_online(ts, character_id, nwn_id, gate_id);
    gate_id
}

public fun setup_online_storage_unit(
    ts: &mut ts::Scenario,
    owner: address,
    character_id: ID,
    nwn_id: ID,
    item_id: u64,
): ID {
    let su_id = create_storage_unit(ts, character_id, nwn_id, item_id);
    bring_storage_unit_online(ts, owner, character_id, nwn_id, su_id);
    su_id
}

public fun setup_online_turret(
    ts: &mut ts::Scenario,
    owner: address,
    character_id: ID,
    nwn_id: ID,
    item_id: u64,
): ID {
    let turret_id = create_turret(ts, character_id, nwn_id, item_id);
    bring_turret_online(ts, owner, character_id, nwn_id, turret_id);
    turret_id
}

public fun init_world(ts: &mut ts::Scenario) {
    ts.next_tx(governor());
    {
        world::init_for_testing(ts.ctx());
        access::init_for_testing(ts.ctx());
        object_registry::init_for_testing(ts.ctx());
        killmail_registry::init_for_testing(ts.ctx());
        fuel::init_for_testing(ts.ctx());
        energy::init_for_testing(ts.ctx());
        location::init_for_testing(ts.ctx());
        gate::init_for_testing(ts.ctx());
    };

    ts.next_tx(governor());
    {
        let gov_cap = ts.take_from_sender<GovernorCap>();
        let mut admin_acl = ts.take_shared<AdminACL>();
        let mut server_registry = ts.take_shared<ServerAddressRegistry>();
        access::add_sponsor_to_acl(&mut admin_acl, &gov_cap, admin());
        access::add_sponsor_to_acl(&mut admin_acl, &gov_cap, user_a());
        access::register_server_address(&mut server_registry, &gov_cap, admin());
        ts.return_to_sender(gov_cap);
        ts::return_shared(admin_acl);
        ts::return_shared(server_registry);
    };

    ts.next_tx(admin());
    {
        let admin_acl = ts.take_shared<AdminACL>();
        let mut fuel_config = ts.take_shared<FuelConfig>();
        let mut energy_config = ts.take_shared<EnergyConfig>();
        let mut gate_config = ts.take_shared<GateConfig>();
        fuel_config.set_fuel_efficiency(&admin_acl, FUEL_TYPE_ID, FUEL_EFFICIENCY, ts.ctx());
        energy_config.set_energy_config(&admin_acl, GATE_TYPE_ID, GATE_TYPE_ENERGY, ts.ctx());
        energy_config.set_energy_config(&admin_acl, SSU_TYPE_ID, SSU_TYPE_ENERGY, ts.ctx());
        energy_config.set_energy_config(&admin_acl, TURRET_TYPE_ID, TURRET_TYPE_ENERGY, ts.ctx());
        gate::set_max_distance(&mut gate_config, &admin_acl, GATE_TYPE_ID, 1_000_000_000, ts.ctx());
        ts::return_shared(fuel_config);
        ts::return_shared(energy_config);
        ts::return_shared(gate_config);
        ts::return_shared(admin_acl);
    };
}

public fun create_character(ts: &mut ts::Scenario, user: address, item_id: u32): ID {
    create_character_in_tenant(ts, user, item_id, tenant())
}

public fun create_character_in_tenant(
    ts: &mut ts::Scenario,
    user: address,
    item_id: u32,
    tenant: std::string::String,
): ID {
    ts.next_tx(admin());
    let admin_acl = ts.take_shared<AdminACL>();
    let mut registry = ts.take_shared<ObjectRegistry>();
    let character = character::create_character(
        &mut registry,
        &admin_acl,
        item_id,
        tenant,
        DEFAULT_TRIBE_ID,
        user,
        std::string::utf8(b"name"),
        ts.ctx(),
    );
    let character_id = object::id(&character);
    character.share_character(&admin_acl, ts.ctx());
    ts::return_shared(registry);
    ts::return_shared(admin_acl);
    character_id
}

public fun create_network_node(ts: &mut ts::Scenario, character_id: ID, item_id: u64): ID {
    ts.next_tx(admin());
    let mut registry = ts.take_shared<ObjectRegistry>();
    let character = ts.take_shared_by_id<Character>(character_id);
    let admin_acl = ts.take_shared<AdminACL>();
    let nwn = network_node::anchor(
        &mut registry,
        &character,
        &admin_acl,
        item_id,
        NWN_TYPE_ID,
        VERIFIED_LOCATION_HASH,
        FUEL_MAX_CAPACITY,
        FUEL_BURN_RATE_IN_MS,
        MAX_PRODUCTION,
        ts.ctx(),
    );
    let nwn_id = object::id(&nwn);
    nwn.share_network_node(&admin_acl, ts.ctx());
    ts::return_shared(character);
    ts::return_shared(registry);
    ts::return_shared(admin_acl);
    nwn_id
}

public fun bring_network_node_online(
    ts: &mut ts::Scenario,
    owner: address,
    character_id: ID,
    nwn_id: ID,
) {
    ts.next_tx(owner);
    let clock = clock::create_for_testing(ts.ctx());
    let mut nwn = ts.take_shared_by_id<NetworkNode>(nwn_id);
    let mut character = ts.take_shared_by_id<Character>(character_id);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<NetworkNode>>(nwn.owner_cap_id());
    let (owner_cap, receipt) = character.borrow_owner_cap<NetworkNode>(ticket, ts.ctx());
    nwn.deposit_fuel_test(&owner_cap, FUEL_TYPE_ID, 10, 10, &clock);
    nwn.online(&owner_cap, &clock);
    character.return_owner_cap(owner_cap, receipt);
    ts::return_shared(nwn);
    ts::return_shared(character);
    clock.destroy_for_testing();
}

public fun create_gate(ts: &mut ts::Scenario, character_id: ID, nwn_id: ID, item_id: u64): ID {
    ts.next_tx(admin());
    let mut registry = ts.take_shared<ObjectRegistry>();
    let mut nwn = ts.take_shared_by_id<NetworkNode>(nwn_id);
    let character = ts.take_shared_by_id<Character>(character_id);
    let admin_acl = ts.take_shared<AdminACL>();
    let gate_obj = gate::anchor(
        &mut registry,
        &mut nwn,
        &character,
        &admin_acl,
        item_id,
        GATE_TYPE_ID,
        VERIFIED_LOCATION_HASH,
        ts.ctx(),
    );
    let gate_id = object::id(&gate_obj);
    gate_obj.share_gate(&admin_acl, ts.ctx());
    ts::return_shared(character);
    ts::return_shared(nwn);
    ts::return_shared(registry);
    ts::return_shared(admin_acl);
    gate_id
}

fun bring_gate_online(ts: &mut ts::Scenario, character_id: ID, nwn_id: ID, gate_id: ID) {
    ts.next_tx(user_a());
    let mut nwn = ts.take_shared_by_id<NetworkNode>(nwn_id);
    let energy_config = ts.take_shared<EnergyConfig>();
    let mut character = ts.take_shared_by_id<Character>(character_id);
    let mut gate_obj = ts.take_shared_by_id<Gate>(gate_id);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<Gate>>(gate_obj.owner_cap_id());
    let (owner_cap, receipt) = character.borrow_owner_cap<Gate>(ticket, ts.ctx());
    gate_obj.online(&mut nwn, &energy_config, &owner_cap);
    character.return_owner_cap(owner_cap, receipt);
    ts::return_shared(gate_obj);
    ts::return_shared(character);
    ts::return_shared(nwn);
    ts::return_shared(energy_config);
}

public fun create_storage_unit(ts: &mut ts::Scenario, character_id: ID, nwn_id: ID, item_id: u64): ID {
    ts.next_tx(admin());
    let mut registry = ts.take_shared<ObjectRegistry>();
    let mut nwn = ts.take_shared_by_id<NetworkNode>(nwn_id);
    let character = ts.take_shared_by_id<Character>(character_id);
    let admin_acl = ts.take_shared<AdminACL>();
    let su = storage_unit::anchor(
        &mut registry,
        &mut nwn,
        &character,
        &admin_acl,
        item_id,
        SSU_TYPE_ID,
        SSU_MAX_CAPACITY,
        VERIFIED_LOCATION_HASH,
        ts.ctx(),
    );
    let su_id = object::id(&su);
    su.share_storage_unit(&admin_acl, ts.ctx());
    ts::return_shared(character);
    ts::return_shared(nwn);
    ts::return_shared(registry);
    ts::return_shared(admin_acl);
    su_id
}

public fun bring_storage_unit_online(
    ts: &mut ts::Scenario,
    owner: address,
    character_id: ID,
    nwn_id: ID,
    su_id: ID,
) {
    ts.next_tx(owner);
    let mut nwn = ts.take_shared_by_id<NetworkNode>(nwn_id);
    let energy_config = ts.take_shared<EnergyConfig>();
    let mut character = ts.take_shared_by_id<Character>(character_id);
    let mut su = ts.take_shared_by_id<StorageUnit>(su_id);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<StorageUnit>>(su.owner_cap_id());
    let (owner_cap, receipt) = character.borrow_owner_cap<StorageUnit>(ticket, ts.ctx());
    su.online(&mut nwn, &energy_config, &owner_cap);
    character.return_owner_cap(owner_cap, receipt);
    ts::return_shared(su);
    ts::return_shared(character);
    ts::return_shared(nwn);
    ts::return_shared(energy_config);
}

public fun create_turret(ts: &mut ts::Scenario, character_id: ID, nwn_id: ID, item_id: u64): ID {
    ts.next_tx(admin());
    let mut registry = ts.take_shared<ObjectRegistry>();
    let mut nwn = ts.take_shared_by_id<NetworkNode>(nwn_id);
    let character = ts.take_shared_by_id<Character>(character_id);
    let admin_acl = ts.take_shared<AdminACL>();
    let t = turret::anchor(
        &mut registry,
        &mut nwn,
        &character,
        &admin_acl,
        item_id,
        TURRET_TYPE_ID,
        VERIFIED_LOCATION_HASH,
        ts.ctx(),
    );
    let turret_id = object::id(&t);
    t.share_turret(&admin_acl, ts.ctx());
    ts::return_shared(character);
    ts::return_shared(nwn);
    ts::return_shared(registry);
    ts::return_shared(admin_acl);
    turret_id
}

public fun bring_turret_online(
    ts: &mut ts::Scenario,
    owner: address,
    character_id: ID,
    nwn_id: ID,
    turret_id: ID,
) {
    ts.next_tx(owner);
    let mut nwn = ts.take_shared_by_id<NetworkNode>(nwn_id);
    let energy_config = ts.take_shared<EnergyConfig>();
    let mut character = ts.take_shared_by_id<Character>(character_id);
    let mut t = ts.take_shared_by_id<Turret>(turret_id);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<Turret>>(t.owner_cap_id());
    let (owner_cap, receipt) = character.borrow_owner_cap<Turret>(ticket, ts.ctx());
    t.online(&mut nwn, &energy_config, &owner_cap);
    character.return_owner_cap(owner_cap, receipt);
    ts::return_shared(t);
    ts::return_shared(character);
    ts::return_shared(nwn);
    ts::return_shared(energy_config);
}

public fun create_killmail(
    ts: &mut ts::Scenario,
    reporter_id: ID,
    item_id: u64,
    killer_game_id: u64,
    victim_game_id: u64,
    kill_timestamp: u64,
): ID {
    ts.next_tx(admin());
    let mut registry = ts.take_shared<KillmailRegistry>();
    let admin_acl = ts.take_shared<AdminACL>();
    let reporter = ts.take_shared_by_id<Character>(reporter_id);
    killmail::create_killmail(
        &mut registry,
        &admin_acl,
        item_id,
        killer_game_id,
        victim_game_id,
        &reporter,
        kill_timestamp,
        LOSS_TYPE_SHIP,
        SOLAR_SYSTEM_ID,
        ts.ctx(),
    );
    ts::return_shared(reporter);
    ts::return_shared(admin_acl);
    ts::return_shared(registry);
    ts.next_tx(admin());
    ts::most_recent_id_shared<killmail::Killmail>().destroy_some()
}

public fun set_tribe(ts: &mut ts::Scenario, character_id: ID, tribe_id: u32) {
    ts.next_tx(admin());
    let admin_acl = ts.take_shared<AdminACL>();
    let mut character = ts.take_shared_by_id<Character>(character_id);
    character.update_tribe(&admin_acl, tribe_id, ts.ctx());
    ts::return_shared(character);
    ts::return_shared(admin_acl);
}

public fun create_assembly(ts: &mut ts::Scenario, character_id: ID, nwn_id: ID, item_id: u64, type_id: u64): ID {
    ts.next_tx(admin());
    let mut registry = ts.take_shared<ObjectRegistry>();
    let mut nwn = ts.take_shared_by_id<NetworkNode>(nwn_id);
    let character = ts.take_shared_by_id<Character>(character_id);
    let admin_acl = ts.take_shared<AdminACL>();
    let a = assembly::anchor(
        &mut registry,
        &mut nwn,
        &character,
        &admin_acl,
        item_id,
        type_id,
        VERIFIED_LOCATION_HASH,
        ts.ctx(),
    );
    let assembly_id = object::id(&a);
    a.share_assembly(&admin_acl, ts.ctx());
    ts::return_shared(character);
    ts::return_shared(nwn);
    ts::return_shared(registry);
    ts::return_shared(admin_acl);
    assembly_id
}

public fun bring_assembly_online(
    ts: &mut ts::Scenario,
    owner: address,
    character_id: ID,
    nwn_id: ID,
    assembly_id: ID,
) {
    ts.next_tx(owner);
    let mut nwn = ts.take_shared_by_id<NetworkNode>(nwn_id);
    let energy_config = ts.take_shared<EnergyConfig>();
    let mut character = ts.take_shared_by_id<Character>(character_id);
    let mut a = ts.take_shared_by_id<Assembly>(assembly_id);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<Assembly>>(a.owner_cap_id());
    let (owner_cap, receipt) = character.borrow_owner_cap<Assembly>(ticket, ts.ctx());
    a.online(&mut nwn, &energy_config, &owner_cap);
    character.return_owner_cap(owner_cap, receipt);
    ts::return_shared(a);
    ts::return_shared(character);
    ts::return_shared(nwn);
    ts::return_shared(energy_config);
}

public fun setup_online_assembly(
    ts: &mut ts::Scenario,
    owner: address,
    character_id: ID,
    nwn_id: ID,
    item_id: u64,
    type_id: u64,
): ID {
    let assembly_id = create_assembly(ts, character_id, nwn_id, item_id, type_id);
    bring_assembly_online(ts, owner, character_id, nwn_id, assembly_id);
    assembly_id
}

public fun set_storage_unit_metadata(
    ts: &mut ts::Scenario,
    owner: address,
    character_id: ID,
    su_id: ID,
    name: vector<u8>,
    description: vector<u8>,
    url: vector<u8>,
) {
    ts.next_tx(owner);
    let mut character = ts.take_shared_by_id<Character>(character_id);
    let mut su = ts.take_shared_by_id<StorageUnit>(su_id);
    let ticket = ts::receiving_ticket_by_id<OwnerCap<StorageUnit>>(su.owner_cap_id());
    let (owner_cap, receipt) = character.borrow_owner_cap<StorageUnit>(ticket, ts.ctx());
    su.update_metadata_name(&owner_cap, std::string::utf8(name));
    su.update_metadata_description(&owner_cap, std::string::utf8(description));
    su.update_metadata_url(&owner_cap, std::string::utf8(url));
    character.return_owner_cap(owner_cap, receipt);
    ts::return_shared(su);
    ts::return_shared(character);
}

public fun reveal_storage_unit_location(ts: &mut ts::Scenario, su_id: ID) {
    ts.next_tx(admin());
    let su = ts.take_shared_by_id<StorageUnit>(su_id);
    let mut registry = ts.take_shared<LocationRegistry>();
    let admin_acl = ts.take_shared<AdminACL>();
    su.reveal_location(
        &mut registry,
        &admin_acl,
        SOLAR_SYSTEM_ID,
        std::string::utf8(b"1"),
        std::string::utf8(b"-2"),
        std::string::utf8(b"3"),
        ts.ctx(),
    );
    ts::return_shared(admin_acl);
    ts::return_shared(registry);
    ts::return_shared(su);
}
