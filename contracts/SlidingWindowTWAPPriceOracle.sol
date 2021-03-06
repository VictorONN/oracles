pragma solidity =0.6.6;

import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./libraries/FixedPoint.sol";

import "./libraries/SafeMath.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/UniswapV2OracleLibrary.sol";

contract SlidingWindowTWAPPriceOracle.sol{
   using FixedPoint for *;
   using SafeMath for uint;

   struct Observation {
                 uint timestamp;
                 uint price0Cumulative;
                 uint price1Cumulative;                 
   }

   address public immutable factory;
   //desired amount of time over which the MA shd be computed e.g. 24 hrs
   uint public immutable windowSize;
   /* the number of observations stored for each pair, i.e. how many price observations are 
   stored for the window. As granularity increases from 1, more frequent updates are needed, but MA 
   become more precise. Averages are computed over intervals with sizes in the range:
   [windowSize - (windowSize/granularity) * 2, windowSize]
   e.g. if the windowSize is 24 hrs, and the granularity is 24, the oracle will return the average price
   for the period: [now - [22 hours, 24 hours], now]
   */
   uint8 public immutable granularity;
   //this is redundant with granularity and windowSize but stored for gas savings and informational purposes
   uint public immutable periodSize;

   //mapping from pair address to a list of price observations of that pair
   mapping(address => Observation[])public pairObservations;

   constructor(address factory_, uint windowSize_, uint8 granularity_)public{
                 require(granularity_ > 1, 'SlidingWindowOracle: GRANULARITY');
                 require((periodSize = windowSize_ / granularity_) * granularity_ == windowSize_,
                 'SlidingWindowOracle: WINDOW_NOT_EVENLY_DIVISIBLE');
                 factory = factory_;
                 windowSize = windowSize_;
                 granularity = granularity_;
   }

   //returns the index of the observation corresponding to the given timestamp
   function observationIndexOf(uint timestamp) public view returns (uint8 index){
                 uint epochPeriod = timestamp/periodSize;
                 return uint8(epochPeriod % granularity);
   }

   //returns the observation from the oldest epoch(beginning of the window) relative to the current time
   function getFirstObservationInWindow(address pair) private view returns(Observation storage firstObservation){
                 uint8 observationIndex = observationIndexOf(block.timestamp);
                 //no overflow issue. if observationIndex + 1 overflows, result is still zero
                 uint8 firstObservationIndex = (observationIndex + 1) % granularity;
                 firstObservation = pairObservations[pair][firstObservationIndex];
   } 

   //update the cumulative price for the observation at the current timestamp, each observation is updated at
   //once per period
   function update(address tokenA, address tokenB) external {
                 address pair = UniswapV2Library,pairFor(factory, tokenA, tokenB);

                 //populate the array with empty observations (first call only)
                 for (uint i = pairObservations[pair].length; i < granularity; i++){
                               pairObservations[pair].push();
                 }

                 //get the observation for the current period
                 uint8 observationIndex = observationIndexOf(block.timestamp);
                 Observation storage observation = pairObservations[pair][observationIndex];

                 //we only want to commit updates once per period(i.e. windowSize/granularity)
                 uint timeElapsed = block.timestamp - observation.timestamp;
                 if(timeElapsed > periodSize){
                               (uint price0Cumulative, uint price1Cumulative,) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
                               observation.timestamp = block.timestamp;
                               observation.price0Cumulative = price0Cumulative;
                               observation.price1Cumulative = price1Cumulative;               
                                 }
   } 

   //given the cumulative prices at the start and end of a period, and the length of the period, compute the average 
   //price in terms of how much amount out is received for the amount in
   function computeAmountOut(uint priceCumulativeLast, uint priceCumulativeEnd, uint timeElapsedm uint amountIn)
   private pure returns (uint amountOut){
                 //overflow is desired
                 FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
                               uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
                 );
                 amountOut = priceAverage.mul(amountIn).decode144();
   }

   //returns the amount out corresponding to the amount in for a given token using the moving average over the
   //    time range [now - [windowSize, windowSize - periodSize * 2], now]
   //update must have been called for the bucket corresponding to timestamp `now - windowSize`
   function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut) {
                 address pair = UniswapV2Library.pairFor(factory, tokenIn, tokenOut);
                 Observation storage firstObservation = getFirstObservationInWindow(pair);

                 uint timeElapsed = block.timestamp - firstObservation.timestamp;
                 require(timeElapsed <= windowSize, 'SlidingWindowOracle: MISSING_HISTORICAL_OBSERVATIONS');   
                 //should never happen
                 require(timeElapsed >= windowSize - periodSize * 2, 'SlidingWindowOracle: UNEXPECTED_TIME_ELAPSED ');

                 (uint price0Cumulative, uint price1Cumulative) = UniswapV2OracleLibrary.currentCumulativePrices(pair);
                 (address token0,) = UniswapV2Library.sortTokens(tokenIn, tokenOut);

                 if(token0 == tokenIn) {
                               return computeAmountOut(firstObservation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);          
                 }
                 else {
                           return computeAmountOut(firstObservation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
                 }
                 
   }

   

}