# Scripts examples

## BRETT

```bash
npx hardhat simple-swap --owner 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199 --asset 0x532f27101965dd16442E59d40670FaF5eBB142E4 --network localhost
```

```bash
npx hardhat mint-nft-position --owner 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199 --asset 0x532f27101965dd16442E59d40670FaF5eBB142E4 --network localhost
```

```bash
npx hardhat transfer-nft --owner 0x32cf4d1df6fb7bB173183CF8b51EF9499c803634 --newowner 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199 --tokenid 888441
```

```bash
npx hardhat list-positions --owner 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199 --network localhost
```

## WEWE

```bash
npx hardhat simple-swap --owner 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199 --network localhost
```

```bash
npx hardhat mint-nft-position --owner 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199 --network localhost
```

```bash
npx hardhat list-positions --owner 0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199 --network localhost
```

# Deterministic State of the Blockchain Base

To perform the tests, the state of the blockchain needs to be deterministic. To achieve this:

- Set `FORKING_URL` variable in the `.env` file.
- In order to perform the tests correctly you may need to [impersonate the address](https://hardhat.org/hardhat-network/docs/guides/forking-other-networks#impersonating-accounts)

## Info about the state of the blockchain

- Blockchain: `Base`
- Block: `19197423`

- Address with WEWE / WETH: `0x38019bc40f504be4546f24083ccaf0c8553c408a`
- Block with the mint tx of the WEWE / WETH LP: `18720627`

- Address with WETH / USDC: `0xAd3B97c3C22B00C900fB04d47B3037E33f1d07d9`
- Block with the mint tx of the WETH / USDC LP: `19167068`

# Error codes
- INPM -> Invalid NonfungiblePositionManager address
- ISR -> Invalid SwapRouter address
- IA -> Invalid Arrakis V2 address
- IAR -> Invalid Arrakis V2 Resolver address
- ITM -> Invalid token to migrate address
- IUSDC -> Invalid USDC address
- NLP -> No liquidity in this LP
- INFT -> Invalid NFT: Does not have the correct token

## Contract addresses

| Contract | Address | Network |
| --- | --- | --- |
| NonfungiblePositionManager | 0xC36442b4a4522E871399CD717aBDD847Ab11FE88 | Base |
| SwapRouter | 0xE592427A0AEce92De3Edee1F18E0157C05861564 | Base |
| ArrakisV2 | 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984 | Base |
| Farm | 0xb1389D8A20B6be19111D4435Bd218a9F370472aB | Base |
| ChaosToken | 0xf901F4ec62590231f374cA7C5d34BbcA49B11d6B | Base |