//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Update the import path to the correct location of BaseHook.sol
import {BaseHook} from "lib/v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

contract PointsHook is BaseHook, ERC1155 {
    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function getHookPermissions()
        public
        pure
        override
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
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        //if this is not an ETH-TOKEN pool with this hook attached ignnooe
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);

        //we only mint points f th usr is buying token with eth
        if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);

        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 points = ethSpendAmount / 5;

        //Mint the points

        _assignPoints(key.toId(), hookData, points);

        return (this.afterSwap.selector, 0);
    }

    function _assignPoints(
        PoolId poolId,
        bytes calldata hookData,
        uint256 points
    ) internal {
        //if no hookdata is provided no points is assigned to anyone

        if (hookData.length == 0) return;

        //Extract the user address from hookdata

        address user = abi.decode(hookData, (address));

        //there is hookdata but not in our expected format and user adress is zero
        //nobody gets any points

        if (user == address(0)) return;

        //mint points to user

        uint256 poolIdUint = uint256(PoolId.unwrap(poolId));
        _mint(user, poolIdUint, points, "");
    }
}
