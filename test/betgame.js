const { mine, mineUpTo, time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { parseUnits } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

describe("Bet Game Test", function () {
    const PriceOracleETHUSD = "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419";
    let owner;
    let betGame;

    async function deployContractFixture() {
        // Contracts are deployed using the first signer/account by default
        [owner, ...addrs] = await ethers.getSigners();

        const BetGame = await ethers.getContractFactory("BetGame");
        betGame = await BetGame.deploy(PriceOracleETHUSD);
        await betGame.deployed();

        return { owner, betGame };
    }

    describe("Game Flow", function () {
        before(async () =>  {
            await loadFixture(deployContractFixture);
        });

        it("get latest price > 0:", async function () {
            expect(await betGame.GetLatestPrice()).to.gt(0);
        });
    });

});

