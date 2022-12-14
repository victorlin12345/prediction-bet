// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

contract MockOracle {

   struct FakeLatestRoundData {
      uint80 roundId;
      int256 answer;
      uint256 startedAt;
      uint256 updatedAt;
      uint80 answeredInRound;
   }

   FakeLatestRoundData FakeData;

   constructor(int256 _answer) {
    FakeData.roundId = 1;
    FakeData.answer = _answer;
    FakeData.startedAt = 1671033600;
    FakeData.updatedAt = 1671033600;
    FakeData.answeredInRound = 1;
   }

  function decimals() external view returns (uint8){
    return 18;
  }

  function description() external view returns (string memory) {
    return "mock oracle";
  }

  function version() external view returns (uint256) {
    return 0;
  }

  function getRoundData(uint80 _roundId) external view
  returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
        return (FakeData.roundId, FakeData.answer, FakeData.startedAt, FakeData.updatedAt, FakeData.answeredInRound);
    }

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ){
        return (FakeData.roundId, FakeData.answer, FakeData.startedAt, FakeData.updatedAt, FakeData.answeredInRound);
    }

    function setFakeLatestRoundData(int256 _answer) external {
        FakeData.answer = _answer;
    }
}