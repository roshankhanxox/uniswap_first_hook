// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";

import "forge-std/console.sol";
import {PointsHook} from "../src/PointsHook.sol";

contract TestPointsHook is Test, Deployers, ERC1155TokenReceiver {
    MockERC20 token;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    PointsHook hook;

    function setUp() public {
        // Deploy an instance of the PoolManager
        // Deploy periphery router contracts for swapping, modifying liquidity, etc
        // Deploy the TOKEN ERC-20 contract (we'll use MockERC20 here)
        // Mint a bunch of TOKEN supply to ourselves, so we can use it for adding liquidity
        // Mine a contract address for our hook using HookMiner
        // Deploy our hook contract
        // Approve our TOKEN for spending on the periphery router contracts
        // Create a new pool for ETH and TOKEN with our hook attached
        // Add some liquidity to this pool

        //dpeloys pool manager and periphery routers
        deployFreshManagerAndRouters();

        // Deploy the MockERC20 token
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));

        // Mint some tokens to the contract and an address
        token.mint(address(this), 1000 ether);
        token.mint(address(1), 1000 ether);

        //dloy hook to an address that has proper flags set
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("PointsHook.sol", abi.encode(manager), address(flags));

        //casting the already deployed hooks address to a points contract so that we can interact with it
        hook = PointsHook(address(flags));

        //provide approval to the swaprouter and the modify liquidity router
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        //initialsng a pool

        (key, ) = initPool(
            ethCurrency,
            tokenCurrency,
            hook,
            3000,
            SQRT_PRICE_1_1
        );

        //adding liquidity to the pool
        uint160 sqrtPriceAtLowerTick = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtUpperTick = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 0.003 ether;

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            SQRT_PRICE_1_1,
            sqrtPriceAtUpperTick,
            ethToAdd
        );

        uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtPriceAtLowerTick,
            SQRT_PRICE_1_1,
            liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_swap() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(key.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(
            address(this),
            poolIdUint
        );

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 20% of 0.001 * 10**18 points
        // = 2 * 10**14
        swapRouter.swap{value: 0.001 ether}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            hookData
        );
        uint256 pointsBalanceAfterSwap = hook.balanceOf(
            address(this),
            poolIdUint
        );
        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2 * 10 ** 14);
    }
}
