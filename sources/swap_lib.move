/*
        @title: lib for swap nft 1v1
	@custom: version 1.0
	@author Konstantin Klyuchnikov (knstntn.asuoki.eth)
*/

module asuoki::swap_lib {
        use sui::object::{Self, ID, UID};
        use sui::tx_context::{Self, TxContext};
        use sui::transfer;
        use sui::dynamic_field;  

        friend asuoki::marketplace;

        struct Swap<T: key + store> has key, store {
                id: UID,
                seller: address,
                item: T,
                last_offer_id: u64,
        }

        struct SwapOffer<T: key + store> has store, key {
                id: UID,
                status: u64,
                offer_id: u64,
                item: T,
                offerer: address,
        }

        struct Swap_Mechanism has key {
                id: UID,
        }

        public(friend) fun create_swap(ctx: &mut TxContext) {
                let swap_mechanism = Swap_Mechanism {
                        id: object::new(ctx),
                };
                transfer::share_object(swap_mechanism);
        }


        public(friend) fun swap<T: key + store>(sm: &mut Swap_Mechanism, item: T, ctx: &mut TxContext) {
                let item_id = object::id(&item);
                let listing = Swap<T> {
                        id: object::new(ctx),
                        seller: tx_context::sender(ctx),
                        item: item,
                        last_offer_id: 0,
                };
                dynamic_field::add(&mut sm.id, item_id, listing);
        }

        public(friend) fun deswap<T: store + key>(sm: &mut Swap_Mechanism, item_id: ID, ctx: &mut TxContext) {
                let Swap<T> { id, seller, item, last_offer_id: _ } = dynamic_field::remove(&mut sm.id, item_id);
                assert!(tx_context::sender(ctx) == seller, 126);
                object::delete(id);
                transfer::transfer(item, tx_context::sender(ctx));
        }

        public(friend) fun make_offer_swap<T: store + key>(sm: &mut Swap_Mechanism, item_id: ID, item: T, ctx: &mut TxContext) {
                let Swap<T> { id, seller, item: item_req, last_offer_id } = dynamic_field::remove(&mut sm.id, item_id);
                let offer = SwapOffer<T> {
                        id: object::new(ctx), 
                        status: 0,
                        offer_id: last_offer_id + 1,
                        item: item,
                        offerer: tx_context::sender(ctx),
                };
                let new_list = Swap<T> {
                        id: id,
                        seller: seller,
                        item: item_req ,
                        last_offer_id: last_offer_id + 1,
                };
                dynamic_field::add(&mut new_list.id, last_offer_id + 1, offer);  
                dynamic_field::add(&mut sm.id, item_id, new_list);              
        }

        public(friend) fun delete_offer_swap<T: store + key + copy>(sm: &mut Swap_Mechanism, item_id: ID, offer_id: u64, ctx: &mut TxContext) {
                let Swap<T> { id, seller, item, last_offer_id } = dynamic_field::remove(&mut sm.id, item_id);
                let SwapOffer<T> {id: idOffer, status, offer_id: _, item: item_offer, offerer } = dynamic_field::remove(&mut id, offer_id);
                assert!(tx_context::sender(ctx) == offerer, 126);
                assert!(status == 0, 126);
                let offer = SwapOffer<T> {
                        id: idOffer, 
                        status: 1,
                        offer_id: offer_id,
                        item: item_offer,
                        offerer: offerer,
                };
                transfer::transfer(item, tx_context::sender(ctx));
                let new_list = Swap<T> {
                        id: id,
                        seller: seller,
                        item: item,
                        last_offer_id: last_offer_id,
                };
                dynamic_field::add(&mut new_list.id, offer_id, offer);
                dynamic_field::add(&mut sm.id, item_id, new_list); 
        }

        public(friend) fun accept_offer_swap<T: store + key>(sm: &mut Swap_Mechanism, item_id: ID, offer_id: u64, ctx: &mut TxContext) { 
                let Swap<T> { id, seller, item, last_offer_id: _ } = dynamic_field::remove(&mut sm.id, item_id);
                assert!(tx_context::sender(ctx) == seller, 126);
                let SwapOffer<T> {id: idOffer, status, offer_id: _, item: item_offer, offerer } = dynamic_field::remove(&mut id, offer_id);
                assert!(status == 0, 126);
                transfer::transfer(item_offer, seller);
                transfer::transfer(item, offerer);
                object::delete(idOffer);
                object::delete(id);
        }
}