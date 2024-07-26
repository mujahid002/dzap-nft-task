// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// Custom errors for more efficient error handling
error DZapStaking__NftNotAllowedByOwner();
error DZapStaking__NftNotStaked();
error DZapStaking__NftNotUnStaked();
error DZapStaking__UnbondingPeriodNotOver();
error DZapStaking__UnableToCallRewardTokenContract();

/// @title DZapStaking
/// @notice This contract allows users to stake their NFTs to earn rewards in ERC20 tokens.
contract DZapStaking is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    /*****************************
            STATE VARIABLES
    ******************************/
    /// @notice Struct to store staking information for each NFT
    struct StakeInfo {
        uint256 rewardDebt; // Accumulated reward up to the last update
        uint48 stakedAt; // Block number when the NFT was staked
        uint48 unbondingAt; // Block number when the NFT started unbonding
        bool unbonding; // Flag indicating if the NFT is in the unbonding process
    }

    /// VARIABLES
    /// @notice ERC721 token that users can stake
    IERC721 public s_stakingTokenContract;
    /// @notice ERC20 token used for rewards
    address public s_rewardTokenContractAddress;
    /// @notice Reward rate in ERC20 tokens per block
    uint256 public s_rewardRatePerBlock = 10 * 10**18;
    /// @notice Unbonding period in blocks before an unstaked NFT can be withdrawn
    uint48 public s_unbondingPeriod = 3 days;
    /// @notice Delay period in blocks before rewards can be claimed again
    uint48 public s_rewardClaimDelay = 1 days;

    /// MAPPINGS
    /// @notice Mapping to store staking information for each user and their NFTs
    mapping(address => mapping(uint256 => StakeInfo)) public s_stakes;
    /// @notice Mapping to store a list of staked NFTs for each user
    mapping(address => uint256[]) public s_userStakes;

    /// EVENTS
    /// @notice Events to log staking, unstaking, and reward claiming activities
    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event RewardClaimed(address indexed user, uint256 amount);

    /// @dev Constructor to disable initializers
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the given parameters
    /// @param _rewardTokenContractAddress The ERC20 token used for rewards
    /// @param _stakingTokenContract The ERC721 token that users can stake
    function initialize(
        IERC721 _stakingTokenContract,
        address _rewardTokenContractAddress
    ) public initializer {
        s_stakingTokenContract = _stakingTokenContract;
        s_rewardTokenContractAddress = _rewardTokenContractAddress;
        __Pausable_init();
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
    }

    /*****************************
        STATE UPDATE FUNCTIONS
    ******************************/
    /// @notice Allows users to stake multiple NFTs
    /// @param tokenIds The IDs of the NFTs to stake
    function stake(uint256[] calldata tokenIds) public whenNotPaused {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            s_stakingTokenContract.transferFrom(
                _msgSender(),
                address(this),
                tokenId
            );

            s_stakes[_msgSender()][tokenId] = StakeInfo({
                stakedAt: uint48(block.number),
                unbondingAt: 0,
                rewardDebt: 0,
                unbonding: false
            });

            s_userStakes[_msgSender()].push(tokenId);
            emit Staked(_msgSender(), tokenId);
        }
    }

    /// @notice Allows users to unstake specific NFTs, initiating the unbonding process
    /// @param tokenIds The IDs of the NFTs to unstake
    function unstake(uint256[] calldata tokenIds) public {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            _updateReward(_msgSender(), tokenId);

            StakeInfo storage stakeInfo = s_stakes[_msgSender()][tokenId];

            if (stakeInfo.stakedAt <= 0) revert DZapStaking__NftNotStaked();

            stakeInfo.unbondingAt = uint48(block.number);
            stakeInfo.unbonding = true;
            emit Unstaked(_msgSender(), tokenId);
        }
    }

    /// @notice Allows users to withdraw NFTs after the unbonding period has passed
    /// @param tokenIds The IDs of the NFTs to withdraw
    function withdraw(uint256[] calldata tokenIds) public {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            _updateReward(_msgSender(), tokenId);

            StakeInfo storage stakeInfo = s_stakes[_msgSender()][tokenId];
            if (stakeInfo.unbondingAt <= 0)
                revert DZapStaking__NftNotUnStaked();

            if (
                uint48(block.number) < stakeInfo.unbondingAt + s_unbondingPeriod
            ) revert DZapStaking__UnbondingPeriodNotOver();

            delete s_stakes[_msgSender()][tokenId];
            _removeTokenId(_msgSender(), tokenId);
            s_stakingTokenContract.transferFrom(
                address(this),
                _msgSender(),
                tokenId
            );
        }
    }

    /// @notice Allows users to claim accumulated rewards for their staked NFTs
    /// @param tokenIds The IDs of the NFTs to claim rewards for
    function claimReward(uint256[] calldata tokenIds) public {
        uint256 totalReward = 0;
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            _updateReward(_msgSender(), tokenId);

            StakeInfo storage stakeInfo = s_stakes[_msgSender()][tokenId];
            if (stakeInfo.stakedAt <= 0) revert DZapStaking__NftNotStaked();

            if (
                uint48(block.number) >= stakeInfo.stakedAt + s_rewardClaimDelay
            ) {
                totalReward += earned(_msgSender(), tokenId);
                stakeInfo.rewardDebt = 0;
                stakeInfo.stakedAt = uint48(block.number);
            }
        }
        if (totalReward > 0) {
            (bool checkMint, ) = s_rewardTokenContractAddress.call(
                abi.encodeWithSignature(
                    "mint(address,uint256)",
                    _msgSender(),
                    totalReward
                )
            );
            if (!checkMint)
                revert DZapStaking__UnableToCallRewardTokenContract();

            emit RewardClaimed(_msgSender(), totalReward);
        }
    }

    /// @notice Calculates the rewards earned by a user for a specific staked NFT
    /// @param user The address of the user
    /// @param tokenId The ID of the staked NFT
    /// @return The amount of rewards earned
    function earned(address user, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        StakeInfo storage stakeInfo = s_stakes[user][tokenId];
        if (stakeInfo.stakedAt == 0 || stakeInfo.unbonding)
            return stakeInfo.rewardDebt;
        return
            (uint48(block.number) - stakeInfo.stakedAt) *
            s_rewardRatePerBlock +
            stakeInfo.rewardDebt;
    }

    /// @notice Allows the owner to update the reward rate per block
    /// @param newRewardRate The new reward rate per block
    function updateRewardRate(uint256 newRewardRate) public onlyOwner {
        s_rewardRatePerBlock = newRewardRate;
    }

    /// @notice Allows the owner to update the unbonding period
    /// @param newUnbondingPeriod The new unbonding period
    function updateUnbondingPeriod(uint48 newUnbondingPeriod) public onlyOwner {
        s_unbondingPeriod = newUnbondingPeriod;
    }

    /// @notice Allows the owner to update the reward claim delay
    /// @param newRewardClaimDelay The new reward claim delay
    function updateRewardClaimDelay(uint48 newRewardClaimDelay)
        public
        onlyOwner
    {
        s_rewardClaimDelay = newRewardClaimDelay;
    }

    /// @notice Allows the owner to pause the staking functionality
    function pause() public onlyOwner {
        _pause();
        (bool checkCall, ) = s_rewardTokenContractAddress.call(
            abi.encodeWithSignature("pause()")
        );
        if (!checkCall)
            revert DZapStaking__UnableToCallRewardTokenContract();
    }

    /// @notice Allows the owner to unpause the staking functionality
    function unpause() public onlyOwner {
        _unpause();
        (bool checkCall, ) = s_rewardTokenContractAddress.call(
            abi.encodeWithSignature("unpause()")
        );
        if (!checkCall)
            revert DZapStaking__UnableToCallRewardTokenContract();
    }

    /// @dev Authorizes contract upgrades, restricted to the contract owner
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /// @dev Updates the reward for a specific NFT
    /// @param user The address of the user
    /// @param tokenId The ID of the NFT to update the reward for
    function _updateReward(address user, uint256 tokenId) private {
        if (
            s_stakes[user][tokenId].stakedAt > 0 &&
            !s_stakes[user][tokenId].unbonding
        ) {
            s_stakes[user][tokenId].rewardDebt = earned(user, tokenId);
            s_stakes[user][tokenId].stakedAt = uint48(block.number);
        }
    }

    /// @dev Removes an NFT from the user's staked list
    /// @param user The address of the user
    /// @param tokenId The ID of the NFT to remove
    function _removeTokenId(address user, uint256 tokenId) private {
        uint256 length = s_userStakes[user].length;
        for (uint256 i = 0; i < length; ++i) {
            if (s_userStakes[user][i] == tokenId) {
                s_userStakes[user][i] = s_userStakes[user][length - 1];
                s_userStakes[user].pop();
                break;
            }
        }
    }
}
