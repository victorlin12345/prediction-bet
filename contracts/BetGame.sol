// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";



contract BetGame is Ownable, Pausable {
    
    struct GameInfo {
        uint256 Round;
        uint256 StartTime;
        uint256 LockTime;
        uint256 EndTime;
        uint256 PredictBullAmount; // bet higher than LockPrice
        uint256 PredictBearAmount; // bet lower than LockPrice
        uint256 TotalAmount;
        uint256 LockPrice;
        uint256 EndPrice;
    }
    
    uint256 currentRound;

    mapping(uint256 => GameInfo) public Games;

    AggregatorV3Interface internal priceFeed;

    constructor(address _priceFeed) {
         priceFeed = AggregatorV3Interface(_priceFeed);
    }
    
    function BeginGame(uint256 _round, uint256 entryInterval, uint256 revealInterval) public onlyOwner {
        GameInfo storage game = Games[_round];
        game.Round = _round;
        game.StartTime = uint32(block.timestamp);
        game.LockTime = uint32(block.timestamp);
    }

    function GetLatestPrice() public view returns (int256) {
        (,int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }

}