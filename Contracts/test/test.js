const {
  BN, // Big Number support
  constants, // Common constants, like the zero address and largest integers
  expectEvent, // Assertions for emitted events
  expectRevert, // Assertions for transactions that should fail
} = require("@openzeppelin/test-helpers");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");
const ether = require("@openzeppelin/test-helpers/src/ether");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Hub", async function () {
  let hub;
  let owner;
  let addr1;
  let addr2;
  let addrs;
  let TestUID = "test";
  let TestURI = "https://test.com/";
  let TestKusamaAddress = "test_addr";

  beforeEach(async function () {
    Hub = await ethers.getContractFactory("Hub");
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    hub = await Hub.deploy();
  });

  describe("Basic functionality", async function () {
    describe("Deployment", async function () {
      it("Should set right owner", async function () {
        expect(await hub.owner()).to.equal(owner.address);
      });

      it("Check total supply", async function () {
        expect(await hub.getCurrentSupply()).to.equal(0);
      });
    });

    describe("Transactions", async function () {
      it("Should create RMRK order and emit event createdRMRKOrder", async function () {
        const tx = await hub
          .connect(addr1)
          .createRMRKOrder(addr1.address, TestUID);
        const receipt = await tx.wait();

        expect(await hub.balanceOf(addr1.address)).to.equal(0);
        receipt.events?.filter((x) => {
          return x.event == "createdRMRKOrder";
        });
      });

      it("Should revert create MOVR order", async function () {
        await expect(
          hub.connect(addr1).createMOVROrder(TestKusamaAddress, TestUID)
        ).to.be.revertedWith("ERC721: owner query for nonexistent token");
      });

      it("Should conduct a full normal cycle of nft translation", async function () {
        await hub.connect(addr1).createRMRKOrder(addr1.address, TestUID);

        //Attempt to fill in not by the owner
        await expect(
          hub.connect(addr1).fillRMRKOrder(addr1.address, TestUID, TestURI, [])
        ).to.be.reverted;

        await hub
          .connect(owner)
          .fillRMRKOrder(addr1.address, TestUID, TestURI, []);

        expect(await hub.balanceOf(addr1.address)).to.equal(1);
        expect(await hub.ownerOf(0)).to.equal(addr1.address);
        expect(await hub.getID(TestUID)).to.equal(0);
        expect(await hub.getUID(0)).to.equal(TestUID);
        expect(await hub.getCurrentSupply()).to.equal(1);

        await hub.connect(addr1).createMOVROrder(TestKusamaAddress, TestUID);

        expect(await hub.balanceOf(addr1.address)).to.equal(0);
        expect(await hub.getCurrentSupply()).to.equal(1);

        //Check movr orders
        let movr_orders = await hub.getMOVROrders();
        expect(movr_orders.length).to.equal(1);

        //Attempt to fill in not by the owner
        await expect(hub.connect(addr1).fillMOVROrders(1)).to.be.reverted;

        await hub.connect(owner).fillMOVROrders(1);

        //Check movr orders
        movr_orders = await hub.getMOVROrders();
        expect(movr_orders.length).to.equal(0);
      });

      it("Should conduct a full not normal cycle of nft translation", async function () {
        //Attempt to fill in not by the owner
        await expect(
          hub.connect(addr1).fillRMRKOrder(addr1.address, TestUID, TestURI, [])
        ).to.be.reverted;

        await hub
          .connect(owner)
          .fillRMRKOrder(addr1.address, TestUID, TestURI, []);

        expect(await hub.balanceOf(addr1.address)).to.equal(0);
        expect(await hub.getCurrentSupply()).to.equal(0);

        await hub.connect(addr1).createRMRKOrder(addr1.address, TestUID);

        expect(await hub.balanceOf(addr1.address)).to.equal(1);
        expect(await hub.ownerOf(0)).to.equal(addr1.address);
        expect(await hub.getID(TestUID)).to.equal(0);
        expect(await hub.getUID(0)).to.equal(TestUID);
        expect(await hub.getCurrentSupply()).to.equal(1);

        await hub.connect(addr1).createMOVROrder(TestKusamaAddress, TestUID);

        expect(await hub.balanceOf(addr1.address)).to.equal(0);
        expect(await hub.getCurrentSupply()).to.equal(1);

        //Check movr orders
        let movr_orders = await hub.getMOVROrders();
        expect(movr_orders.length).to.equal(1);

        //Attempt to fill in not by the owner
        await expect(hub.connect(addr1).fillMOVROrders(1)).to.be.reverted;

        await hub.connect(owner).fillMOVROrders(1);

        //Check movr orders
        movr_orders = await hub.getMOVROrders();
        expect(movr_orders.length).to.equal(0);
      });
    });

    describe("Pay", async function () {
      it("Should pay on", async function () {
        expect(await hub.paymentsOn()).to.false;
        await hub.connect(owner).switchFee(true);
        expect(await hub.paymentsOn()).to.true;
      });

      it("Should change payments", async function () {
        await hub.connect(owner).switchFee(true);

        expect(await hub.getServerPayments()).to.equal(0);
        expect(await hub.getDeployPayments()).to.equal(0);
        await hub.connect(owner).changeServerPayments(1);
        await hub.connect(owner).changeDeployPayments(1);
        expect(await hub.getServerPayments()).to.equal(1);
        expect(await hub.getDeployPayments()).to.equal(1);
      });

      it("Should pay and create an order", async function () {
        await hub.connect(owner).switchFee(true);
        await hub
          .connect(owner)
          .changeServerPayments(ethers.utils.parseEther("1"));
        await hub
          .connect(owner)
          .changeDeployPayments(ethers.utils.parseEther("1"));

        const receiver = await hub.getAddressReceiver();
        const bank = await hub.getAddressBank();
        const start_balance = await ethers.provider.getBalance(addr1.address);

        await expect(hub.connect(addr1).createRMRKOrder(addr1.address, TestUID))
          .to.be.reverted;

        await hub.connect(addr1).createRMRKOrder(addr1.address, TestUID, {
          value: ethers.utils.parseEther("2"),
        });

        expect(await ethers.provider.getBalance(bank)).to.equal(
          ethers.utils.parseEther("1")
        );
        expect(await ethers.provider.getBalance(receiver)).to.equal(
          ethers.utils.parseEther("1")
        );
      });

      it("Should lose money and get it back", async function () {
        await hub.connect(owner).switchFee(true);
        await hub
          .connect(owner)
          .changeServerPayments(ethers.utils.parseEther("1"));
        await hub
          .connect(owner)
          .changeDeployPayments(ethers.utils.parseEther("1"));

        const receiver = await hub.getAddressReceiver();
        const bank = await hub.getAddressBank();
        const bank_balance = await ethers.provider.getBalance(bank);
        const receiver_balance = await ethers.provider.getBalance(receiver);
        const start_balance = await ethers.provider.getBalance(addr1.address);

        await expect(hub.connect(addr1).createRMRKOrder(addr1.address, TestUID))
          .to.be.reverted;

        await hub.connect(addr1).createRMRKOrder(addr1.address, TestUID, {
          value: ethers.utils.parseEther("3"),
        });

        expect(await ethers.provider.getBalance(bank)).to.equal(
          bank_balance.add(ethers.utils.parseEther("1"))
        );
        expect(await ethers.provider.getBalance(receiver)).to.equal(
          receiver_balance.add(ethers.utils.parseEther("1"))
        );

        expect(await hub.connect(addr1).myLostMoney()).to.equal(
          ethers.utils.parseEther("1")
        );

        await hub.connect(addr1).takeMoney();

        expect(await hub.connect(addr1).myLostMoney()).to.equal(
          ethers.utils.parseEther("0")
        );
      });
    });
  });

  describe("Access", async function () {
    it("Reject a call to the fillRMRKOrder function not by the owner", async function () {
      await expect(hub.connect(addr1).fillRMRKOrder(addr1.address, TestUID, TestURI, [])).to.be.reverted;
    });

    it("Reject a call to the fillMOVROrder function not by the owner", async function () {
      await expect(hub.connect(addr1).fillMOVROrders(1)).to.be.reverted;
    });

    it("Reject a call to the switchFee function not by the owner", async function () {
      await expect(hub.connect(addr1).switchFee(true)).to.be.reverted;
    });

    it("Reject a call to the changeAddressBank function not by the owner", async function () {
      await expect(hub.connect(addr1).changeAddressBank(0xb2b009Fe33c8EcE7AC9a1BbE9C438A0795A7dC9b)).to.be.reverted;
    });

    it("Reject a call to the changeAddressReceiver function not by the owner", async function () {
      await expect(hub.connect(addr1).changeAddressReciever(0xb2b009Fe33c8EcE7AC9a1BbE9C438A0795A7dC9b)).to.be.reverted;
    });

    it("Reject a call to the changeDeployPayments function not by the owner", async function () {
      await expect(hub.connect(addr1).changeDeployPayments(1)).to.be.reverted;
    });

    it("Reject a call to the changeServerPayments function not by the owner", async function () {
      await expect(hub.connect(addr1).changeServerPayments(2)).to.be.reverted;
    });

    //Attempt to transfer create an order without payment
    it("Attempt to transfer create an order without payment", async function () {
      await hub.connect(owner).switchFee(true);
      await hub
        .connect(owner)
        .changeServerPayments(ethers.utils.parseEther("1"));
      await hub
        .connect(owner)
        .changeDeployPayments(ethers.utils.parseEther("1"));
      await expect(hub.connect(addr1).createRMRKOrder(addr1.address, TestUID)).to.be.reverted;
    });

    //Attempt to transfer the nft without having rights to it
    it("Attempt to transfer the nft without having rights to it", async function () {

      //Start minting
      await hub.connect(addr1).createRMRKOrder(addr1.address, TestUID);

      await hub
        .connect(owner)
        .fillRMRKOrder(addr1.address, TestUID, TestURI, []);
      //End minting

      await expect(hub.connect(addr2).transferFrom(addr1.address, addr2.address, 0)).to.be.reverted;
      await expect(hub.connect(owner).transferFrom(addr1.address, addr2.address, 0)).to.be.reverted;

      await hub.connect(addr1).transferFrom(addr1.address, addr2.address, 0);

      await expect(hub.connect(addr1).transferFrom(addr2.address, addr1.address, 0)).to.be.reverted;
      await expect(hub.connect(owner).transferFrom(addr2.address, addr1.address, 0)).to.be.reverted;

    });
  });
});
