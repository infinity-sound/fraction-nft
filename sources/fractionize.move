module infinity::fraction_nft {
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::coin;
    use std::error;
    use std::signer;
    use std::string::{String,utf8};
    use std::option;
    use aptos_token_objects::token;
    use aptos_framework::resource_account;
    use aptos_framework::account;

    use infinity::events;
    use infinity::infinity_token;
    use inf_custom_coin::inf_coin::{INFCOIN};



 


    const TOKEN_NAME: vector<u8> = b"M ALBUMS";
    const ASSET_SYMBOL: vector<u8> = b"CHK";
    const ASSET_NAME: vector<u8> = b"CHECK COIN";
    const COLLECTION_NAME: vector<u8> = b"CHECK ALBUM";

   /// Insufficient Resource (http: 400)
    const INSUFFICIENT_RESOURCE:u64=0xE;

    /// Only fungible asset metadata owner can make changes.
    const ENOT_OWNER: u64 = 1;
    /// Insufficient infinity token
     const ENOT_ENOUGH_COIN: u64=2;
    /// The collection does not exist
    const ECOLLECTION_DOES_NOT_EXIST: u64 = 3;
    /// The token does not exist
    const ETOKEN_DOES_NOT_EXIST: u64 = 4;
    /// Insufficient fungible asset
     const ENOT_ENOUGH_FA: u64=5;

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    /// Hold refs to control the minting, transfer and burning of fungible assets.
    struct ManagedFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
    }

    struct ResourceCap has key {
        resource_signer_cap:account::SignerCapability
    }

    struct OwnerConstraints has key {
        min_holding:u64,
        rate:u64,
    }

    // struct 


    fun init_module(resource_account: &signer) {
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_account, @source_addr);
        move_to(resource_account, ResourceCap {
            resource_signer_cap: resource_signer_cap,
        });     
        create_album_aptos_collection(resource_account);
        events::init(resource_account);
    }

     fun create_album_aptos_collection(creator: &signer) {
        infinity_token::create_collection(
            creator,
            utf8(b"Collection containing different types of albums. Each album is a separate token"),
            1000,
            utf8(COLLECTION_NAME),
            utf8(b"http:://collection.uri"), 
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            false,
            0,
            1,
        );
    }
    
    public entry fun init_token(
        admin: &signer,
        collection_name:String,
        description:String,
        asset_name:String,
        uri:String,
        token_name:String,
        token_symbol:String,
        maximum_supply:u128,
        decimals:u8,
        icon_uri:String,
        project_uri:String,
        receiver:address,
        min_holding:u64,
        rate:u64,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>
    ) acquires ResourceCap,ManagedFungibleAsset
    {       
        let resource_account_data = borrow_global_mut<ResourceCap>(@infinity);
        let resource_account_signer = account::create_signer_with_capability(&resource_account_data.resource_signer_cap);
        let constructor_ref=infinity_token::mint_soul_bound_infinity_token(
            &resource_account_signer,
            collection_name,
            description,
            asset_name,
            uri,
            property_keys,
            property_types,
            property_values,
            receiver
        );
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::some(maximum_supply),
            token_name,
            token_symbol, 
            decimals,
            icon_uri,
            project_uri
        );
        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constructor_ref);
        let metadata_object_signer = object::generate_signer(&constructor_ref);
        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset { mint_ref, transfer_ref, burn_ref }
        );
        move_to(
            &metadata_object_signer,
            OwnerConstraints { min_holding,rate }
        );
        mint(admin,1000,receiver,asset_name);
        let nft = object::object_from_constructor_ref(&constructor_ref);
        let tokenMetadata = events::token_metadata_for_tokenv2(nft);
        let asset = get_metadata(asset_name);
        let faMetadata = events::fungible_asset_metadata(asset);
        events::emit_create_token_event(tokenMetadata,faMetadata,receiver);
    }

    public entry fun update_min_holding(holder:&signer,asset_name:String,min_holding_amount:u64) acquires OwnerConstraints{
        let asset = get_metadata(asset_name);
        let holding = authorized_borrow_constraints(holder, asset);
        holding.min_holding= min_holding_amount;
    }

    public entry fun update_rate(holder:&signer,asset_name:String,rate:u64) acquires OwnerConstraints{
        let asset = get_metadata(asset_name);
        let holding = authorized_borrow_constraints(holder, asset);
        holding.rate= rate;
    }


    /// Mint as the owner of metadata object.
    fun mint(admin: &signer, amount: u64, receiver: address,asset_name:String) acquires ManagedFungibleAsset{
        let asset = get_metadata(asset_name);
        let managed_fungible_asset = authorized_borrow_refs(admin, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(receiver, asset);
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);
    }


    public entry fun buy_fungible_asset(requester:&signer,from:address,amount:u64,asset_name:String) acquires ManagedFungibleAsset,OwnerConstraints{
        let requester_address = signer::address_of(requester);
        let asset = get_metadata(asset_name);  
        assert!(object::is_owner(asset, from), error::permission_denied(ENOT_OWNER));
        let sender_min_holding = get_asset_min_holding(asset_name);
        let sender_rate = get_asset_rate(asset_name);
        let sender_balance = get_asset_balance(from,asset_name);
        let buy_limit = sender_balance-sender_min_holding;
        assert!(amount<=buy_limit,error::canonical(INSUFFICIENT_RESOURCE,ENOT_ENOUGH_FA));
        coin::transfer<INFCOIN>(requester,from,sender_rate*amount);
        transfer(from,requester_address,amount,asset_name,sender_rate*amount);

    }
    
    public entry fun transfer_fungible_asset(owner:&signer,to:address,amount:u64,asset_name:String) acquires ManagedFungibleAsset{
        let owner_address = signer::address_of(owner);
        transfer(owner_address,to,amount,asset_name,0);

    }
    /// Transfer as the owner of metadata object ignoring `frozen` field.
    inline fun transfer(from_address:address, to: address, amount: u64,asset_name:String,inf_amount:u64) acquires ManagedFungibleAsset {
        // let from_address = signer::address_of(admin);
        let asset = get_metadata(asset_name);  
        let transfer_ref = &borrow_global<ManagedFungibleAsset>(object::object_address(&asset)).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from_address, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        fungible_asset::transfer_with_ref(transfer_ref, from_wallet, to_wallet, amount);
        let fa_metadata = events::fungible_asset_metadata(asset);
        events::emit_transfer_fungible_asset_event(from_address,to,amount,inf_amount,fa_metadata);
    }

    // accessors

    /// Borrow the immutable reference of the refs of `metadata`.
    /// This validates that the signer is the metadata object's owner.
    inline fun authorized_borrow_refs(
        owner: &signer,
        asset: Object<Metadata>,
    ): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        assert!(object::is_owner(asset, signer::address_of(owner)), error::permission_denied(ENOT_OWNER));
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }

    /// Borrow the mutable reference of the refs of `metadata`.
    /// This validates that the signer is the metadata object's owner.
    inline fun authorized_borrow_constraints(
        owner: &signer,
        asset: Object<Metadata>,
    ): &mut OwnerConstraints acquires OwnerConstraints {
        assert!(object::is_owner(asset, signer::address_of(owner)), error::permission_denied(ENOT_OWNER));
        borrow_global_mut<OwnerConstraints>(object::object_address(&asset))
    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(asset:String) : Object<Metadata>  {
        let seed = token::create_token_seed(&utf8(COLLECTION_NAME), &asset);
        let asset_address = object::create_object_address(&@infinity, seed);
        object::address_to_object<Metadata>(asset_address)
    }

    #[view]
    public fun get_asset_balance(user:address,asset_name:String):u64  {
        let asset = get_metadata(asset_name);
        primary_fungible_store::balance(user, asset)
    }

    #[view]
    public fun get_asset_min_holding(asset_name:String):u64 acquires OwnerConstraints{
        let asset = get_metadata(asset_name);
        let holding = borrow_global<OwnerConstraints>(object::object_address(&asset)).min_holding;
        holding
    }

    #[view]
    public fun get_asset_rate(asset_name:String):u64 acquires OwnerConstraints{
        let asset = get_metadata(asset_name);
        let rate = borrow_global<OwnerConstraints>(object::object_address(&asset)).rate;
        rate
    }


    #[view]
    public fun get_asset_decimals(asset_name:String):u8  {
        let metadata_obj = get_metadata(asset_name);
        fungible_asset::decimals(metadata_obj)
    }
    #[view]
    public fun get_asset_symbol(asset_name:String):String  {
        let metadata_obj = get_metadata(asset_name);
        fungible_asset::symbol(metadata_obj)
    }

    #[test(creator = @infinity)]
    fun test_basic_flow(
        creator: &signer,
    ) acquires ManagedFungibleAsset,ResourceCap {
        init_module(creator);
        let creator_address = signer::address_of(creator);
        let aaron_address = @0xface;

        mint(creator, 100, creator_address);
        let asset = get_metadata();
        assert!(primary_fungible_store::balance(creator_address, asset) == 100, 4);
        transfer(creator, aaron_address, 10);
        assert!(primary_fungible_store::balance(aaron_address, asset) == 10, 6);
        assert!(!primary_fungible_store::is_frozen(creator_address, asset), 7);
        burn(creator, creator_address, 90);
    }

    #[test(creator = @fractionNFT, aaron = @0xface)]
    #[expected_failure(abort_code = 0x50001, location = Self)]
    fun test_permission_denied(
        creator: &signer,
        aaron: &signer
    ) acquires ManagedFungibleAsset {
        init_module(creator);
        let creator_address = signer::address_of(creator);
        mint(aaron, 100, creator_address);
    }
}