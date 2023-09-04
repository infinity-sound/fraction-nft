module infinity::events {
    use std::option::{Self,Option};
    use std::string::String;

    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object::{Object};
    use aptos_token_objects::collection as collectionv2;
    use aptos_token_objects::token as tokenv2;

    friend infinity::fraction_nft;
    /// Fractionize does not have EventsINF
    const ENO_EVENTS_INF: u64 = 1;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]

    struct TokenMetadata has key ,drop, store {
        creator_address: address,
        collection_name: String,
        collection: Option<Object<collectionv2::Collection>>,
        token_name: String,
        token: Option<Object<tokenv2::Token>>,
        property_version: Option<u64>
    }

    struct FungibleAssetMetadata has drop, store {
        name: String,
        symbol: String,
        decimals: u8,
    }

    struct TokenCreatedEvent has drop, store {
        token_metadata:TokenMetadata,
        fungible_asset_metadata: FungibleAssetMetadata,
        soul_bound_to:address,
    }
    
    struct TransferEvent has drop, store {
        from: address,
        to: address,
        amount: u64,
        inf_coin_amount:u64,
        fungible_asset_metadata: FungibleAssetMetadata,
    }

    struct EventsInf has key {
        create_token_events: EventHandle<TokenCreatedEvent>,
        transfer_fungible_asset_events: EventHandle<TransferEvent>
    }

    public(friend) fun init(creator:&signer) {
        let events = EventsInf {
            create_token_events: account::new_event_handle(creator),
            transfer_fungible_asset_events: account::new_event_handle(creator),
        };
        move_to(creator, events);
    }

    public(friend) fun emit_create_token_event(
        token_metadata:TokenMetadata,
        fungible_asset_metadata: FungibleAssetMetadata,
        soul_bound_to:address,
    ) acquires EventsInf {
        let infinity_events = borrow_global_mut<EventsInf>(@resource_addr);
        event::emit_event(&mut infinity_events.create_token_events, TokenCreatedEvent {
            token_metadata,
            fungible_asset_metadata,
            soul_bound_to,
        });
    }
    public(friend) fun emit_transfer_fungible_asset_event(
        from: address,
        to: address,
        amount: u64,
        inf_coin_amount:u64,
        fungible_asset_metadata: FungibleAssetMetadata,
    ) acquires EventsInf {
        let infinity_events = borrow_global_mut<EventsInf>(@resource_addr);
        event::emit_event(&mut infinity_events.transfer_fungible_asset_events, TransferEvent {
            from,
            to,
            amount,
            inf_coin_amount,
            fungible_asset_metadata,
        });
    }

    public fun token_metadata_for_tokenv2(token: Object<tokenv2::Token>): TokenMetadata {
        TokenMetadata {
            creator_address: tokenv2::creator(token),
            collection_name: tokenv2::collection_name(token),
            collection: option::some(tokenv2::collection_object(token)),
            token_name: tokenv2::name(token),
            token: option::some(token),
            property_version: option::none(),
        }
    }

    public fun fungible_asset_metadata(f_asset_obj:Object<Metadata>):FungibleAssetMetadata {
        FungibleAssetMetadata {
            name: fungible_asset::name(f_asset_obj),
            symbol: fungible_asset::symbol(f_asset_obj),
            decimals: fungible_asset::decimals(f_asset_obj),
        }
    }

}