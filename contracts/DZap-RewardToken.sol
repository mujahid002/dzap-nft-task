// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @custom:security-contact mujahidshaik2002@gmail.com
contract RewardToken is ERC20, ERC20Pausable, AccessControl {
    bytes32 public constant DZAP_STAKING_NFT_CONTRACT = keccak256("DZAP_STAKING_NFT_CONTRACT");

    constructor(address defaultAdmin, address dZapStakingNftContract)
        ERC20("MyToken", "MTK")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(DZAP_STAKING_NFT_CONTRACT, dZapStakingNftContract);
    }

    function pause() public onlyRole(DZAP_STAKING_NFT_CONTRACT) {
        _pause();
    }

    function unpause() public onlyRole(DZAP_STAKING_NFT_CONTRACT) {
        _unpause();
    }

    function mintRewardToken(address to, uint256 amount) public onlyRole(DZAP_STAKING_NFT_CONTRACT) {
        _mint(to, amount);
    }
    function burnRewardToken(address from, uint256 amount) public onlyRole(DZAP_STAKING_NFT_CONTRACT) {
        _burn(from,amount);
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
