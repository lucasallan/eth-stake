// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title ITokenReceiver Interface
/// @notice Interface for contracts that want to receive notifications when tokens are burned
interface ITokenReceiver {
    /// @notice Called when tokens are burned from a contract address
    /// @param from The address from which tokens are burned
    /// @param amount The amount of tokens being burned
    function onERC20Burning(address from, uint256 amount) external;
}

/// @title StakedToken Contract
/// @notice An upgradeable ERC20 token representing staked ETH
/// @dev Implements UUPS upgradeability pattern and includes burning notification for contracts
contract StakedToken is ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Contract constructor that disables initializers
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @dev Sets up the token with name and symbol, and initializes the owner and UUPS functionality
    function initialize() public initializer {
        __ERC20_init("Staked ETH", "stETH");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    /// @notice Mints new tokens
    /// @dev Only callable by the contract owner
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burns tokens from a specified address
    /// @dev Only callable by the contract owner. If the address is a contract,
    /// it attempts to notify it about the burning via the ITokenReceiver interface
    /// @param from The address to burn tokens from
    /// @param amount The amount of tokens to burn
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
        // Call onERC20Burning if the address is a contract
        if (from.code.length > 0) {
            try ITokenReceiver(from).onERC20Burning(from, amount) {} catch {}
        }
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev Required by the UUPSUpgradeable contract, only callable by the owner
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
