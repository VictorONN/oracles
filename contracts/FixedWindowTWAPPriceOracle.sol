pragma solidity 0.6.6;

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./libraries/FixedPoint.sol";
import "./libraries/UniswapV2OracleLibrary.sol";
import "./libraries/UniswapV2Library.sol";

//fixed window oracle that recomputes average price for the entire period once every 30 minutes
//price average is only guaranteed to be over at least 1 period, but may be over a longer period

contract FixedWindowTWAPPriceOracle {
    using FixedPoint for *;

    uint256 public constant PERIOD = 30 minutes;

    IUniswapV2Pair immutable pair;
    address public immutable token0;
    address public immutable token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    constructor(
        address factory,
        address tokenA,
        address tokenB
    ) public {
        IUniswapV2Pair _pair = IUniswapV2Pair(
            UniswapV2Library.pairFor(factory, tokenA, tokenB)
        );
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); //fetch current accumulated price value (1/0)
        price1CumulativeLast = _pair.price1CumulativeLast(); //fetch current accumulated price value (0/1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "TWAPPriceOracle: NO_RESERVES");
    }

    function update() external {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        //ensure at least one full period has passed since last update
        require(timeElapsed >= PERIOD, "TWAPPriceOracle: PERIOD_NOT_ELAPSED");

        //overflow is desired
        //cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0average = FixedPoint.uq112x112(
            uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
        );
        price1average = FixedPoint.uq112x112(
            uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
        );

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimetamp;
    }

    // note this will always return 0 before update has been called successfully for the first time
    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, "TWAPPriceOracle: INVALID_TOKEN");
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}
