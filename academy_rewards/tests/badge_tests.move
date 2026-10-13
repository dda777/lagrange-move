#[test_only]
module academy_rewards::badge_tests;

use academy_core::core::{Self, Academy, AcademyAdminCap, Quest};
use academy_rewards::{badge::{Self, Badge}, test_identity};
use std::string::{String, utf8};
use sui::{
    clock,
    display_registry::{Display, DisplayCap, DisplayRegistry},
    package::Publisher,
    test_scenario::{Self as ts, Scenario}
};

const AUTHOR: address = @0xA1;
const PLAYER: address = @0xB1;
const IMAGE: vector<u8> = b"https://example.org/node.png";

fun tenant(): String { utf8(b"TEST") }

fun setup(s: &mut Scenario, rewards: vector<core::Requirement>): (ID, ID) {
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
        test_identity::requirement(),
        vector[],
        rewards,
        utf8(b""),
        x"",
        s.ctx(),
    );
    s.return_to_sender(cap);
    ts::return_shared(academy);
    (academy_id, quest_id)
}

#[test]
fun badge_is_issued_to_recipient() {
    let mut s = ts::begin(AUTHOR);
    let (academy_id, quest_id) = setup(&mut s, vector[badge::requirement(utf8(IMAGE))]);

    s.next_tx(PLAYER);
    let mut clock = clock::create_for_testing(s.ctx());
    clock.set_for_testing(1_700_000_000_000);
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let mut rt = core::complete(t, &mut quest);
    badge::issue(&mut rt, &clock, s.ctx());
    core::finish(rt);
    ts::return_shared(quest);
    clock.destroy_for_testing();

    let effects = s.next_tx(PLAYER);
    assert!(effects.num_user_events() == 2);
    let b = s.take_from_sender<Badge>();
    assert!(b.academy_id() == academy_id);
    assert!(b.quest_id() == quest_id);
    assert!(b.tenant() == tenant());
    assert!(b.game_id() == 101);
    assert!(b.image_uri() == utf8(IMAGE));
    assert!(b.issued_at_ms() == 1_700_000_000_000);
    s.return_to_sender(b);
    s.end();
}

#[test, expected_failure(abort_code = core::EWrongRequirement)]
fun badge_cannot_take_other_reward() {
    let mut s = ts::begin(AUTHOR);
    let (_, quest_id) = setup(
        &mut s,
        vector[test_identity::other_reward(), badge::requirement(utf8(IMAGE))],
    );
    s.next_tx(PLAYER);
    let clock = clock::create_for_testing(s.ctx());
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let mut rt = core::complete(t, &mut quest);
    badge::issue(&mut rt, &clock, s.ctx());
    abort
}

#[test]
fun owner_can_burn_badge() {
    let mut s = ts::begin(AUTHOR);
    let (_, quest_id) = setup(&mut s, vector[badge::requirement(utf8(IMAGE))]);
    s.next_tx(PLAYER);
    let clock = clock::create_for_testing(s.ctx());
    let mut quest = s.take_shared_by_id<Quest>(quest_id);
    let mut t = core::begin_claim(&quest);
    test_identity::bind(&mut t, tenant(), 101, PLAYER);
    let mut rt = core::complete(t, &mut quest);
    badge::issue(&mut rt, &clock, s.ctx());
    core::finish(rt);
    ts::return_shared(quest);
    clock.destroy_for_testing();

    s.next_tx(PLAYER);
    let b = s.take_from_sender<Badge>();
    let badge_id = object::id(&b);
    badge::burn(b);
    let effects = s.next_tx(PLAYER);
    assert!(effects.deleted().contains(&badge_id));
    assert!(!s.has_most_recent_for_sender<Badge>());
    s.end();
}

#[test]
fun display_v2_is_created_by_publisher() {
    let mut s = ts::begin(AUTHOR);
    s.create_system_objects();
    s.next_tx(AUTHOR);
    badge::init_for_testing(s.ctx());

    s.next_tx(AUTHOR);
    let mut registry = s.take_shared<DisplayRegistry>();
    let mut publisher = s.take_from_sender<Publisher>();
    let cap = badge::create_display(&mut registry, &mut publisher, s.ctx());
    transfer::public_transfer(cap, AUTHOR);
    s.return_to_sender(publisher);
    ts::return_shared(registry);

    s.next_tx(AUTHOR);
    let display = s.take_shared<Display<Badge>>();
    let fields = display.fields();
    assert!(fields.get(&utf8(b"image_url")) == utf8(b"{image_uri}"));
    assert!(fields.contains(&utf8(b"name")));
    assert!(fields.contains(&utf8(b"description")));
    assert!(fields.get(&utf8(b"academy_id")) == utf8(b"{academy_id}"));
    assert!(fields.get(&utf8(b"quest_id")) == utf8(b"{quest_id}"));
    let cap = s.take_from_sender<DisplayCap<Badge>>();
    assert!(display.cap_id() == option::some(object::id(&cap)));
    s.return_to_sender(cap);
    ts::return_shared(display);
    s.end();
}
