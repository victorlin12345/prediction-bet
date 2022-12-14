// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// StartTime -> LockTime -> EndTime
contract BetGame is Ownable, Pausable, ReentrancyGuard {

    modifier notContract() {
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }
    
    struct RoundInfo {
        uint256 RoundID;
        uint256 StartTime;
        uint256 LockTime;
        uint256 EndTime;
        uint256 PredictBullAmount; // bet higher than LockPrice
        uint256 PredictBearAmount; // bet lower than LockPrice
        uint256 TotalAmount;
        int256 StartPrice;
        int256 LockPrice;
        int256 EndPrice;
    }
    
    uint256 currentRoundID = 1;
    uint256 interval = 60 * 60 * 3; // 3 hours
    uint256 tolerance = 30;
    uint256 minBetAmount = 0.001 ether;

    mapping(uint256 => RoundInfo) public Games;
    mapping(uint256 => mapping(address => uint256)) public Bets;

    AggregatorV3Interface internal priceFeed;

    constructor(address _priceFeed) {
         priceFeed = AggregatorV3Interface(_priceFeed);
    }
    
    function _setRoundBegin(uint256 _round, int256 _startPrice) private {
        require(_round > 0, "_round should greater than 0");
        require(_startPrice > 0, "_startPrice should greater than 0");
        
        RoundInfo storage game = Games[_round];
        game.RoundID = _round;
        game.StartPrice = _startPrice;
        game.StartTime = uint32(block.timestamp);
        game.LockTime = uint32(block.timestamp + interval);
        game.EndTime = uint32(block.timestamp + interval * 2);
    }

    function _setRoundLock(uint256 _round, int256 _lockPrice) private {
        require(_round > 0, "_round should greater than 0");
        require(_lockPrice > 0, "_lockPrice should greater than 0");

        RoundInfo storage game = Games[_round];
        require(block.timestamp >= game.LockTime, "should set greater than LockTime");
        require(block.timestamp <= game.LockTime + tolerance, "should set less than LockTime with tolerance");
        require(block.timestamp <= game.EndTime, "should set less than EndTime");
        game.LockPrice =  _lockPrice;
    }

    function _setRoundEnd(uint256 _round, int256 _endPrice) private {
        require(_round > 0, "_round should greater than 0");
        require(_endPrice > 0, "_endPrice should greater than 0");

        RoundInfo storage game = Games[_round];
        require(block.timestamp >= game.EndTime, "should set greater than EndTime");
        require(block.timestamp <= game.EndTime + tolerance, "should set less than EndTime with tolerance");
        game.EndPrice =  _endPrice;
    }

    function ExecuteRoundBegin() external onlyOwner whenNotPaused {
        int256 price = GetLatestPrice();
        require(price >= 0, "price should greater than 0");
        require(currentRoundID >= 1, "should greater than 1");
        _setRoundBegin(currentRoundID, price);
    }

    function ExecuteRoundLock() public whenNotPaused {
        require(block.timestamp <= (Games[currentRoundID].LockTime + tolerance), "should execute before lock time with tolerance");
        require(block.timestamp >= Games[currentRoundID].LockTime, "should execute after lock time");

        int256 price = GetLatestPrice();
        require(price >= 0, "price should greater than 0");
        _setRoundLock(currentRoundID, price);
    }

    function ExecuteRoundEnd() public whenNotPaused {
        require(block.timestamp <= (Games[currentRoundID].EndTime + tolerance), "should execute after end time in tolerance interval");
        require(block.timestamp >= Games[currentRoundID].EndTime, "should execute after end time");

        int256 price = GetLatestPrice();
        require(price >= 0, "price should greater than 0");
        _setRoundEnd(currentRoundID, price);
        currentRoundID = currentRoundID + 1;
    }

    function GetLatestPrice() public view returns (int256) {
        (,int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }

    function BetBull() external payable whenNotPaused nonReentrant notContract {
        require(msg.value >= minBetAmount, "Bet amount must be greater than minBetAmount");
        require(Bets[currentRoundID][msg.sender] == 0, "Can only bet once per round");

        uint256 amount = msg.value;
        RoundInfo storage game = Games[currentRoundID];
        game.PredictBullAmount = game.PredictBullAmount + amount;
        Bets[currentRoundID][msg.sender] = amount;
    } 

    function BetBear() external payable whenNotPaused nonReentrant notContract {
        require(msg.value >= minBetAmount, "Bet amount must be greater than minBetAmount");
        require(Bets[currentRoundID][msg.sender] == 0, "Can only bet once per round");

        uint256 amount = msg.value;
        RoundInfo storage game = Games[currentRoundID];
        game.PredictBearAmount = game.PredictBearAmount + amount;
        Bets[currentRoundID][msg.sender] = amount;
    } 

    function ClaimRewards(uint256 _round) internal {

    }

    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }


}