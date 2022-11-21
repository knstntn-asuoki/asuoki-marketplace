# Asuoki Marketplace
## Deploy
```bash
$ sui client publish --path . --gas-budget 1000 
$ sui client call --package {package address} --module marketplace --function create --gas-budget 1000
```
## Listing
```bash
$ sui client call --package {package address} \
  --module marketplace \
  --function list_item \
  --type-args 0x2::devnet_nft::DevNetNFT \
  --args {shared auction} {item address} {price} \
  --gas-budget 1000
```

## Make offer
```bash
$ sui client call --package {package address} \
  --module marketplace \
  --function make_offer \
  --type-args 0x2::devnet_nft::DevNetNFT \
  --args {shared auction} {item address} {coin address} \
  --gas-budget 1000
```

## Accept offer
```bash
$ sui client call --package {package address} \
  --module marketplace \
  --function accept_offer \
  --type-args 0x2::devnet_nft::DevNetNFT \
  --args {shared auction} {item address} {offer id} \
  --gas-budget 1000
```
