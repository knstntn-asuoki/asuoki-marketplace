module asuoki::marketplace {
        use sui::object::{Self, ID, UID};
        use sui::transfer;
        use sui::tx_context::{Self, TxContext};
        use sui::coin::{Self, Coin};
        use sui::dynamic_field;
        use sui::sui::SUI;
        use asuoki::auction_lib::{Self, Auction};
        //use asuoki::swap_lib::{Self, Swap};

        const EWrongOwner: u64 = 1;

        struct Offer<C: key + store> has store, key {
                id: UID,
                status: u64,
                offer_id: u64,
                paid: C,
                offerer: address,
        }

        struct DeletedOffer has store, key {
                id: UID,
                status: u64,
                offer_id: u64,
                offerer: address,
        }

        struct Marketplace has key {
                id: UID,
        }

        struct List<T: key + store> has store, key {
                id: UID,
                seller: address,
                item: T,
                price: u64,
                last_offer_id: u64,
        }


        fun init(_: &mut TxContext) {}

        public entry fun create(ctx: &mut TxContext) {
                let marketplace = Marketplace {
                        id: object::new(ctx),
                };
                transfer::share_object(marketplace);
        }

        public entry fun list_item<T: store + key>(mp: &mut Marketplace, item: T, price: u64, ctx: &mut TxContext) {
                let item_id = object::id(&item);
                let listing = List<T> {
                        id: object::new(ctx),
                        seller: tx_context::sender(ctx),
                        item: item,
                        price: price,
                        last_offer_id: 0,
                };
                dynamic_field::add(&mut mp.id, item_id, listing);
        }

        public entry fun delist_item<T: store + key>(mp: &mut Marketplace, item_id: ID, ctx: &mut TxContext) {
                let List<T> { id, seller, item, price: _, last_offer_id: _ } = dynamic_field::remove(&mut mp.id, item_id);
                assert!(tx_context::sender(ctx) == seller, 126);
                object::delete(id);
                transfer::transfer(item, tx_context::sender(ctx));
        }

        public entry fun make_offer<T: store + key>(mp: &mut Marketplace, item_id: ID, coin: Coin<SUI>, ctx: &mut TxContext) {
                let List<T> { id, seller, item, price, last_offer_id } = dynamic_field::remove(&mut mp.id, item_id);
                let offer = Offer<Coin<SUI>> {
                        id: object::new(ctx), 
                        status: 0,
                        offer_id: last_offer_id + 1,
                        paid: coin,
                        offerer: tx_context::sender(ctx),
                };
                let new_list = List<T> {
                        id: id,
                        seller: seller,
                        item: item,
                        price: price,
                        last_offer_id: last_offer_id + 1,
                };

                dynamic_field::add(&mut new_list.id, last_offer_id + 1, offer);  
                dynamic_field::add(&mut mp.id, item_id, new_list);              
        }

        public entry fun delete_offer<T: store + key>(mp: &mut Marketplace, item_id: ID, offer_id: u64, ctx: &mut TxContext) {
                let List<T> { id, seller, item, price, last_offer_id } = dynamic_field::remove(&mut mp.id, item_id);
                let Offer<Coin<SUI>> {id: idOffer, status,  offer_id: _, paid, offerer } = dynamic_field::remove(&mut id, offer_id);
                assert!(tx_context::sender(ctx) == offerer, 126);
                assert!(status == 0, 126);
                let offer = DeletedOffer {
                        id: idOffer, 
                        status: 1,
                        offer_id: offer_id,
                        offerer: offerer,
                };
                //object::delete(idOffer);
                transfer::transfer(paid, tx_context::sender(ctx));
                let new_list = List<T> {
                        id: id,
                        seller: seller,
                        item: item,
                        price: price,
                        last_offer_id: last_offer_id,
                };
                dynamic_field::add(&mut new_list.id, offer_id, offer);  
                dynamic_field::add(&mut mp.id, item_id, new_list); 
        }

        public entry fun accept_offer<T: store + key>(mp: &mut Marketplace, item_id: ID, offer_id: u64, ctx: &mut TxContext) { 
                let List<T> { id, seller, item, price: _, last_offer_id: _ } = dynamic_field::remove(&mut mp.id, item_id);
                assert!(tx_context::sender(ctx) == seller, 126);
                let Offer<Coin<SUI>> {id: idOffer, status, offer_id: _, paid, offerer } = dynamic_field::remove(&mut id, offer_id);
                assert!(status == 0, 126);
                transfer::transfer(paid, seller);
                transfer::transfer(item, offerer);
                object::delete(idOffer);
                object::delete(id);
        } 

        public fun get_seller<T: store + key>(old_listing: &List<T>): &address {
                &old_listing.seller
        }

        public fun get_price<T: store + key>(old_listing: &List<T>): &u64 {
                &old_listing.price
        }

        public fun get_last_offer_id<T: store + key>(old_listing: &List<T>): &u64 {
                &old_listing.last_offer_id
        }

        public entry fun create_auction<T: key + store >(to_sell: T, ctx: &mut TxContext) {
                let auction = auction_lib::create_auction(object::new(ctx), to_sell, ctx);
                auction_lib::share_object(auction);
        }

        public entry fun bid<T: key + store>(coin: Coin<SUI>, auction: &mut Auction<T>, ctx: &mut TxContext) {
                auction_lib::update_auction(
                        auction,
                        tx_context::sender(ctx),
                        coin::into_balance(coin),
                        ctx
                );
        }

        public entry fun end_auction<T: key + store>(auction: &mut Auction<T>, ctx: &mut TxContext) {
                let owner = auction_lib::auction_owner(auction);
                assert!(tx_context::sender(ctx) == owner, EWrongOwner);
                auction_lib::end_shared_auction(auction, ctx);
        }        
}

#[test_only]
module asuoki::marketplaceTests {
        use sui::object::{Self, UID};
        use sui::transfer;
        use sui::coin::{Self, Coin};
        //use sui::coin;
        use sui::sui::SUI;
        use sui::test_scenario::{Self, Scenario};
        use asuoki::marketplace::{Self, Marketplace};

        struct NFT has store, key {
                id: UID,
                kitty_id: u8
        }

        const ADMIN: address = @0xA55;
        const SELLER: address = @0x00A;
        const BUYER: address = @0x00B;
        const ITEM: address = @0x01B;

        fun create_marketplace(scenario: &mut Scenario) {
                test_scenario::next_tx(scenario, ADMIN);
                marketplace::create(test_scenario::ctx(scenario));
        }

        fun mint_some_coin(scenario: &mut Scenario) {
                test_scenario::next_tx(scenario, ADMIN);
                let coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
                transfer::transfer(coin, BUYER);
        }

        fun mint_kitty(scenario: &mut Scenario) {
                test_scenario::next_tx(scenario, ADMIN);
                let nft = NFT { id: object::new(test_scenario::ctx(scenario)), kitty_id: 1 };
                transfer::transfer(nft, SELLER);
        }     

        fun burn_kitty(kitty: NFT): u8 {
                let NFT{ id, kitty_id } = kitty;
                object::delete(id);
                kitty_id
        }

        #[test]
        fun init_market(){
                use sui::test_scenario;
                let scenario_val = test_scenario::begin(ADMIN);
                let scenario = &mut scenario_val;
                create_marketplace(scenario);
                test_scenario::end(scenario_val);
        }

        #[test]
        fun list_item(){
                use sui::test_scenario;
                let scenario_val = test_scenario::begin(ADMIN);
                let scenario = &mut scenario_val;
                create_marketplace(scenario);
                mint_kitty(scenario);
                test_scenario::next_tx(scenario, SELLER);
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                let nft = test_scenario::take_from_sender<NFT>(scenario);
                marketplace::list_item<NFT>(mkp, nft, 1000, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::end(scenario_val);
        }

        #[test]
        fun delist_item(){
                use sui::test_scenario;
                let scenario_val = test_scenario::begin(ADMIN);
                let scenario = &mut scenario_val;
                create_marketplace(scenario);
                mint_kitty(scenario);
                test_scenario::next_tx(scenario, SELLER);
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                let nft = test_scenario::take_from_sender<NFT>(scenario);
                let item_id = object::id(&nft);
                marketplace::list_item<NFT>(mkp, nft, 1000, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::next_tx(scenario, SELLER);
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                marketplace::delist_item<NFT>(mkp, item_id, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::end(scenario_val);
        }

        #[test]
        fun make_offer() {
                use sui::test_scenario;
                let scenario_val = test_scenario::begin(ADMIN);
                let scenario = &mut scenario_val;
                create_marketplace(scenario);
                mint_kitty(scenario);
                mint_some_coin(scenario);
                
                test_scenario::next_tx(scenario, SELLER);
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                let nft = test_scenario::take_from_sender<NFT>(scenario);
                let item_id = object::id(&nft);
                marketplace::list_item<NFT>(mkp, nft, 1000, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);

                test_scenario::next_tx(scenario, BUYER);
                let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
                
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                
                let payment = coin::take(coin::balance_mut(&mut coin), 1000, test_scenario::ctx(scenario));

                marketplace::make_offer<NFT>(mkp, item_id, payment, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::return_to_sender(scenario, coin);
                test_scenario::end(scenario_val);
        }

        #[test]
        //#[expected_failure(abort_code = 127)]
        fun accept_offer() {
                use sui::test_scenario;
                let scenario_val = test_scenario::begin(ADMIN);
                let scenario = &mut scenario_val;
                create_marketplace(scenario);
                mint_kitty(scenario);
                mint_some_coin(scenario);
                
                test_scenario::next_tx(scenario, SELLER);
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                let nft = test_scenario::take_from_sender<NFT>(scenario);
                let item_id = object::id(&nft);
                marketplace::list_item<NFT>(mkp, nft, 1000, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);

                test_scenario::next_tx(scenario, BUYER);
                let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                let payment = coin::take(coin::balance_mut(&mut coin), 1000, test_scenario::ctx(scenario));
                marketplace::make_offer<NFT>(mkp, item_id, payment, test_scenario::ctx(scenario));

                test_scenario::next_tx(scenario, SELLER);
                marketplace::accept_offer<NFT>(mkp, item_id, 1, test_scenario::ctx(scenario));

                test_scenario::next_tx(scenario, BUYER);
                let nft = test_scenario::take_from_sender<NFT>(scenario);
                let nft_id = burn_kitty(nft);
                assert!(nft_id == 1, 0);

                test_scenario::return_shared(market);
                test_scenario::return_to_sender(scenario, coin);
                test_scenario::end(scenario_val);
        }
}