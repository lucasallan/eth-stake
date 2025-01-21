// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./StakedToken.sol";

/**
 * @title EthStaking
 * @dev A contract for staking ETH and receiving stETH tokens
 */
contract EthStaking is ReentrancyGuardUpgradeable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    struct Stake {
        uint256 amount;
        uint128 rewards;
        uint128 timestamp;
    }
    
    StakedToken public stakedToken;
    
    uint256 public minStakePeriod;
    uint256 public constant MAX_REWARD_RATE = 1e16; // 1% per second
    
    // Storage slots
    bytes32 private constant STAKES_POSITION = keccak256("stEth.stake.stakes.position");
    bytes32 private constant REWARD_RATE_POSITION = keccak256("stEth.stake.rewardrate.position");

    uint256[50] private __gap;

    event Staked(address indexed user, uint256 indexed amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 indexed amount, uint256 shares);
    event RewardsClaimed(address indexed user, uint256 indexed amount);
    event RewardRateUpdated(uint256 indexed newRate);
    event EmergencyWithdrawn(address indexed user, uint256 indexed amount);
    event MinStakePeriodUpdated(uint256 indexed newPeriod);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initializes the contract setting the deployer as the initial owner
     * and sets the initial reward rate
     * @param _stakedToken Address of the StakedToken contract
     */
    function initialize(address _stakedToken) external initializer {
        require(_stakedToken != address(0), "Invalid staked token address");
        
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __Pausable_init();
        
        stakedToken = StakedToken(_stakedToken);
        _setRewardRate(1e14);
        minStakePeriod = 60;
    }

    // External functions
    /**
     * @dev Allows users to stake ETH and receive stETH tokens
     * @notice Stakes the sent ETH amount and mints equivalent stETH tokens
     */
    function stake() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Cannot stake 0 ETH");
        
        Stake storage userStake = _getStakesMapping()[msg.sender];
        
        _updateRewardsForUser(userStake);
        
        userStake.amount += msg.value;
        userStake.timestamp = uint128(block.timestamp);
        
        stakedToken.mint(msg.sender, msg.value);
        
        emit Staked(msg.sender, msg.value, msg.value);
    }
    
    /**
     * @dev Allows users to withdraw their staked ETH by burning stETH tokens
     * @param _amount Amount of ETH/stETH to withdraw
     * @notice Burns the specified amount of stETH tokens and returns ETH
     */
    function withdraw(uint256 _amount) external nonReentrant whenNotPaused {
        Stake storage userStake = _getStakesMapping()[msg.sender];
        
        require(_amount > 0, "Cannot withdraw 0 ETH");
        require(_amount <= userStake.amount, "Insufficient staked amount");
        require(block.timestamp >= uint256(userStake.timestamp) + minStakePeriod, "Minimum stake period not met");
        
        _updateRewardsForUser(userStake);
        userStake.amount -= _amount;
        userStake.timestamp = uint128(block.timestamp);
        
        stakedToken.burn(msg.sender, _amount);
        
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "ETH transfer failed");
        
        emit Withdrawn(msg.sender, _amount, _amount);
    }
    
    /**
     * @dev Allows users to claim their accumulated rewards
     * @notice Claims all accumulated rewards and transfers them to the user
     */
    function claimRewards() external nonReentrant whenNotPaused {
        Stake storage userStake = _getStakesMapping()[msg.sender];
        
        _updateRewardsForUser(userStake);
        uint256 rewards = userStake.rewards;
        
        require(rewards > 0, "No rewards to claim");
        
        userStake.rewards = 0;
        
        (bool success, ) = msg.sender.call{value: rewards}("");
        require(success, "ETH transfer failed");
        
        emit RewardsClaimed(msg.sender, rewards);
    }

    /**
     * @dev Updates the reward rate for the staking contract
     * @param _newRate New reward rate to be set
     * @notice Can only be called by the contract owner
     */
    function setRewardRate(uint256 _newRate) external onlyOwner {
        require(_newRate <= MAX_REWARD_RATE, "Rate too high");
        require(_newRate > 0, "Rate cannot be zero");
        _setRewardRate(_newRate);
        emit RewardRateUpdated(_newRate);
    }

    /**
     * @dev Sets the minimum stake period
     * @param _period New minimum stake period in seconds
     * @notice Can only be called by the contract owner
     */
    function setMinStakePeriod(uint256 _period) external onlyOwner {
        minStakePeriod = _period;
        emit MinStakePeriodUpdated(_period);
    }

    /**
     * @dev Emergency withdraw function that bypasses the minimum stake period
     * @notice Can only be used when contract is paused
     */
    function emergencyWithdraw() external nonReentrant whenPaused {
        Stake storage userStake = _getStakesMapping()[msg.sender];
        uint256 amount = userStake.amount;
        
        require(amount > 0, "No stake to withdraw");
        
        userStake.amount = 0;
        userStake.rewards = 0;
        userStake.timestamp = uint128(block.timestamp);
        stakedToken.burn(msg.sender, amount);
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");
        
        emit EmergencyWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Pauses all non-emergency functions
     * @notice Can only be called by the contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all functions
     * @notice Can only be called by the contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Gets the current rewards for a specific user
     * @param _user Address of the user to check
     * @return Total rewards (claimed + unclaimed)
     */
    function getRewards(address _user) external view returns (uint256) {
        Stake storage userStake = _getStakesMapping()[_user];
        
        uint256 currentRewards = userStake.rewards;
        
        if (userStake.amount > 0) {
            uint256 timeElapsed = block.timestamp - uint256(userStake.timestamp);
            currentRewards += (userStake.amount * timeElapsed * _getRewardRate()) / 1e18;
        }
        
        return currentRewards;
    }

    // View functions for transparency
    /**
     * @dev Gets the total amount of ETH staked in the contract
     * @return Total staked ETH amount
     */
    function getTotalStaked() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Gets the total number of unique stakers
     * @param _user Address of the user to check
     * @return Boolean indicating if the address has an active stake
     */
    function isActiveStaker(address _user) external view returns (bool) {
        return _getStakesMapping()[_user].amount > 0;
    }

    /**
     * @dev Gets the time remaining until a user can withdraw their stake
     * @param _user Address of the user to check
     * @return Time remaining in seconds, 0 if withdrawal is possible
     */
    function getTimeUntilWithdraw(address _user) external view returns (uint256) {
        Stake storage userStake = _getStakesMapping()[_user];
        if (userStake.amount == 0) return 0;
        
        uint256 stakeEndTime = uint256(userStake.timestamp) + minStakePeriod;
        if (block.timestamp >= stakeEndTime) return 0;
        return stakeEndTime - block.timestamp;
    }

    // Public functions
    /**
     * @dev Retrieves the stake information for a specific account
     * @param account Address of the account to query
     * @return Stake struct containing stake details
     */
    function getStake(address account) public view returns (Stake memory) {
        return _getStakesMapping()[account];
    }

    /**
     * @dev Gets the current reward rate
     * @return Current reward rate value
     */
    function getRewardRate() public view returns (uint256) {
        return _getRewardRate();
    }

    // Internal functions
    /**
     * @dev Internal function to authorize contract upgrades
     * @param newImplementation Address of the new implementation contract
     * @notice Can only be called by the contract owner
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Internal function to update rewards for a specific user
     * @param userStake Storage pointer to the user's stake
     */
    function _updateRewardsForUser(Stake storage userStake) internal {
        if (userStake.amount > 0) {
            uint256 timeElapsed = block.timestamp - uint256(userStake.timestamp);
            uint256 newRewards = (userStake.amount * timeElapsed * _getRewardRate()) / 1e18;
            userStake.rewards = uint128(uint256(userStake.rewards) + newRewards);
        }
        
        userStake.timestamp = uint128(block.timestamp);
    }

    // Private functions
    /**
     * @dev Private function to get the stakes mapping from storage
     * @return stakes Mapping of address to Stake struct
     */
    function _getStakesMapping() private pure returns (mapping(address => Stake) storage stakes) {
        bytes32 position = STAKES_POSITION;
        assembly {
            stakes.slot := position
        }
    }

    /**
     * @dev Private function to get the reward rate from storage
     * @return Current reward rate value
     */
    function _getRewardRate() private view returns (uint256) {
        bytes32 position = REWARD_RATE_POSITION;
        uint256 value;
        assembly {
            value := sload(position)
        }
        return value;
    }

    /**
     * @dev Private function to set the reward rate in storage
     * @param _value New reward rate value to store
     */
    function _setRewardRate(uint256 _value) private {
        bytes32 position = REWARD_RATE_POSITION;
        assembly {
            sstore(position, _value)
        }
    }

    // Fallback function
    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
}