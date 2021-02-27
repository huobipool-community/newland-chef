
const { expect } = require("chai")
//const { time } = require("./utilities")

const Chef = artifacts.require("MasterChef")
const HPT = artifacts.require("IERC20")
const USDT = artifacts.require("IERC20")
const LP = artifacts.require("IERC20");

const _mdxFactory = '0xb0b670fc1f7724119963018db0bfa86adb22d941';
const _WHT = '0x5545153ccfca01fbd7dd11c0b23ba694d9509a6f';
const _mdxChef = '0xFB03e11D93632D97a8981158A632Dd5986F5E909';
const _hptAddress = '0xe499ef4616993730ced0f31fa2703b92b50bb536';
const _usdtAddress = '0xa71EdC38d189767582C38A3145b5873052c3e47a';
const _mdx = '0x25d2e80cb6b86881fd7e07dd263fb79f4abe033c';


const _usdthpt = '0xdE5b574925EE475c41b99a7591EC43E92dCD2fc1';
const other = '0x124a9013652a6FDB8c7be1C5201850F448aA4Bbf';

describe("MasterChef", function () {
  before(async function () {
    let accounts = await web3.eth.getAccounts();

    this.deployer = accounts[0];
    this.bob = accounts[1];
    this.carol = accounts[2];
    this.alice = accounts[3];

    console.log(accounts[0]);
  })

  beforeEach(async function () {
    this.hpt = await HPT.at(_hptAddress);
    this.usdt = await USDT.at(_usdtAddress);
    this.lp = await LP.at(_usdthpt);
  })
 
  it("should set correct state variables", async function () {
    this.chef = await Chef.new(_hptAddress, "100000", "0", "1",
      _mdxFactory,
      _WHT,
      _mdxChef,
      1,
      _mdx
    );
    //get hpt
    await this.hpt.transfer(
      this.deployer,
      web3.utils.toHex('200000000000000000000'),
      { from: other }  
    );
    await this.usdt.transfer(
      this.deployer,
      web3.utils.toHex('20000000000000000000'),
      { from: other }  
    );
    console.log((await this.hpt.balanceOf(this.deployer)).toString());
    
    //transfer hpt to chef 
    await this.hpt.approve(this.chef.address,web3.utils.toHex('100000000000000000000000') );
    await this.usdt.approve(this.chef.address,web3.utils.toHex('100000000000000000000000') );
    // await this.hpt.approve(this.test.address,web3.utils.toHex('100000000000000000000000') );
    // await this.usdt.approve(this.test.address,web3.utils.toHex('100000000000000000000000') );
  
    await this.hpt.transfer(
      this.chef.address,
      web3.utils.toHex('10000000000000000000')
    );

    

    let chefHptBalance = (await this.hpt.balanceOf(this.chef.address)).toString();
    expect(chefHptBalance).to.equal("10000000000000000000")
  })

  context("With ERC/LP token added to the field", function () {
    beforeEach(async function () {

    })
    
    it("should depositTokens properly for each staker", async function () {

      await this.chef.add("10", this.lp.address, 18, true)
      expect((await this.chef.poolLength()).toString()).to.equal("1");
      console.log("start");
      let result = await this.chef.depositTokens(0, "0xa71EdC38d189767582C38A3145b5873052c3e47a",
          "0xE499Ef4616993730CEd0f31FA2703B92B50bB536","1000000000000000000","2000000000000000000",
          0,0);
      console.log(JSON.stringify(result));

      await time.advanceBlockTo("319")
      console.log((await this.chef.poolInfo(0).lpBalance));
      expect(await this.chef.poolInfo(0).lpBalance).to.gt(0)

    });

    // it("should distribute SUSHIs properly for each staker", async function () {
    //   // 100 per block farming rate starting at block 300 with bonus until block 1000
    //   //this.chef = await this.MasterChef.new(this.sushi.address, this.dev.address, "100", "300", "1000")
      
      
    //   await this.chef.add("100", this.lp.address, true)
    //   await this.lp.connect(this.alice).approve(this.chef.address, "1000", {
    //     from: this.alice.address,
    //   })
    //   await this.lp.connect(this.bob).approve(this.chef.address, "1000", {
    //     from: this.bob.address,
    //   })
    //   await this.lp.connect(this.carol).approve(this.chef.address, "1000", {
    //     from: this.carol.address,
    //   })
    //   // Alice deposits 10 LPs at block 310
    //   await time.advanceBlockTo("309")
    //   await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
    //   // Bob deposits 20 LPs at block 314
    //   await time.advanceBlockTo("313")
    //   await this.chef.connect(this.bob).deposit(0, "20", { from: this.bob.address })
    //   // Carol deposits 30 LPs at block 318
    //   await time.advanceBlockTo("317")
    //   await this.chef.connect(this.carol).deposit(0, "30", { from: this.carol.address })
    //   // Alice deposits 10 more LPs at block 320. At this point:
    //   //   Alice should have: 4*1000 + 4*1/3*1000 + 2*1/6*1000 = 5666
    //   //   MasterChef should have the remaining: 10000 - 5666 = 4334
    //   await time.advanceBlockTo("319")
    //   await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
    //   expect(await this.sushi.totalSupply()).to.equal("11000")
    //   expect(await this.sushi.balanceOf(this.alice.address)).to.equal("5666")
    //   expect(await this.sushi.balanceOf(this.bob.address)).to.equal("0")
    //   expect(await this.sushi.balanceOf(this.carol.address)).to.equal("0")
    //   expect(await this.sushi.balanceOf(this.chef.address)).to.equal("4334")
    //   expect(await this.sushi.balanceOf(this.dev.address)).to.equal("1000")
    //   // Bob withdraws 5 LPs at block 330. At this point:
    //   //   Bob should have: 4*2/3*1000 + 2*2/6*1000 + 10*2/7*1000 = 6190
    //   await time.advanceBlockTo("329")
    //   await this.chef.connect(this.bob).withdraw(0, "5", { from: this.bob.address })
    //   expect(await this.sushi.totalSupply()).to.equal("22000")
    //   expect(await this.sushi.balanceOf(this.alice.address)).to.equal("5666")
    //   expect(await this.sushi.balanceOf(this.bob.address)).to.equal("6190")
    //   expect(await this.sushi.balanceOf(this.carol.address)).to.equal("0")
    //   expect(await this.sushi.balanceOf(this.chef.address)).to.equal("8144")
    //   expect(await this.sushi.balanceOf(this.dev.address)).to.equal("2000")
    //   // Alice withdraws 20 LPs at block 340.
    //   // Bob withdraws 15 LPs at block 350.
    //   // Carol withdraws 30 LPs at block 360.
    //   await time.advanceBlockTo("339")
    //   await this.chef.connect(this.alice).withdraw(0, "20", { from: this.alice.address })
    //   await time.advanceBlockTo("349")
    //   await this.chef.connect(this.bob).withdraw(0, "15", { from: this.bob.address })
    //   await time.advanceBlockTo("359")
    //   await this.chef.connect(this.carol).withdraw(0, "30", { from: this.carol.address })
    //   expect(await this.sushi.totalSupply()).to.equal("55000")
    //   expect(await this.sushi.balanceOf(this.dev.address)).to.equal("5000")
    //   // Alice should have: 5666 + 10*2/7*1000 + 10*2/6.5*1000 = 11600
    //   expect(await this.sushi.balanceOf(this.alice.address)).to.equal("11600")
    //   // Bob should have: 6190 + 10*1.5/6.5 * 1000 + 10*1.5/4.5*1000 = 11831
    //   expect(await this.sushi.balanceOf(this.bob.address)).to.equal("11831")
    //   // Carol should have: 2*3/6*1000 + 10*3/7*1000 + 10*3/6.5*1000 + 10*3/4.5*1000 + 10*1000 = 26568
    //   expect(await this.sushi.balanceOf(this.carol.address)).to.equal("26568")
    //   // All of them should have 1000 LPs back.
    //   expect(await this.lp.balanceOf(this.alice.address)).to.equal("1000")
    //   expect(await this.lp.balanceOf(this.bob.address)).to.equal("1000")
    //   expect(await this.lp.balanceOf(this.carol.address)).to.equal("1000")
    // })

    // it("should give proper SUSHIs allocation to each pool", async function () {
    //   // 100 per block farming rate starting at block 400 with bonus until block 1000
    //   this.chef = await this.MasterChef.deploy(this.sushi.address, this.dev.address, "100", "400", "1000")
    //   await this.sushi.transferOwnership(this.chef.address)
    //   await this.lp.connect(this.alice).approve(this.chef.address, "1000", { from: this.alice.address })
    //   await this.lp2.connect(this.bob).approve(this.chef.address, "1000", { from: this.bob.address })
    //   // Add first LP to the pool with allocation 1
    //   await this.chef.add("10", this.lp.address, true)
    //   // Alice deposits 10 LPs at block 410
    //   await time.advanceBlockTo("409")
    //   await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
    //   // Add LP2 to the pool with allocation 2 at block 420
    //   await time.advanceBlockTo("419")
    //   await this.chef.add("20", this.lp2.address, true)
    //   // Alice should have 10*1000 pending reward
    //   expect(await this.chef.pendingSushi(0, this.alice.address)).to.equal("10000")
    //   // Bob deposits 10 LP2s at block 425
    //   await time.advanceBlockTo("424")
    //   await this.chef.connect(this.bob).deposit(1, "5", { from: this.bob.address })
    //   // Alice should have 10000 + 5*1/3*1000 = 11666 pending reward
    //   expect(await this.chef.pendingSushi(0, this.alice.address)).to.equal("11666")
    //   await time.advanceBlockTo("430")
    //   // At block 430. Bob should get 5*2/3*1000 = 3333. Alice should get ~1666 more.
    //   expect(await this.chef.pendingSushi(0, this.alice.address)).to.equal("13333")
    //   expect(await this.chef.pendingSushi(1, this.bob.address)).to.equal("3333")
    // })

    // it("should stop giving bonus SUSHIs after the bonus period ends", async function () {
    //   // 100 per block farming rate starting at block 500 with bonus until block 600
    //   this.chef = await this.MasterChef.deploy(this.sushi.address, this.dev.address, "100", "500", "600")
    //   await this.sushi.transferOwnership(this.chef.address)
    //   await this.lp.connect(this.alice).approve(this.chef.address, "1000", { from: this.alice.address })
    //   await this.chef.add("1", this.lp.address, true)
    //   // Alice deposits 10 LPs at block 590
    //   await time.advanceBlockTo("589")
    //   await this.chef.connect(this.alice).deposit(0, "10", { from: this.alice.address })
    //   // At block 605, she should have 1000*10 + 100*5 = 10500 pending.
    //   await time.advanceBlockTo("605")
    //   expect(await this.chef.pendingSushi(0, this.alice.address)).to.equal("10500")
    //   // At block 606, Alice withdraws all pending rewards and should get 10600.
    //   await this.chef.connect(this.alice).deposit(0, "0", { from: this.alice.address })
    //   expect(await this.chef.pendingSushi(0, this.alice.address)).to.equal("0")
    //   expect(await this.sushi.balanceOf(this.alice.address)).to.equal("10600")
    // })
  })
})
