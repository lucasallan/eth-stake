const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("EthStaking", function () {
  let EthStaking;
  let StakedToken;
  let ethStaking;
  let stakedToken;
  let owner;
  let addr1;
  let addr2;
  let addrs;

  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    
    StakedToken = await ethers.getContractFactory("StakedToken", owner);
    stakedToken = await upgrades.deployProxy(StakedToken, [], {
      initializer: 'initialize',
      kind: 'uups'
    });
    await stakedToken.waitForDeployment();

    EthStaking = await ethers.getContractFactory("EthStaking", owner);
    ethStaking = await upgrades.deployProxy(EthStaking, [await stakedToken.getAddress()], {
      initializer: 'initialize',
      kind: 'uups'
    });
    await ethStaking.waitForDeployment();

    await stakedToken.transferOwnership(await ethStaking.getAddress());

    await owner.sendTransaction({
      to: await ethStaking.getAddress(),
      value: ethers.parseEther("10.0")
    });
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await ethStaking.owner()).to.equal(await owner.getAddress());
    });

    it("Should initialize with correct reward rate", async function () {
      expect(await ethStaking.getRewardRate()).to.equal(1e14);
    });

    it("Should set StakedToken ownership to EthStaking contract", async function () {
      expect(await stakedToken.owner()).to.equal(await ethStaking.getAddress());
    });
  });

  describe("Staking", function () {
    it("Should allow staking ETH and receive stETH", async function () {
      const stakeAmount = ethers.parseEther("1.0");
      await expect(ethStaking.connect(addr1).stake({ value: stakeAmount }))
        .to.emit(stakedToken, "Transfer")
        .withArgs(ethers.ZeroAddress, addr1.address, stakeAmount);
      
      const stake = await ethStaking.getStake(addr1.address);
      expect(stake.amount).to.equal(stakeAmount);
      expect(await stakedToken.balanceOf(addr1.address)).to.equal(stakeAmount);
    });

    it("Should not allow staking 0 ETH", async function () {
      await expect(ethStaking.connect(addr1).stake({ value: 0 }))
        .to.be.revertedWith("Cannot stake 0 ETH");
    });
  });

  describe("Withdrawals", function () {
    const stakeAmount = ethers.parseEther("1.0");

    beforeEach(async function () {
      await ethStaking.connect(addr1).stake({ value: stakeAmount });
      await time.increase(61);
    });

    it("Should allow withdrawing staked ETH by burning stETH", async function () {
      await expect(ethStaking.connect(addr1).withdraw(stakeAmount))
        .to.emit(stakedToken, "Transfer")
        .withArgs(addr1.address, ethers.ZeroAddress, stakeAmount);
      
      const stake = await ethStaking.getStake(addr1.address);
      expect(stake.amount).to.equal(0);
      expect(await stakedToken.balanceOf(addr1.address)).to.equal(0);
    });

    it("Should not allow withdrawing more than staked amount", async function () {
      const excessAmount = stakeAmount + ethers.parseEther("0.1");
      await expect(ethStaking.connect(addr1).withdraw(excessAmount))
        .to.be.revertedWith("Insufficient staked amount");
    });

    it("Should not allow withdrawing 0 ETH", async function () {
      await expect(ethStaking.connect(addr1).withdraw(0))
        .to.be.revertedWith("Cannot withdraw 0 ETH");
    });

    it("Should not allow withdrawing without sufficient stETH balance", async function () {
      await stakedToken.connect(addr1).transfer(addr2.address, stakeAmount);
      
      await expect(ethStaking.connect(addr1).withdraw(stakeAmount))
        .to.be.reverted;
    });
  });

  describe("StakedToken", function () {
    const stakeAmount = ethers.parseEther("1.0");

    beforeEach(async function () {
      await ethStaking.connect(addr1).stake({ value: stakeAmount });
      await time.increase(61);
    });

    it("Should allow transferring stETH tokens", async function () {
      await expect(stakedToken.connect(addr1).transfer(addr2.address, stakeAmount))
        .to.emit(stakedToken, "Transfer")
        .withArgs(addr1.address, addr2.address, stakeAmount);
      
      expect(await stakedToken.balanceOf(addr2.address)).to.equal(stakeAmount);
      expect(await stakedToken.balanceOf(addr1.address)).to.equal(0);
    });

    it("Should maintain correct total supply", async function () {
      const initialSupply = await stakedToken.totalSupply();
      
      await ethStaking.connect(addr2).stake({ value: stakeAmount });
      expect(await stakedToken.totalSupply()).to.equal(initialSupply + stakeAmount);
      
      await ethStaking.connect(addr1).withdraw(stakeAmount);
      expect(await stakedToken.totalSupply()).to.equal(initialSupply);
    });
  });

  describe("Rewards", function () {
    const stakeAmount = ethers.parseEther("1.0");

    beforeEach(async function () {
      await ethStaking.connect(addr1).stake({ value: stakeAmount });
    });

    it("Should accumulate rewards over time", async function () {
      await time.increase(86400);
      
      const rewards = await ethStaking.getRewards(addr1.address);
      expect(rewards).to.be.gt(0);
    });

    it("Should allow claiming rewards", async function () {
      await time.increase(86400);
      
      const initialBalance = await ethers.provider.getBalance(addr1.address);
      await ethStaking.connect(addr1).claimRewards();
      
      const finalBalance = await ethers.provider.getBalance(addr1.address);
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("Should not affect stETH balance when claiming rewards", async function () {
      await time.increase(86400);
      
      const initialStETHBalance = await stakedToken.balanceOf(addr1.address);
      await ethStaking.connect(addr1).claimRewards();
      const finalStETHBalance = await stakedToken.balanceOf(addr1.address);
      
      expect(finalStETHBalance).to.equal(initialStETHBalance);
    });
  });

  describe("Reentrancy Protection", function () {
    let mockReentrantContract;
    const stakeAmount = ethers.parseEther("1.0");

    beforeEach(async function () {
      const MockReentrantContract = await ethers.getContractFactory("MockReentrantContract");
      mockReentrantContract = await MockReentrantContract.deploy(
        await ethStaking.getAddress(),
        await stakedToken.getAddress()
      );
      await mockReentrantContract.waitForDeployment();

      await owner.sendTransaction({
        to: await mockReentrantContract.getAddress(),
        value: ethers.parseEther("5.0")
      });

      await mockReentrantContract.stake({ value: stakeAmount });
      await time.increase(61);
    });

    it("Should prevent reentrancy on withdrawals", async function () {
      try {
        await mockReentrantContract.attackWithdraw(stakeAmount);
        expect.fail("Transaction should have reverted");
      } catch (error) {
        const errorMessage = error.message.toLowerCase();
        expect(
          errorMessage.includes("reentrant call") || 
          errorMessage.includes("eth transfer failed")
        ).to.be.true;
      }
    });

    it("Should prevent reentrancy on reward claims", async function () {
      await time.increase(86400);
      try {
        await mockReentrantContract.attackRewardClaim();
        expect.fail("Transaction should have reverted");
      } catch (error) {
        const errorMessage = error.message.toLowerCase();
        expect(
          errorMessage.includes("reentrant call") || 
          errorMessage.includes("eth transfer failed")
        ).to.be.true;
      }
    });
  });
});
