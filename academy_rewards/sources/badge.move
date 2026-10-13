module academy_rewards::badge;

use academy_core::core::{Self, Requirement, RewardTicket};
use std::{internal, string::{String, utf8}};
use sui::{
    bcs,
    clock::Clock,
    display_registry::{Self, DisplayCap, DisplayRegistry},
    package::{Self, Publisher}
};

public struct BADGE has drop {}

public struct BadgeReward has drop { image_uri: String }

public struct Badge has key {
    id: UID,
    academy_id: ID,
    quest_id: ID,
    tenant: String,
    game_id: u64,
    image_uri: String,
    issued_at_ms: u64,
}

fun init(otw: BADGE, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx);
}

public fun requirement(image_uri: String): Requirement {
    core::requirement(BadgeReward { image_uri })
}

public fun issue(rt: &mut RewardTicket, clock: &Clock, ctx: &mut TxContext) {
    let (quest_id, recipient, data) = rt.take_reward(internal::permit<BadgeReward>());
    let image_uri = utf8(bcs::new(data).peel_vec_u8());
    let badge = Badge {
        id: object::new(ctx),
        academy_id: rt.reward_academy_id(),
        quest_id,
        tenant: rt.reward_tenant(),
        game_id: rt.reward_game_id(),
        image_uri,
        issued_at_ms: clock.timestamp_ms(),
    };
    rt.record_payment(internal::permit<BadgeReward>(), 1);
    transfer::transfer(badge, recipient);
}

public fun create_display(
    registry: &mut DisplayRegistry,
    publisher: &mut Publisher,
    ctx: &mut TxContext,
): DisplayCap<Badge> {
    let (mut display, cap) = display_registry::new_with_publisher<Badge>(registry, publisher, ctx);
    display.set(&cap, utf8(b"name"), utf8(b"Academy badge · quest {quest_id}"));
    display.set(
        &cap,
        utf8(b"description"),
        utf8(
            b"Academy {academy_id}, quest {quest_id}, character {game_id} ({tenant}). Trust it only if the academy is known to you.",
        ),
    );
    display.set(&cap, utf8(b"image_url"), utf8(b"{image_uri}"));
    display.set(&cap, utf8(b"academy_id"), utf8(b"{academy_id}"));
    display.set(&cap, utf8(b"quest_id"), utf8(b"{quest_id}"));
    display.share();
    cap
}

public fun burn(badge: Badge) {
    let Badge { id, .. } = badge;
    id.delete();
}

public fun academy_id(b: &Badge): ID { b.academy_id }

public fun quest_id(b: &Badge): ID { b.quest_id }

public fun tenant(b: &Badge): String { b.tenant }

public fun game_id(b: &Badge): u64 { b.game_id }

public fun image_uri(b: &Badge): String { b.image_uri }

public fun issued_at_ms(b: &Badge): u64 { b.issued_at_ms }

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(BADGE {}, ctx);
}
