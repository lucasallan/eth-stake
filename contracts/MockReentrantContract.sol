// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStaking.sol";
import "./StakedToken.sol";

contract MockReentrantContract {
    EthStaking public ethStaking;
    StakedToken public stakedToken;
    bool public isAttacking;

    constructor(address payable _ethStaking, address _stakedToken) {
        ethStaking = EthStaking(_ethStaking);
        stakedToken = StakedToken(_stakedToken);
    }

    // Function to stake ETH
    function stake() external payable {
        ethStaking.stake{value: msg.value}();
        stakedToken.approve(address(ethStaking), type(uint256).max);
    }

    // Function to attempt reentrancy on withdrawal
    function attackWithdraw(uint256 amount) external {
        isAttacking = true;
        ethStaking.withdraw(amount);
    }

    // Function to attempt reentrancy on reward claiming
    function attackRewardClaim() external {
        isAttacking = true;
        ethStaking.claimRewards();
    }

    // Fallback function that attempts to reenter when receiving ETH
    receive() external payable {
        if (isAttacking) {
            isAttacking = false; // Prevent infinite loop
            ethStaking.withdraw(1 ether);
        }
    }
}
