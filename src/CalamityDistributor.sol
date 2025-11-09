// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CalamityDistributor
/// @notice Receives ERC-4626 vault shares from Octant vault and distributes them to farmers during calamities
/// @dev This contract acts as the allocation address for the Octant MultistrategyVault
contract CalamityDistributor is Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The Octant ERC-4626 vault this distributor receives shares from
    IERC4626 public immutable vault;

    /// @notice First farmer address to receive distributions
    address public farmer1;

    /// @notice Second farmer address to receive distributions
    address public farmer2;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when vault shares are received
    /// @param shareAmount Amount of shares received
    event SharesReceived(uint256 shareAmount);

    /// @notice Emitted when yield is distributed to farmers
    /// @param totalAmount Total amount distributed in underlying assets
    /// @param farmer1Amount Amount sent to farmer1
    /// @param farmer2Amount Amount sent to farmer2
    event YieldDistributed(uint256 totalAmount, uint256 farmer1Amount, uint256 farmer2Amount);

    /// @notice Emitted when a calamity distribution is triggered
    /// @param reason Description of the calamity
    event CalamityTriggered(string reason);

    /// @notice Emitted when farmer addresses are updated
    /// @param newFarmer1 New address for farmer1
    /// @param newFarmer2 New address for farmer2
    event FarmerAddressesUpdated(address indexed newFarmer1, address indexed newFarmer2);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAddress();
    error NoSharesToDistribute();
    error DistributionFailed();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the CalamityDistributor contract
    /// @param _vault Address of the Octant ERC-4626 vault
    /// @param _farmer1 Address of the first farmer
    /// @param _farmer2 Address of the second farmer
    /// @param _admin Address that will own this contract
    constructor(address _vault, address _farmer1, address _farmer2, address _admin) Ownable(_admin) {
        if (_vault == address(0) || _farmer1 == address(0) || _farmer2 == address(0)) {
            revert InvalidAddress();
        }

        vault = IERC4626(_vault);
        farmer1 = _farmer1;
        farmer2 = _farmer2;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Distributes accumulated yield shares to farmers in a 50/50 split
    /// @param reason Description of the calamity triggering this distribution
    /// @dev Redeems all vault shares held by this contract and splits equally
    function distributeYield(string calldata reason) external onlyOwner {
        emit CalamityTriggered(reason);

        uint256 shareBalance = vault.balanceOf(address(this));
        if (shareBalance == 0) {
            revert NoSharesToDistribute();
        }

        // Redeem all shares for underlying assets
        // The vault will transfer underlying assets to this contract
        uint256 totalAssets = vault.redeem(shareBalance, address(this), address(this));

        // Calculate 50/50 split
        uint256 half = totalAssets / 2;
        uint256 farmer1Amount = half;
        uint256 farmer2Amount = totalAssets - half; // Handle odd amounts

        // Get the underlying asset token
        IERC20 asset = IERC20(vault.asset());

        // Transfer to farmers
        asset.safeTransfer(farmer1, farmer1Amount);
        asset.safeTransfer(farmer2, farmer2Amount);

        emit YieldDistributed(totalAssets, farmer1Amount, farmer2Amount);
    }

    /// @notice Updates the farmer addresses
    /// @param _farmer1 New address for farmer1
    /// @param _farmer2 New address for farmer2
    function setFarmerAddresses(address _farmer1, address _farmer2) external onlyOwner {
        if (_farmer1 == address(0) || _farmer2 == address(0)) {
            revert InvalidAddress();
        }

        farmer1 = _farmer1;
        farmer2 = _farmer2;

        emit FarmerAddressesUpdated(_farmer1, _farmer2);
    }

    /// @notice Emergency withdrawal function for owner
    /// @dev Allows owner to withdraw any tokens in case of emergency
    /// @param token Address of the token to withdraw (use vault.asset() for underlying, address(vault) for shares)
    function emergencyWithdraw(address token) external onlyOwner {
        if (token == address(0)) {
            revert InvalidAddress();
        }

        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        if (balance > 0) {
            tokenContract.safeTransfer(owner(), balance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current share balance of this contract in the vault
    /// @return The amount of vault shares held
    function getShareBalance() external view returns (uint256) {
        return vault.balanceOf(address(this));
    }

    /// @notice Returns the current value of shares in underlying assets
    /// @return The amount of underlying assets the shares can be redeemed for
    function getShareValue() external view returns (uint256) {
        uint256 shares = vault.balanceOf(address(this));
        if (shares == 0) return 0;
        return vault.convertToAssets(shares);
    }
}
