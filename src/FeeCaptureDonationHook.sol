// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BaseTestHooks} from "v4-core/test/BaseTestHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FeeCaptureDonationHook
/// @notice Uniswap V4 hook that captures swap fees and accepts direct donations for disaster relief
/// @dev Hybrid implementation: afterSwap (captures 20% of swap fees) + afterDonate (accepts 100% of donations)
contract FeeCaptureDonationHook is BaseTestHooks {
    using Hooks for IHooks;
    using SafeCast for uint256;
    using SafeCast for int128;
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The Uniswap V4 PoolManager contract
    IPoolManager public immutable poolManager;

    /// @notice The Octant ERC-4626 vault to receive fee donations
    IERC4626 public immutable donationVault;

    /// @notice Percentage of fees to donate (in basis points, e.g., 2000 = 20%)
    uint128 public constant DONATION_FEE_BIPS = 2000; // 20%

    /// @notice Total basis points for percentage calculations
    uint128 public constant TOTAL_BIPS = 10000;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when fees are captured from a swap
    /// @param currency The currency (token) from which fees were captured
    /// @param amount The amount of fees captured
    event FeesCaptured(Currency indexed currency, uint256 amount);

    /// @notice Emitted when captured fees are transferred to the vault
    /// @param currency The currency (token) that was deposited
    /// @param amount The amount deposited to the vault
    /// @param shares The amount of vault shares received
    event FeesTransferred(Currency indexed currency, uint256 amount, uint256 shares);

    /// @notice Emitted when a direct donation is received
    /// @param donor The address that made the donation
    /// @param amount0 The amount of token0 donated
    /// @param amount1 The amount of token1 donated
    event DonationReceived(address indexed donor, uint256 amount0, uint256 amount1);

    /// @notice Emitted when donated funds are deposited to the vault
    /// @param currency The currency (token) that was deposited
    /// @param amount The amount deposited to the vault
    /// @param shares The amount of vault shares received
    event DonationDeposited(Currency indexed currency, uint256 amount, uint256 shares);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyPoolManager();
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the FeeCaptureDonationHook
    /// @param _poolManager Address of the Uniswap V4 PoolManager
    /// @param _donationVault Address of the Octant ERC-4626 vault
    constructor(IPoolManager _poolManager, address _donationVault) {
        if (address(_poolManager) == address(0) || _donationVault == address(0)) {
            revert InvalidAddress();
        }
        poolManager = _poolManager;
        donationVault = IERC4626(_donationVault);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function access to only the PoolManager
    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) {
            revert OnlyPoolManager();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Specifies which hooks this contract implements and their permissions
    /// @dev Hybrid approach: afterSwap for fee capture + afterDonate for direct donations
    /// @return Hooks.Permissions A struct indicating which hooks are implemented
    function getHookPermissions()
        public
        pure
        virtual
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,           // Capture 20% of swap fees
                beforeDonate: false,
                afterDonate: true,         // Accept 100% of direct donations
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Hook called after a swap is executed
    /// @dev Captures a percentage of the swap output as fees and deposits to vault
    /// @param key The pool key for the swap
    /// @param params The swap parameters
    /// @param delta The balance changes from the swap
    /// @return selector The function selector to verify correct execution
    /// @return hookDelta The additional fees taken by the hook
    function afterSwap(
        address, /* sender **/
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, int128) {
        // Determine which token the fee should be taken from
        // Fee is taken from the unspecified (output) token of the swap
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            specifiedTokenIs0 ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        // If fee is on output, get the absolute output amount
        if (swapAmount < 0) swapAmount = -swapAmount;

        // Calculate donation amount (20% of swap output)
        uint256 feeAmount = uint128(swapAmount) * DONATION_FEE_BIPS / TOTAL_BIPS;

        if (feeAmount > 0) {
            // Take the fee from the pool
            poolManager.take(feeCurrency, address(this), feeAmount);

            emit FeesCaptured(feeCurrency, feeAmount);

            // Deposit fees to the Octant vault
            // Note: This assumes the feeCurrency matches the vault's asset
            // In production, you might want to add validation or token swapping
            _depositToVault(feeCurrency, feeAmount);
        }

        return (IHooks.afterSwap.selector, feeAmount.toInt128());
    }

    /// @notice Hook called after a donation is made to the pool
    /// @dev Accepts 100% of donations and routes them to the disaster relief vault
    /// @param sender The address that made the donation
    /// @param key The pool key
    /// @param amount0 The amount of token0 donated
    /// @param amount1 The amount of token1 donated
    /// @return selector The function selector to verify correct execution
    function afterDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4) {
        emit DonationReceived(sender, amount0, amount1);

        // Process token0 donation if any
        if (amount0 > 0) {
            // Take the donated token0 from the pool
            poolManager.take(key.currency0, address(this), amount0);

            // Deposit to vault if it matches the vault asset
            if (Currency.unwrap(key.currency0) == donationVault.asset()) {
                _depositDonationToVault(key.currency0, amount0);
            }
            // Note: If token doesn't match vault asset, it stays in the hook
            // In production, you might want to swap it or handle differently
        }

        // Process token1 donation if any
        if (amount1 > 0) {
            // Take the donated token1 from the pool
            poolManager.take(key.currency1, address(this), amount1);

            // Deposit to vault if it matches the vault asset
            if (Currency.unwrap(key.currency1) == donationVault.asset()) {
                _depositDonationToVault(key.currency1, amount1);
            }
            // Note: If token doesn't match vault asset, it stays in the hook
            // In production, you might want to swap it or handle differently
        }

        return IHooks.afterDonate.selector;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits captured fees to the Octant ERC-4626 vault
    /// @param currency The currency to deposit
    /// @param amount The amount to deposit
    function _depositToVault(Currency currency, uint256 amount) internal {
        address asset = Currency.unwrap(currency);

        // Ensure the asset matches the vault's expected asset
        require(asset == donationVault.asset(), "Asset mismatch");

        // Approve vault to spend the tokens
        IERC20(asset).forceApprove(address(donationVault), amount);

        // Deposit to vault and receive shares
        uint256 shares = donationVault.deposit(amount, address(this));

        emit FeesTransferred(currency, amount, shares);
    }

    /// @notice Deposits donated funds to the Octant ERC-4626 vault
    /// @param currency The currency to deposit
    /// @param amount The amount to deposit
    function _depositDonationToVault(Currency currency, uint256 amount) internal {
        address asset = Currency.unwrap(currency);

        // Approve vault to spend the tokens
        IERC20(asset).forceApprove(address(donationVault), amount);

        // Deposit to vault and receive shares
        uint256 shares = donationVault.deposit(amount, address(this));

        emit DonationDeposited(currency, amount, shares);
    }
}
