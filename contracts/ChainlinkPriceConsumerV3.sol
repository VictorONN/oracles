pragma solidity ^0.6.7;

import 

contract ChainlinkPriceConsumerV3 {

    AggregatorV3Interface internal priceFeed;

    /*
    Network: Kovan
    Aggregator: ETH:USD
    Address: 0x9326BFA02ADD2366b30bacB125260Af641031331
     */

     constructor() public {
         priceFeed = AggregatorV3Inteface(0x9326BFA02ADD2366b30bacB125260Af641031331);
     }

     /*
     returns the latest price */

     function getLatestPrice() public view returns (int) {
         (
             uint80 roundID, 
             int price, 
             uint startedAt,
             uint timestamp,
             uint80 answeredInRound, 
          ) = priceFeed.latestRoundData();
          return price;
     }
}