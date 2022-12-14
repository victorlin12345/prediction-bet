const { mine, mineUpTo, time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { parseUnits } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

describe("Bet Game Test", function () {
    // const PriceOracleETHUSD = "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419";
    let owner, user1, user2, user3, user4;
    let betGame, mockOracle;
    let provider = ethers.getDefaultProvider();

    async function deployContractFixture() {
        // Contracts are deployed using the first signer/account by default
        [owner, user1, user2, user3, user4] = await ethers.getSigners();

        const MockOracle = await ethers.getContractFactory("MockOracle");
        mockOracle = await MockOracle.deploy(1200);
        await mockOracle.deployed();

        const BetGame = await ethers.getContractFactory("BetGame");
        betGame = await BetGame.deploy(mockOracle.address);
        await betGame.deployed();

        return { owner, betGame, oracle: mockOracle };
    }

    describe("Game Flow", function () {
        before(async () =>  {
            await loadFixture(deployContractFixture);
        });

        it("mock oracle price 1300", async function () {
            await mockOracle.setFakeLatestRoundData(1300);
            let r = await mockOracle.latestRoundData();
            expect(r[1]).to.eq(1300);
        });

        it("owner execute round1 begin", async function () {
            await betGame.ExecuteRoundBegin();
        });

        it("round1 bet attributes corrected (startTime < lockTime < endTime)", async function () {
            let roundInfo = await betGame.GetRoundInfo(1);
            let roundID = roundInfo[0];
            let startTime = roundInfo[1];
            let lockTime = roundInfo[2];
            let endTime = roundInfo[3];
            expect(roundID).to.eq(1);
            expect(startTime).to.gte(0);
            expect(lockTime).to.gte(startTime);
            expect(endTime).to.gte(lockTime);
        });

        it("user1 bet bull with 1 ethers", async function () {
            await betGame.connect(user1).BetBull({value: ethers.utils.parseEther("1.0")});
            let roundInfo = await betGame.GetRoundInfo(1);
            expect(roundInfo[4].toString()).eq(ethers.utils.parseUnits("1", 18));
        });

        it("user2 bet bull with 1 ethers", async function () {
            await betGame.connect(user2).BetBull({value: ethers.utils.parseEther("1.0")});
            let roundInfo = await betGame.GetRoundInfo(1);
            expect(roundInfo[4].toString()).eq(ethers.utils.parseUnits("2", 18));
        });

        it("user3 bet bear with 1 ethers", async function () {
            await betGame.connect(user3).BetBear({value: ethers.utils.parseEther("1.0")});
        });

        it("mock oracle price 1200", async function () {
            await mockOracle.setFakeLatestRoundData(1200);
            let r = await mockOracle.latestRoundData();
            expect(r[1]).to.eq(1200);
        });

        it("user1 execute round1 lock", async function () {
            await time.increase(3600 * 3);
            await betGame.connect(user1).ExecuteRoundLock();
        });

        it("user4 can't bet after round1 locked", async function () {
            await expect( betGame.connect(user4).BetBear({value: ethers.utils.parseEther("1.0")})).to.be.revertedWith('should bet before lock time');
        });

        it("mock oracle price 1100", async function () {
            await mockOracle.setFakeLatestRoundData(1100);
            let r = await mockOracle.latestRoundData();
            expect(r[1]).to.eq(1100);
        });

        it("user3 execute round1 end", async function () {
            await time.increase(3600 * 3);
            await betGame.connect(user3).ExecuteRoundEnd();
        });


        it("execute calculateResult for round 1", async function () {
            await time.increase(3600 * 1);
            await betGame.CalculateResult(1);
        });

        it("user3 cliams reward total 3 ethers (2.999942533038708666)", async function () {
            const balanceBefore = await ethers.provider.getBalance(user3.address);
            await betGame.connect(user3).ClaimReward(1);
            const balanceAfter = await ethers.provider.getBalance(user3.address);
            expect(balanceAfter).to.gt(balanceBefore);
            expect(balanceAfter.sub(balanceBefore).toString() > ethers.utils.parseEther("2.999"));
        });
    });

});

