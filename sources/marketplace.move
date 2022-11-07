module asuoki::marketplace {
        use sui::object::{Self, UID};
        use sui::transfer;
        use sui::tx_context::{Self, TxContext};
        use sui::coin::{Self, Coin};
        use sui::dynamic_field;

        struct Marketplace has key {
                id: UID,
        }

        struct List<T: key + store, phantom C> has key, store {
                seller: address,
                item: T,
                price: u64
        }


        fun init(_: &mut TxContext) {}

        public entry fun create(ctx: &mut TxContext) {
                let marketplace = Marketplace {
                        id: object::new(ctx),
                };
                transfer::share_object(marketplace);
        }

        public entry fun list_item<T: key + store, C>(mp: &mut Marketplace, item: T, item_address: address, price: u64, ctx: &mut TxContext) {
                let listing = List<T, C> {
                        seller: tx_context::sender(ctx),
                        item: item,
                        price: price
                };
                dynamic_field::add(&mut mp.id, item_address, listing);
        }

        public entry fun delist_item<T: key + store, C>(mp: &mut Marketplace, item_address: address, ctx: &mut TxContext) {
                let List<T, C> { seller, item, price: _ } = dynamic_field::remove(&mut mp.id, item_address);
                assert!(tx_context::sender(ctx) == seller, 126);
                transfer::transfer(item, tx_context::sender(ctx));
        }

        public entry fun buy_item<T: key + store, C>(mp: &mut Marketplace, item_address: address, paid: Coin<C>, ctx: &mut TxContext) { 
                let List<T, C> { seller, item, price } = dynamic_field::remove(&mut mp.id, item_address);
                assert!(price == coin::value(&paid), 127);
                transfer::transfer(paid, seller);
                transfer::transfer(item, tx_context::sender(ctx));
        }
}

#[test_only]
module asuoki::marketplaceTests {
        use sui::object::{Self, UID};
        use sui::transfer;
        use sui::coin::{Self, Coin};
        use sui::sui::SUI;
        use sui::test_scenario::{Self, Scenario};
        use asuoki::marketplace::{Self, Marketplace};

        struct NFT has key, store {
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
                marketplace::list_item<NFT, SUI>(mkp, nft, ITEM, 1000, test_scenario::ctx(scenario));
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
                marketplace::list_item<NFT, SUI>(mkp, nft, ITEM, 1000, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::next_tx(scenario, SELLER);
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                marketplace::delist_item<NFT, SUI>(mkp, ITEM, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::end(scenario_val);
        }

        #[test]
        fun buy() {
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
                marketplace::list_item<NFT, SUI>(mkp, nft, ITEM, 1000, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);

                test_scenario::next_tx(scenario, BUYER);
                let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);

                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                
                let payment = coin::take(coin::balance_mut(&mut coin), 1000, test_scenario::ctx(scenario));
                
                marketplace::buy_item<NFT, SUI>(mkp, ITEM, payment, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::return_to_sender(scenario, coin);

                test_scenario::next_tx(scenario, BUYER);
                let nft = test_scenario::take_from_sender<NFT>(scenario);
                let nft_id = burn_kitty(nft);
                assert!(nft_id == 1, 0);
                
                test_scenario::end(scenario_val);
        }

        #[test]
        #[expected_failure(abort_code = 127)]
        fun fall_buy() {
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
                marketplace::list_item<NFT, SUI>(mkp, nft, ITEM, 1000, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);

                test_scenario::next_tx(scenario, BUYER);
                let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);

                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                
                let payment = coin::take(coin::balance_mut(&mut coin), 100, test_scenario::ctx(scenario));
                
                marketplace::buy_item<NFT, SUI>(mkp, ITEM, payment, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::return_to_sender(scenario, coin);

                test_scenario::next_tx(scenario, BUYER);
                let nft = test_scenario::take_from_sender<NFT>(scenario);
                let nft_id = burn_kitty(nft);
                assert!(nft_id == 1, 0);
                
                test_scenario::end(scenario_val);
        }

        #[test]
        #[expected_failure(abort_code = 126)]
        fun fall_delist() {
                use sui::test_scenario;
                let scenario_val = test_scenario::begin(ADMIN);
                let scenario = &mut scenario_val;
                create_marketplace(scenario);
                mint_kitty(scenario);
                test_scenario::next_tx(scenario, SELLER);
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                let nft = test_scenario::take_from_sender<NFT>(scenario);
                marketplace::list_item<NFT, SUI>(mkp, nft, ITEM, 1000, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::next_tx(scenario, BUYER);
                let market = test_scenario::take_shared<Marketplace>(scenario);
                let mkp = &mut market;
                marketplace::delist_item<NFT, SUI>(mkp, ITEM, test_scenario::ctx(scenario));
                test_scenario::return_shared(market);
                test_scenario::end(scenario_val);
        }


}