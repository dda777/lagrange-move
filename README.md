# Lagrange Move contracts

These are the Move packages behind [Lagrange](https://lagrange.social), my community portal for EVE Frontier (academy quests with on-chain checks and badges). They are deployed on Sui testnet.

I publish them so you don't have to take my word for what the site asks you to sign. Every transaction the site gives you to sign in EVE Vault calls functions from these packages. Every package version below is tagged in this repository, and its source builds into exactly the bytecode that is on chain. The rest of the portal (website, API, gas sponsor) stays closed: open code for those would not prove what actually runs on the server, while the contracts can be checked by anyone.

## Package versions

<!-- versions:start -->
| Package | Version | Published at | Original ID | Toolchain | Tag | Source |
|---|---|---|---|---|---|---|
| `academy_core` | 3 | `0xc5c2976ccf7b0f05cea9e762d346bb2ca8329f567e0ef9f9f8c9f11adb2d93a0` | `0xd3a6353ab5ccec51a7cc3f7a0c25c6caf72d98727481ed50dfeb7b479c7a70db` | 1.81.1 | `academy_core-v3` | [verified](https://suiscan.xyz/testnet/object/0xc5c2976ccf7b0f05cea9e762d346bb2ca8329f567e0ef9f9f8c9f11adb2d93a0/contracts) |
| `academy_rewards` | 2 | `0xc6ff5a7518196e6415bea1cde427c2ea89984df018b38a2f680ccceaff23eeb1` | `0xd239eebc3fb6b1a98653451e1303112b8b361fdf5823cff3c1231abd57eaa400` | 1.81.1 | `academy_rewards-v2` | pending verification |
| `academy_gas` | 2 | `0x58a87d61a711de84563fd02dc063e64182e73dcfda4acbc1840bbedcc92cf865` | `0x3aed0dd01bbe97ad2dc6b339ef056c0e7f85c0821ea81d8ef0fc080ca9b31821` | 1.81.1 | `academy_gas-v2` | pending verification |
| `academy_world_v0` | 3 | `0x1f9e98daf088a1ec527ccbf74db0e51185bff5fa5f6c0901f10bd35668c822c0` | `0x67b465bb898f2c502ea5cf0abedf2fad37ae8800501c1b8544f5005cd367e8ca` | 1.81.1 | `academy_world_v0-v3` | pending verification |
| `academy_triex_v0` | 2 | `0x2e49717cc0398543b24e905d32a6d406152d78c1b75b97825e2d529672602e9f` | `0xd1aba1014d8eabd09fe5b01be0ec79faffee4a449922dd54c9d85910c0c83533` | 1.81.1 | `academy_triex_v0-v2` | pending verification |
| `academy_arcade` | 2 | `0x3a357b3ff6a86de30135917968d555b07fc7f82e23052cfd0346f7b329ad104b` | `0xab6df728817087e90540bb3392ad2352f5d30f365e4f830fa92c5003d9e1472b` | 1.81.1 | `academy_arcade-v2` | [verified](https://suiscan.xyz/testnet/object/0x3a357b3ff6a86de30135917968d555b07fc7f82e23052cfd0346f7b329ad104b/contracts) |
<!-- versions:end -->

"verified" links to the explorer page where the source was checked against the chain. "pending verification" means the explorer verifier does not accept the package yet: Suiscan currently verifies only packages without dependencies, and these four depend on `academy_core`. Until then, check them yourself with the steps under "Build and verify yourself". Earlier testnet versions are not published.

## Function map

<!-- function-map:start -->
What the site asks you to sign, and what each call can and cannot do. All calls of one action go into a single transaction (PTB): if any check fails, nothing happens.

**Claiming a quest** (the site pays gas through my sponsor):

| Call | What it does | What it cannot do |
|---|---|---|
| `academy_core::core::begin_claim` | Opens a claim ticket for an active quest. | Change the quest; the ticket cannot be stored, it must be finished in the same transaction. |
| `academy_world_v0::world_v0::bind` | Binds your character to the ticket. Aborts unless you, the signer, own the character. | Bind someone else's character or send rewards to another wallet: the recipient is the signer. |
| `world_v0::check_*`, `academy_triex_v0::triex_v0::check_triex_trade` | Read-only checks of the quest condition: a node or structure online (with its `OwnerCap`, borrowed from your character via `world::character::borrow_owner_cap` and returned in the same transaction), a kill, tribe membership, a trade on Trinary Exchange. | Modify or move your structures, characters or trading account: they are passed by immutable reference. |
| `academy_core::core::prove_prereq` | Proves a prerequisite quest was completed. | Anything beyond reading the prerequisite quest. |
| `academy_core::core::complete` | Marks the quest as claimed by your character and your wallet (once each) and issues a reward ticket. | Complete it twice, or with checks or prerequisites still pending. |
| `academy_rewards::badge::issue` | Mints a soulbound badge to you. | Be transferred or sold: `Badge` has no `store`; only you can burn it. |
| `academy_rewards::coin_pool::pay` | Pays a coin reward from the academy's pool to you. | Take coins from you: it only moves coins from the pool to the reward recipient. |
| `academy_gas::gas_budget::charge` | Moves the gas cost of a sponsored claim from the academy's gas budget to the sponsor. Works only in a transaction sponsored by the configured sponsor, capped per claim, once per transaction. | Touch your coins. |
| `academy_core::core::finish` | Closes the reward ticket. Aborts if any reward was not paid. | Anything else. |

**Arcade**:

| Call | What it does | What it cannot do |
|---|---|---|
| `academy_arcade::arcade::pay_attempt` | Pays the exact attempt price from the coin you pass: one part goes to the weekly prize bank, one to the cycle bank, the rest to the arcade owner. | Charge more than the published price: it aborts if the coin value differs from `price`. |
| `academy_arcade::arcade::fund_cycle` | Adds coins to the cycle prize bank (anyone can donate). | Be taken back by the donor. |

**Academy authors** (only for people who run an academy; they sign with their own wallet): `core::create_academy`, `create_quest`, `set_*`, `add_prerequisite` / `remove_prerequisite`, `coin_pool::create` / `fund` / `withdraw`, `gas_budget::create_budget` / `deposit` / `withdraw` / `withdraw_all`. Withdrawals require that academy's `AcademyAdminCap`, so an author can only withdraw from their own academy. `verified_checks::add` (registering a new check type) requires my `PlatformAdminCap`.
<!-- function-map:end -->

## Is this badge really from Lagrange?

The packages are open infrastructure: anyone can create their own academy and issue a `Badge` from them. A badge type alone proves nothing. A Lagrange badge is an object whose type is `0xd239eebc3fb6b1a98653451e1303112b8b361fdf5823cff3c1231abd57eaa400::badge::Badge` **and** whose `academy_id` is one of my academies:

- `0x78a05693f7f23289543ac61ff3ac9bd21eced0f5b4b2841f1911fc9c6b8f3874`
- `0x9c7ee5cc5f93b8b853172066eb2c96665fbfab545519849aad631ce8762d0092`

A badge of the right type with another `academy_id` was issued by another academy. A type from any other package is not mine at all. You can check any object at `https://lagrange.social/verify/<object id>`.

## Official places

- Website: https://lagrange.social (no other domain is mine)
- Discord: https://discord.com/users/426798790662684672
- Discussion thread: https://discord.com/channels/1021714190102175754/1552755213532663969

## Upgrades

I hold the `UpgradeCap` of every package, with the default `compatible` policy, so I can ship bug fixes. Compatible upgrades cannot change existing public function signatures or struct layouts, but they can change function bodies. My commitment: every upgrade gets a new tag here and is submitted for source verification before I announce it.

| Package | UpgradeCap |
|---|---|
| `academy_core` | `0x9ef3f41f1f52edd4ecd678542f83d9a32cdded869a3827e8f208cbc8cb64d226` |
| `academy_rewards` | `0x06a3f556dfd6109cd68a9e767e6437ca1c7d127dd544ce220bc58343253ed09f` |
| `academy_world_v0` | `0x1575a77edb59be8b347af23edb707a01c8bf91e1e4588d0f08a4f054295a67a7` |
| `academy_gas` | `0x14aa07dfd92c95abf988d6559d486df3e80e85196da45b226064a883ef1db3c5` |
| `academy_arcade` | `0x84ae82caaad69f65e886bedc7dedf40379b5f7e0eff71a0483f42ff53a2e38bd` |
| `academy_triex_v0` | `0xbec5f6ac80ac946e14bee419ff6d7c5e026871b80b2058d4276c42dbba84c290` |

## Build and verify yourself

You need the Sui CLI version from the Toolchain column (install it with [`suiup`](https://github.com/MystenLabs/suiup)).

```bash
git checkout <tag>
cd <package>
sui move build -e testnet_stillness --dump-bytecode-as-base64
sui move test
```

The build prints base64 modules. Compare them with the on-chain package (`Published at`), for example through the Sui GraphQL API (`object(address) { asMovePackage { modules { nodes { bytes } } } }`). One difference is expected: a local build writes the package's own address as `0x0`, while on chain it is the `Original ID`.

## License

Business Source License 1.1, see [LICENSE](LICENSE). You may read, build, test and verify this code. Deploying it or derivatives to any network is not permitted. On the Change Date the code becomes available under Apache 2.0.
