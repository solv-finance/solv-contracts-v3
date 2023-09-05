# solv-contracts-v3

Solv Protocol is a Web3 liquidity infrastructure that utilizes Solv Payable, a full-suite semi-fungible token solution to enable institutional entities and retail users to access liquidity by creating, issuing, or trading semi-fungible tokens in a zero-trust and transparent way. 

This is the repository for core smart contracts of the Solv Protocol V3 products, including different types of SFTs and the markets for issuing and trading SFTs. 

## Structure

### commons

[`commons`](./commons) contains generic smart contracts and scripts used for developments and deployments of other smart contracts.

- [`address-resolver`](./commons/address-resolver): Generic smart contracts that provides the abilities to store and retrieve addresses of smart contracts according to their names.

- [`solidity-utils`](./commons/solidity-utils): Util smart contracts and libraries that can be imported by other smart contracts.

### markets

[`markets`](./markets) contains smart contracts for issuing and trading SFTs. 

- [`prime`](./markets/prime): Smart contracts for Solv Closed-end Fund Market, a platform for issuing and subscribing Payable SFTs.

    - [`price`](./markets/prime/price): Price strategy module of Closed-end Fund Market, allowing the market to support different price strategies, such as Fixed-Price strategy, Declining-Price strategy, etc.

    - [`whitelist`](./markets/prime/whitelist): Whitelist strategy module of Closed-end Fund Market, allowing any issuer to set whitelist for the subscription of an issuance.

- [`open-fund-market`](./markets/open-fund-market): Smart contracts for Solv Open-end Fund Market, a platform for issuing and subscribing Open-end Fund.

    - [`whitelist`](./markets/open-fund-market/whitelist): Whitelist strategy module of Payable Market, allowing any issuer to set whitelist for the subscription of an issuance.

    - [`oracle`](./markets/open-fund-market/oracle): Nav oracle module of Payable Market, allowing nav manager to set nav for the fund.

### sft

[`sft`](./sft) contains smart contracts for a series of SFTs, along with the ability module contracts that describes different aspects of abilities of SFTs.

- [`core`](./sft/core): A basic implementation of SFT, which is split into two smart contracts. The BaseSFTDelegate contract is an extension implementation of ERC3525, while the BaseSFTConcrete contract is designed to implement the specific product logic of an SFT.

- [`abilities`](./sft/abilities): Smart contracts representing different kinds of abilities of SFT contracts. SFT contracts that would like to provide any ability can directly inherit the corresponding ability contract.

    - [`issuable`](./sft/abilities/issuable): Represents SFTs that can only be minted by IssueMarket.

    - [`lockable`](./sft/abilities/lockable): Provides restrictions on token/value transferring at token or slot level.

    - [`mintable`](./sft/abilities/mintable): Represents SFTs that can be directly minted by users.

    - [`multi-rechargeable`](./sft/abilities/multi-rechargeable): Provides the ability for flow payment that allows multiple recharge and multiple withdrawals. Under this pattern, values will not be burnt when withdrawing from a token.

    - [`multi-repayable`](./sft/abilities/multi-repayable): Provides the basic ability of Payable Token that allow issuers (borrowers) to repay in multiple installments.

    - [`slot-ownable`](./sft/abilities/slot-ownable): Provides the ability to set and check the owner of any slot.

- [`payable`](./sft/payable): Smart contracts for Solv Payable SFT products, including Earn SFT and Underwriter Profit SFT, etc.

    - [`earn`](./sft/payable/earn): Smart contracts for Solv Closed-end product, integrated with `issuable` and `multi-repayable` abilities. 

    - [`underwriter-profit`](./sft/payable/underwriter-profit): Smart contracts for Solv Underwriter Profit SFT product, integrated with `mintable`, `multi-rechargeable` and `slot-ownable` abilities.

    - [`open-fund`](./sft/payable/open-fund): Smart contracts for Solv Open-end Fund product, intergrated with `value-issuable`, `fcfs-multi-repayable`, `issuable` and `multi-repayable`.