// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// Custom errors for more efficient error handling
error DZapStaking__InvalidNftOwner();
error DZapStaking__NftNotAllowedByOwner();
error DZapStaking__NftNotStaked();
error DZapStaking__NftAlreadyUnStaked();
error DZapStaking__NftNotUnStaked();
error DZapStaking__UnbondingPeriodNotOver();
error DZapStaking__AlreadyRewardsClaimed();
error DZapStaking__DelayTimeNotExceeded();
error DZapStaking__ZeroRewardsToClaim();
error DZapStaking__ClaimRewardsBeforeWithdraw();
error DZapStaking__InvalidRewardTokenContract();
error DZapStaking__UnableToCallRewardTokenContract();

/// @title DZapStaking
/// @notice This contract allows users to stake their NFTs to earn rewards in ERC20 tokens.
contract DZapStaking is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*****************************
            STATE VARIABLES
    ******************************/

    /// VARIABLES
    /// @notice ERC721 token that users can stake
    IERC721 private s_stakingTokenContract;
    /// @notice ERC20 token used for rewards
    address private s_rewardTokenContractAddress;
    /// @notice Unbonding period in blocks before an unstaked NFT can be withdrawn
    uint256 private s_unbondingPeriod;
    /// @notice Delay period in blocks before rewards can be claimed again
    uint256 private s_rewardClaimDelay; //i.e 20 minutes
    /// @notice Reward rate in ERC20 tokens per block
    uint256 private s_rewardRatePerBlock;

    /// @notice Struct to store staking information for each NFT
    struct StakeInfo {
        uint256 stakedBlock;
        uint48 stakedSince;
        uint48 stakedUntil;
    }

    /// MAPPINGS
    /// @notice Mapping to store staking information for each user and their NFTs
    mapping(address => mapping(uint256 => StakeInfo)) private s_stakes;
    /// @notice Mapping to store a list of staked NFTs for each user
    mapping(address => uint256[]) private s_userStakes;

    /// EVENTS
    /// @notice Events to log staking, unstaking, and reward claiming activities
    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event RewardClaimed(address indexed user, uint256 amount);

    /// @dev Constructor to disable initializers
    // constructor() {
    //     _disableInitializers();
    // }

    /// @notice Initializes the contract with the given parameters
    /// @param _stakingTokenContract The ERC721 token that users can stake
    function initialize(
        IERC721 _stakingTokenContract,
        uint256 _unbondingPeriod,
        uint256 _rewardClaimDelay,
        uint256 _rewardRatePerBlock
    ) public initializer {
        s_stakingTokenContract = _stakingTokenContract;
        s_unbondingPeriod = _unbondingPeriod;
        s_rewardClaimDelay = _rewardClaimDelay;
        s_rewardRatePerBlock = _rewardRatePerBlock;
        __Pausable_init();
        __ReentrancyGuard_init();
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
    }

    /*****************************
        STATE UPDATE FUNCTIONS
    ******************************/
    /// @notice Allows users to stake multiple NFTs
    /// @param tokenIds The IDs of the NFTs to stake
    function stake(uint256[] calldata tokenIds)
        public
        whenNotPaused
        nonReentrant
    {
        uint256 length = tokenIds.length;

        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (s_stakingTokenContract.ownerOf(tokenId) != _msgSender())
                revert DZapStaking__InvalidNftOwner();
            if (s_stakingTokenContract.getApproved(tokenId) != address(this))
                revert DZapStaking__NftNotAllowedByOwner();
            s_stakingTokenContract.transferFrom(
                _msgSender(),
                address(this),
                tokenId
            );

            s_stakes[_msgSender()][tokenId] = StakeInfo({
                stakedBlock: block.number,
                stakedSince: uint48(block.timestamp),
                stakedUntil: 0
            });

            s_userStakes[_msgSender()].push(tokenId);
            emit Staked(_msgSender(), tokenId);
        }
    }

    /// @notice Allows users to unstake specific NFTs, initiating the unbonding process
    /// @param tokenIds The IDs of the NFTs to unstake
    function unstake(uint256[] calldata tokenIds)
        public
        whenNotPaused
        nonReentrant
    {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];

            StakeInfo storage stakeInfo = s_stakes[_msgSender()][tokenId];

            if (stakeInfo.stakedSince <= 0) revert DZapStaking__NftNotStaked();
            if (stakeInfo.stakedUntil != 0)
                revert DZapStaking__NftAlreadyUnStaked();

            stakeInfo.stakedUntil = uint48(block.timestamp);
            emit Unstaked(_msgSender(), tokenId);
        }
        _transferRewards(_msgSender(), tokenIds);
    }

    /// @notice Allows users to withdraw NFTs after the unbonding period has passed
    /// @param tokenIds The IDs of the NFTs to withdraw
    function withdraw(uint256[] calldata tokenIds)
        public
        whenNotPaused
        nonReentrant
    {
        uint256 length = tokenIds.length;

        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];

            StakeInfo storage stakeInfo = s_stakes[_msgSender()][tokenId];
            if (stakeInfo.stakedUntil <= 0)
                revert DZapStaking__NftNotUnStaked();

            if (
                uint48(block.timestamp) <
                stakeInfo.stakedUntil + s_unbondingPeriod
            ) revert DZapStaking__UnbondingPeriodNotOver();

            if (earned(_msgSender(), tokenId) > 0)
                revert DZapStaking__ClaimRewardsBeforeWithdraw();

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
    function claimReward(uint256[] calldata tokenIds)
        public
        whenNotPaused
        nonReentrant
    {
        if (s_rewardTokenContractAddress == address(0))
            revert DZapStaking__InvalidRewardTokenContract();
        uint256 length = tokenIds.length;

        uint256 totalReward = 0;
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];

            StakeInfo storage stakeInfo = s_stakes[_msgSender()][tokenId];
            if (stakeInfo.stakedSince <= 0) revert DZapStaking__NftNotStaked();

            if (stakeInfo.stakedUntil != 0)
                revert DZapStaking__AlreadyRewardsClaimed();
            if (
                uint48(block.timestamp) >=
                stakeInfo.stakedSince + s_rewardClaimDelay
            ) {
                totalReward += earned(_msgSender(), tokenId);
                stakeInfo.stakedBlock = block.number;
            } else {
                revert DZapStaking__DelayTimeNotExceeded();
            }
        }
        if (totalReward != 0) {
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
        } else {
            revert DZapStaking__ZeroRewardsToClaim();
        }
    }

    /// @notice Allows the owner to update the staking token contract
    /// @param newStakingTokenContract The new staking token contract address
    function updateStakingTokenContract(address newStakingTokenContract)
        public
        onlyOwner
    {
        s_stakingTokenContract = IERC721(newStakingTokenContract);
    }

    /// @notice Allows the owner to update the reward token contract address
    /// @param newRewardTokenContractAddress The new reward token contract address
    function updateRewardTokenContractAddress(
        address newRewardTokenContractAddress
    ) public onlyOwner {
        s_rewardTokenContractAddress = newRewardTokenContractAddress;
    }

    /// @notice Allows the owner to update the reward rate per block
    /// @param newRewardRate The new reward rate per block
    function updateRewardRate(uint256 newRewardRate) public onlyOwner {
        s_rewardRatePerBlock = newRewardRate;
    }

    /// @notice Allows the owner to update the unbonding period
    /// @param newUnbondingPeriod The new unbonding period
    function updateUnbondingPeriod(uint256 newUnbondingPeriod)
        public
        onlyOwner
    {
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
        if (!checkCall) revert DZapStaking__UnableToCallRewardTokenContract();
    }

    /// @notice Allows the owner to unpause the staking functionality
    function unpause() public onlyOwner {
        _unpause();
        (bool checkCall, ) = s_rewardTokenContractAddress.call(
            abi.encodeWithSignature("unpause()")
        );
        if (!checkCall) revert DZapStaking__UnableToCallRewardTokenContract();
    }

    /// @dev Authorizes contract upgrades, restricted to the contract owner
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /// @dev Removes an NFT from the user's staked list
    /// @param user The address of the user
    /// @param tokenId The ID of the NFT to remove
    function _removeTokenId(address user, uint256 tokenId) internal {
        uint256 length = s_userStakes[user].length;
        for (uint256 i = 0; i < length; ++i) {
            if (s_userStakes[user][i] == tokenId) {
                s_userStakes[user][i] = s_userStakes[user][length - 1];
                s_userStakes[user].pop();
                break;
            }
        }
    }

    function _transferRewards(address user, uint256[] calldata tokenIds)
        internal
    {
        uint256 length = tokenIds.length;
        uint256 totalReward = 0;
        for (uint256 i = 0; i < length; ++i) {
            uint256 tokenId = tokenIds[i];

            StakeInfo storage stakeInfo = s_stakes[user][tokenId];
            if (stakeInfo.stakedSince <= 0) revert DZapStaking__NftNotStaked();
        }
        if (totalReward != 0) {
            (bool checkMint, ) = s_rewardTokenContractAddress.call(
                abi.encodeWithSignature(
                    "mint(address,uint256)",
                    user,
                    totalReward
                )
            );
            if (!checkMint)
                revert DZapStaking__UnableToCallRewardTokenContract();

            emit RewardClaimed(user, totalReward);
        }
    }

    /*****************************
            VIEW FUNCTIONS
    ******************************/

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
        return (block.number - stakeInfo.stakedBlock) * s_rewardRatePerBlock;
    }

    /// @notice Returns the address of the ERC721 token contract used for staking
    /// @return The address of the ERC721 token contract
    function getStakingTokenContract() public view returns (IERC721) {
        return s_stakingTokenContract;
    }

    /// @notice Returns the address of the ERC20 token contract used for rewards
    /// @return The address of the ERC20 token contract
    function getRewardTokenContractAddress() public view returns (address) {
        return s_rewardTokenContractAddress;
    }

    /// @notice Returns the reward rate in ERC20 tokens per block
    /// @return The reward rate in ERC20 tokens per block
    function getRewardRatePerBlock() public view returns (uint256) {
        return s_rewardRatePerBlock;
    }

    /// @notice Returns the unbonding period in blocks before an unstaked NFT can be withdrawn
    /// @return The unbonding period in blocks
    function getUnbondingPeriod() public view returns (uint256) {
        return s_unbondingPeriod;
    }

    /// @notice Returns the delay period in blocks before rewards can be claimed again
    /// @return The reward claim delay period in blocks
    function getRewardClaimDelay() public view returns (uint256) {
        return s_rewardClaimDelay;
    }

    /// @notice Returns staking information for a specific user and NFT
    /// @param user The address of the user
    /// @param tokenId The ID of the staked NFT
    /// @return StakeInfo struct containing staking details
    function getStakeInfo(address user, uint256 tokenId)
        external
        view
        returns (StakeInfo memory)
    {
        return s_stakes[user][tokenId];
    }

    /// @notice Returns a list of staked NFTs for a specific user
    /// @param user The address of the user
    /// @return An array of token IDs representing the user's staked NFTs
    function getUserStakes(address user)
        external
        view
        returns (uint256[] memory)
    {
        return s_userStakes[user];
    }
}
