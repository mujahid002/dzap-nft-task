# dzap-nft-task

## Contracts

Deploying DZapNfts Contract...
DZapNfts Contract Address: 0x05203d191dda7dba3a3130eb2b3cd85593f7fc07
Link: https://amoy.polygonscan.com/address/0x05203d191dda7dba3a3130eb2b3cd85593f7fc07#code

---

Deploying DZapStaking Contract...
DZapStaking Contract Address: 0x91Ce856e9eFB78b57002Ff2E88C80b856F893138
Link:
Implementation Contract: https://amoy.polygonscan.com/address/0x8edffa01e86b1f039b6c168b7f8813169a662364#code
Proxy Contract: https://amoy.polygonscan.com/address/0x91Ce856e9eFB78b57002Ff2E88C80b856F893138#code

---

Deploying DZapRewardToken Contract...
DZapRewardToken Contract Address: 0xab2233d19dc0e2C48125Fca7A2D72B14Af2C0F4F
Link: https://amoy.polygonscan.com/address/0xab2233d19dc0e2C48125Fca7A2D72B14Af2C0F4F#code

---


## Flowchart
![Flowchart](image.png)

1. User(DZap NFT Owner) need to approve DZap-Staking Contract with TokenId(or multiple).
2. After Approving user can stake TokenId where DZap-Staking tranfer & lock within contract itself. State Variables updated.
3. User can claim rewards based on Staking from DZap-Staking contract(i.e where it interacts with Reward Token contract, it mints tokens only by DZap-Staking contract).
4. User can unstake anytime and unbounding period starts(i.e for 1 day), after one day user can withdraw reward tokens(Rewards not generated after unbounding period starts).
5. After unbounding period user can withdraw their respective NFTs.

### Another Idea: DZap-Staking can be implemented using the reference ERC-4626 (Extended ERC-20, Tokenized vault interface) 
