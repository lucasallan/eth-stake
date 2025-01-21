# ETH Staking Contract

A secure and upgradeable smart contract for staking ETH and receiving stETH tokens in return.

## Features

- **ETH Staking**: Users can stake their ETH and receive stETH tokens in return
- **Flexible Withdrawals**: Withdraw staked ETH after the minimum stake period
- **Reward System**: Earn rewards based on stake amount and time elapsed
- **Emergency Functions**: Emergency withdrawal available when contract is paused
- **Security Features**:
  - Reentrancy protection
  - Pausable functionality
  - Upgradeable contract architecture (UUPS pattern)
  - Owner-controlled admin functions
  - Minimum stake period
  - Maximum reward rate cap

## Contract Details

- **License**: MIT
- **Solidity Version**: ^0.8.0
- **Dependencies**: 
  - OpenZeppelin Contracts Upgradeable
    - ReentrancyGuardUpgradeable
    - OwnableUpgradeable
    - UUPSUpgradeable
    - PausableUpgradeable

## Main Functions

### User Functions

- `stake()`: Stake ETH and receive stETH tokens (payable function)
- `withdraw(uint256 _amount)`: Withdraw specified amount of staked ETH (burns stETH)
- `claimRewards()`: Claim accumulated staking rewards
- `emergencyWithdraw()`: Withdraw stake during paused state
- `getRewards(address _user)`: View current rewards for a user
- `getTotalStaked()`: View total ETH staked in contract
- `isActiveStaker(address _user)`: Check if address has active stake
- `getTimeUntilWithdraw(address _user)`: Check remaining time until withdrawal possible
- `getStake(address account)`: View complete stake information

### Admin Functions

- `setRewardRate(uint256 _newRate)`: Update the reward rate (owner only)
- `setMinStakePeriod(uint256 _period)`: Set minimum staking period (owner only)
- `pause()`: Pause contract functionality (owner only)
- `unpause()`: Resume contract functionality (owner only)
- `upgradeTo(address)`: Upgrade the contract implementation (owner only)

## Constants

- `MAX_REWARD_RATE`: 1% per second (1e16)
- Default minimum stake period: 60 seconds (configurable)

## Events

- `Staked(address indexed user, uint256 indexed amount, uint256 shares)`
- `Withdrawn(address indexed user, uint256 indexed amount, uint256 shares)`
- `RewardsClaimed(address indexed user, uint256 indexed amount)`
- `RewardRateUpdated(uint256 indexed newRate)`
- `EmergencyWithdrawn(address indexed user, uint256 indexed amount)`
- `MinStakePeriodUpdated(uint256 indexed newPeriod)`

## Security

For security concerns or bug reports, please contact: security@example.com

## Development

This project uses Hardhat as the development environment. To get started:

1. Install dependencies:
```bash
npm install
```

2. Run tests:
```bash
npx hardhat test
```

3. Deploy:
```bash
npx hardhat run scripts/deploy.js --network <network-name>
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
