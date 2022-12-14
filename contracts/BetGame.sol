// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "hardhat/console.sol";

// StartTime -> LockTime -> EndTime
contract BetGame is Ownable, Pausable, ReentrancyGuard {

    event RoundBeginEvent(uint256 indexed roundID, RoundInfo roundInfo);
    event LockRoundEvent(uint256 indexed roundID, address sender, int256 price, uint32 timestamp);
    event EndRoundEvent(uint256 indexed roundID, address sender, int256 price, uint32 timestamp);
    event BetBearEvent(address indexed sender, uint256 indexed roundID, uint256 amount);
    event BetBullEvent(address indexed sender, uint256 indexed roundID, uint256 amount);
    event CalculateResultEvent(uint256 indexed roundID, address sender);
    event ClaimRewardEvent(uint256 indexed roundID, address indexed sender, uint256 amount);
    event SetIntervalEvent(uint256 interval, uint32 timestamp);
    event SetIntervalBufferEvent(uint256 buffer, uint32 timestamp);
    event SetMinBetAmountEvent(uint256 amount, uint32 timestamp);
    event PauseEvent(uint256 indexed roundID);
    event UnpausedEvent(uint256 indexed roundID);

    modifier notContract() {
        require(!_isContract(msg.sender), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    modifier bettable() {
        require(msg.value >= minBetAmount, "Bet amount must be greater than minBetAmount");
        require(Bets[currentRoundID][msg.sender].Amount == 0, "Can only bet once per round");
        require(block.timestamp > Games[currentRoundID].StartTime, "should bet after start time");
        require(block.timestamp < Games[currentRoundID].LockTime, "should bet before lock time");
        _;
    }
    
    struct RoundInfo {
        uint256 RoundID;
        uint256 StartTime;
        uint256 LockTime;
        uint256 EndTime;
        uint256 PredictBullAmount; // bet higher than LockPrice
        uint256 PredictBearAmount; // bet lower than LockPrice
        int256 StartPrice;
        int256 LockPrice;
        int256 EndPrice;
        uint256 PredictBullParticipants;
        uint256 PredictBearParticipants;
    }

    enum Prediction {
        Bull,
        Bear
    }

    enum Result {
        NoWinner,
        Bull,
        Bear
    }

    struct BetInfo {
        address Participant;
        uint256 RoundID;
        Prediction Predict;
        uint256 Amount;
    }

    struct ResultInfo {
        Result Answer;
        bool BeCalculated;
        uint256 Share;
    }
    
    uint256 currentRoundID = 1;
    uint256 interval = 60 * 60 * 3;       // default: 3 hour
    uint256 intervalBuffer = 30;          // default: 30 sec
    uint256 minBetAmount = 0.001 ether;   // default

    mapping(uint256 => RoundInfo) public Games;
    mapping(uint256 => mapping(address => BetInfo)) public Bets;
    mapping(uint256 => ResultInfo) public Results;

    AggregatorV3Interface internal priceFeed;

    constructor(address _priceFeed) {
         priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function GetRoundInfo(uint256 _round) public view returns (RoundInfo memory) {
        return Games[_round];
    }

    function GetBetInfo(uint256 _round, address _user)  public view returns (BetInfo memory) {
        return Bets[_round][_user];
    }

    function GetResultInfo(uint256 _round) public view returns (ResultInfo memory) {
        return Results[_round];
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
        require(block.timestamp <= game.LockTime + intervalBuffer, "should set less than LockTime with tolerance");
        require(block.timestamp <= game.EndTime, "should set less than EndTime");
        game.LockPrice =  _lockPrice;
    }

    function _setRoundEnd(uint256 _round, int256 _endPrice) private {
        require(_round > 0, "_round should greater than 0");
        require(_endPrice > 0, "_endPrice should greater than 0");

        RoundInfo storage game = Games[_round];
        require(block.timestamp >= game.EndTime, "should set greater than EndTime");
        require(block.timestamp <= game.EndTime + intervalBuffer, "should set less than EndTime with tolerance");
        game.EndPrice =  _endPrice;
    }

    function ExecuteRoundBegin() public onlyOwner whenNotPaused {
        int256 price = GetLatestPrice();
        require(price >= 0, "price should greater than 0");
        require(currentRoundID >= 1, "should greater than 1");
        _setRoundBegin(currentRoundID, price);
        emit RoundBeginEvent(currentRoundID, Games[currentRoundID]);
    }

    function ExecuteRoundLock() public whenNotPaused notContract {
        require(block.timestamp <= (Games[currentRoundID].LockTime + intervalBuffer), "should execute before lock time with tolerance");
        require(block.timestamp >= Games[currentRoundID].LockTime, "should execute after lock time");

        int256 price = GetLatestPrice();
        require(price >= 0, "price should greater than 0");
        _setRoundLock(currentRoundID, price);
        emit LockRoundEvent(currentRoundID, msg.sender, price, uint32(block.timestamp));
    }

    function ExecuteRoundEnd() public whenNotPaused notContract {
        require(block.timestamp <= (Games[currentRoundID].EndTime + intervalBuffer), "should execute after end time in tolerance interval");
        require(block.timestamp >= Games[currentRoundID].EndTime, "should execute after end time");

        int256 price = GetLatestPrice();
        require(price >= 0, "price should greater than 0");
        _setRoundEnd(currentRoundID, price);
        currentRoundID = currentRoundID + 1;
        emit EndRoundEvent(currentRoundID, msg.sender, price, uint32(block.timestamp));
    }

    function GetLatestPrice() public view returns (int256) {
        (,int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }

    function BetBull() public payable whenNotPaused nonReentrant notContract bettable {
        uint256 amount = msg.value;
        RoundInfo storage game = Games[currentRoundID];
        game.PredictBullAmount = game.PredictBullAmount + amount;
        game.PredictBullParticipants = game.PredictBullParticipants + 1;
        
        Bets[currentRoundID][msg.sender].RoundID = currentRoundID;
        Bets[currentRoundID][msg.sender].Amount = amount;
        Bets[currentRoundID][msg.sender].Predict = Prediction.Bull;
        emit BetBullEvent(msg.sender, currentRoundID, amount);
    } 

    function BetBear() public payable whenNotPaused nonReentrant notContract bettable {
        uint256 amount = msg.value;
        RoundInfo storage game = Games[currentRoundID];
        game.PredictBearAmount = game.PredictBearAmount + amount;
        game.PredictBearParticipants = game.PredictBearParticipants + 1;

        Bets[currentRoundID][msg.sender].RoundID = currentRoundID;
        Bets[currentRoundID][msg.sender].Amount = amount;
        Bets[currentRoundID][msg.sender].Predict = Prediction.Bear;
        emit BetBearEvent(msg.sender, currentRoundID, amount);
    }

    // 贏家可以拿走自己的 share 以及和輸家全部錢平分給贏家
    function CalculateResult(uint256 _round) public whenNotPaused notContract {
        require(Games[_round].EndPrice > 0, "not yet set up end price");
        require(!Results[_round].BeCalculated, "already be calculated");
        require(block.timestamp >= Games[_round].EndTime + intervalBuffer * 2, "should call after end time with twice buffer time");
        
        uint256 bearParticipants = Games[_round].PredictBearParticipants;
        uint256 bullParticipants = Games[_round].PredictBullParticipants;
        uint256 bullAmount = Games[_round].PredictBullAmount;
        uint256 bearAmount = Games[_round].PredictBearAmount;
        int256 lockPrice = Games[_round].LockPrice;
        int256 endPrice = Games[_round].EndPrice;

        
        require(bearParticipants > 0, "bearParticipants should greater than 0");
        require(bullParticipants > 0, "bullParticipants should greater than 0");
        require(bullAmount > 0, "bullParticipants should greater than 0");
        require(bearAmount > 0, "bullParticipants should greater than 0");
        require(lockPrice > 0, "lockPrice should greater than 0");
        require(endPrice > 0, "endPrice should greater than 0");

        // bull
        if (endPrice > lockPrice) {
            Results[_round].Share = bearAmount / bullParticipants;
            Results[_round].Answer = Result.Bull;
        }
        // bear
        if (endPrice < lockPrice) {
            Results[_round].Share = bullAmount / bearParticipants;
            Results[_round].Answer = Result.Bear;
        }
        // no winner 
        if (endPrice == lockPrice) {
            Results[_round].Answer = Result.NoWinner;
        } else {
            require(Results[_round].Share > 0, "share should greater than 0");
        }

        Results[_round].BeCalculated = true;  

        emit CalculateResultEvent(currentRoundID, msg.sender);      
    }
    
    function ClaimReward(uint256 _round) public whenNotPaused nonReentrant notContract {
        require(Results[_round].BeCalculated, "result should be calculated first");
        require(Bets[_round][msg.sender].Amount > 0, "users amount should greater than 0");
        require(block.timestamp >= Games[_round].EndTime + intervalBuffer * 2, "should claim reward after end time with twice buffer time");
        
        uint256 claimAmount = 0;

        // 退費
        if (Results[_round].Answer == Result.NoWinner) {
            claimAmount = Bets[_round][msg.sender].Amount;
             _safeTransfer(msg.sender, claimAmount);
        }
        // 獲勝
        if ((Results[_round].Answer == Result.Bear && Bets[_round][msg.sender].Predict == Prediction.Bear) ||
         (Results[_round].Answer == Result.Bear && Bets[_round][msg.sender].Predict == Prediction.Bear)) {
            claimAmount = Bets[_round][msg.sender].Amount + Results[_round].Share;
            Bets[_round][msg.sender].Amount = 0;
            _safeTransfer(msg.sender, claimAmount);
        }

        emit ClaimRewardEvent(currentRoundID, msg.sender, claimAmount);
    }

    function SetInterval(uint256 _interval) public onlyOwner {
        interval = _interval;
        emit SetIntervalEvent(_interval, uint32(block.timestamp));
    }

    function SetIntervalBuffer(uint256 _intervalBuffer) public onlyOwner {
        intervalBuffer = _intervalBuffer;
        emit SetIntervalBufferEvent(_intervalBuffer, uint32(block.timestamp));
    }

    function SetMinBetAmount(uint256 _amount) public onlyOwner {
        minBetAmount = _amount;
        emit SetMinBetAmountEvent(_amount, uint32(block.timestamp));
    }

    function Pause() public onlyOwner whenNotPaused {
        _pause();
        emit PauseEvent(currentRoundID);
    }

    function Resume() public onlyOwner whenPaused {
        _unpause();
        emit UnpausedEvent(currentRoundID);
    }

    function _safeTransfer(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, "Transfer Failed");
    }

    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

}