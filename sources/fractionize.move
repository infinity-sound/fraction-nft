module fractionNFT::Fraction {
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use std::error;
    use std::signer;
    use std::string::{String,utf8};
    use std::option;
    use aptos_token_objects::token;
    use aptos_token_objects::collection;
    use aptos_framework::resource_account;
    use aptos_framework::account;


    /// Only fungible asset metadata owner can make changes.
    const ENOT_OWNER: u64 = 1;
    const TOKEN_NAME: vector<u8> = b"M ALBUMS";
    const ASSET_SYMBOL: vector<u8> = b"CHK";
    const ASSET_NAME: vector<u8> = b"CHECK COIN";
    const COLLECTION_NAME: vector<u8> = b"CHECK ALBUM";

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

    fun init_module(resource_account: &signer) acquires ResourceCap{
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_account, @source_addr);
        move_to(resource_account, ResourceCap {
            resource_signer_cap: resource_signer_cap,
        });     
        create_album_collection(resource_account);
    }

   

    public entry fun create_album_collection(creator: &signer)acquires ResourceCap {
        let resource_account_data = borrow_global_mut<ResourceCap>(@fractionNFT);
        let resource_account_signer = account::create_signer_with_capability(&resource_account_data.resource_signer_cap);
        collection::create_unlimited_collection(
            &resource_account_signer,
            utf8(b"Collection containing different types of albums. Each album is a separate token"),
            utf8(COLLECTION_NAME), 
            option::none(),
            utf8(b"https://myalbum.com"),
        );
}
    /// Initialize metadata object and store the refs.

    public entry fun init_token(admin: &signer,collection_name:String,description:String,asset_name:String,uri:String,token_name:String,token_symbol:String,decimals:u8,icon_uri:String,project_uri:String,receiver:address) acquires ResourceCap,ManagedFungibleAsset {
        let admin_addr= signer::address_of(admin);
        assert!(admin_addr==@source_addr,1);
         let resource_account_data = borrow_global_mut<ResourceCap>(@fractionNFT);
        let resource_account_signer = account::create_signer_with_capability(&resource_account_data.resource_signer_cap);
        let constructor_ref = &token::create_named_token(
        &resource_account_signer,
        collection_name,
        description,
        asset_name,
        option::none(),
        uri,
        );
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::some(1000),
            token_name,
            token_symbol, 
            decimals,
            icon_uri,
            project_uri
        );
        // Create mint/burn/transfer refs to allow creator to manage the fungible asset.
        let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);
        let metadata_object_signer = object::generate_signer(constructor_ref);
        move_to(
            &metadata_object_signer,
            ManagedFungibleAsset { mint_ref, transfer_ref, burn_ref }
        );

        mint(admin,1000,receiver,asset_name);

    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(asset:String) : Object<Metadata>  {
        let seed = token::create_token_seed(&utf8(COLLECTION_NAME), &asset);
        let asset_address = object::create_object_address(&@fractionNFT, seed);
        object::address_to_object<Metadata>(asset_address)
    }

    #[view]
    public fun balance(user:address,asset_name:String):u64  {
        let asset = get_metadata(asset_name);
        primary_fungible_store::balance(user, asset)
    }

    // #[view]
    // public fun name():String  {
    //     let metadata_obj = get_metadata();
    //     fungible_asset::name(metadata_obj)
    // }

    #[view]
    public fun decimals(asset_name:String):u8  {
        let metadata_obj = get_metadata(asset_name);
        fungible_asset::decimals(metadata_obj)
    }
    #[view]
    public fun symbol(asset_name:String):String  {
        let metadata_obj = get_metadata(asset_name);
        fungible_asset::symbol(metadata_obj)
    }
   

    /// Mint as the owner of metadata object.
    fun mint(admin: &signer, amount: u64, receiver: address,asset_name:String) acquires ManagedFungibleAsset,ResourceCap{
        let admin_addr= signer::address_of(admin);
        assert!(admin_addr==@source_addr,1);
        let asset = get_metadata(asset_name);
        let resource_account_data = borrow_global_mut<ResourceCap>(@fractionNFT);
        let resource_account_signer = account::create_signer_with_capability(&resource_account_data.resource_signer_cap);
        let managed_fungible_asset = authorized_borrow_refs(&resource_account_signer, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(receiver, asset);
        let fa = fungible_asset::mint(&managed_fungible_asset.mint_ref, amount);
        fungible_asset::deposit_with_ref(&managed_fungible_asset.transfer_ref, to_wallet, fa);
    }

    /// Transfer as the owner of metadata object ignoring `frozen` field.
    public entry fun transfer(admin: &signer, to: address, amount: u64,asset_name:String) acquires ManagedFungibleAsset,ResourceCap {
        let from_address = signer::address_of(admin);
        let asset = get_metadata(asset_name);
        let resource_account_data = borrow_global_mut<ResourceCap>(@fractionNFT);
        let resource_account_signer = account::create_signer_with_capability(&resource_account_data.resource_signer_cap);
        let transfer_ref = &authorized_borrow_refs(&resource_account_signer, asset).transfer_ref;
        let from_wallet = primary_fungible_store::primary_store(from_address, asset);
        let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
        fungible_asset::transfer_with_ref(transfer_ref, from_wallet, to_wallet, amount);
    }

    // /// Burn fungible assets as the owner of metadata object.
    //  fun burn(admin: &signer, from: address, amount: u64) acquires ManagedFungibleAsset, {
    //     let asset = get_metadata();
    //     let burn_ref = &authorized_borrow_refs(admin, asset).burn_ref;
    //     let from_wallet = primary_fungible_store::primary_store(from, asset);
    //     fungible_asset::burn_from(burn_ref, from_wallet, amount);
    // }

    // /// Withdraw as the owner of metadata object ignoring `frozen` field.
    // public fun withdraw(admin: &signer, amount: u64, from: address): FungibleAsset acquires ManagedFungibleAsset ,{
    //     let asset = get_metadata();
    //     let transfer_ref = &authorized_borrow_refs(admin, asset).transfer_ref;
    //     let from_wallet = primary_fungible_store::primary_store(from, asset);
    //     fungible_asset::withdraw_with_ref(transfer_ref, from_wallet, amount)
    // }

    // /// Deposit as the owner of metadata object ignoring `frozen` field.
    // public fun deposit(admin: &signer, to: address, fa: FungibleAsset) acquires ManagedFungibleAsset ,{
    //     let asset = get_metadata();
    //     let transfer_ref = &authorized_borrow_refs(admin, asset).transfer_ref;
    //     let to_wallet = primary_fungible_store::ensure_primary_store_exists(to, asset);
    //     fungible_asset::deposit_with_ref(transfer_ref, to_wallet, fa);
    // }

    /// Borrow the immutable reference of the refs of `metadata`.
    /// This validates that the signer is the metadata object's owner.
    inline fun authorized_borrow_refs(
        owner: &signer,
        asset: Object<Metadata>,
    ): &ManagedFungibleAsset acquires ManagedFungibleAsset {
        assert!(object::is_owner(asset, signer::address_of(owner)), error::permission_denied(ENOT_OWNER));
        borrow_global<ManagedFungibleAsset>(object::object_address(&asset))
    }

    #[test(creator = @fractionNFT)]
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