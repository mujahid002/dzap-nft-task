// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20, ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

error RewardToken__Unauthorized();

/// @custom:security-contact mujahidshaik2002@gmail.com
contract RewardToken is ERC20, ERC20Pausable {
    address private immutable s_dZapStakingContractAddress;

    constructor(address _dZapStakingNftContract)
        ERC20("DZapRewardToken", "DZRT")
    {
        s_dZapStakingContractAddress = _dZapStakingNftContract;
    }

     modifier onlyDZapStakingContract() {
        if (_msgSender() != s_dZapStakingContractAddress)
            revert RewardToken__Unauthorized();
        _;
    }

    function pause() public onlyDZapStakingContract {
        _pause();
    }

    function unpause() public onlyDZapStakingContract {
        _unpause();
    }

    function mint(address to, uint256 amount)
        public
        onlyDZapStakingContract
    {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount)
        public
        onlyDZapStakingContract
    {
        _burn(from, amount);
    }

    // The following functions are overrides required by Solidity.

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}
