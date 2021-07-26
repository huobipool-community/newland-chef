let {MDX_ROUTER,
    USDT,
    MDX,
    WHT,
    HPT,
    BOO,
    MDX_FACTORY,
    TenBankHall,
    MDX_CHEF
} = $config;
let erc20Artifact = '@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20'

let chef
let signer
let signerAddress = '0x2f1178bd9596ab649014441dDB83c2f240B5527C'
let strategyAbi = require('../source/abis/boosterStrategy')
let tenBankHallAbi = require('../source/abis/tenBankHall')
let strategy = '0xAfaf11781664705Ba3Cd3cC4E9186F13368F6728'

describe("BoosterStakingChef", function () {
    before(async function () {
        let emergency = await $deploy('Treasury')

        chef = await $deploy('BoosterStakingChef',
            HPT,
            '10000000000000000',
            0,
            '100000000000000000',
            BOO,
            '0x2f1178bd9596ab649014441dDB83c2f240B5527C',
            MDX_FACTORY,
            WHT,
            MDX_CHEF,
            TenBankHall
        )

        if (chef.$isNew) {
            await emergency.$transferOwnership(chef.address);
            await chef.$setEmergencyAddress(emergency.address);

            // USDT-HPT
            await chef.$add(10, 43)
        }

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [signerAddress]}
        );
        signer = await ethers.provider.getSigner(signerAddress);

        const usdt = await ethers.getContractAt(erc20Artifact,USDT);
        const hpt = await ethers.getContractAt(erc20Artifact,HPT);

        await usdt.connect(signer).approve(chef.address,"100000000000000000000");
        await hpt.connect(signer).approve(chef.address,"100000000000000000000");

        const strategyIns = await ethers.getContractAt(strategyAbi, strategy);
        let strategyOwner = await strategyIns.owner();
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [strategyOwner]}
        );
        let strategyOwnerSigner = await ethers.provider.getSigner(strategyOwner);
        await strategyIns.connect(strategyOwnerSigner).setWhitelist(chef.address, true)
        console.log(await strategyIns.whitelist(chef.address))

        const bankIns = await ethers.getContractAt(tenBankHallAbi, TenBankHall);
        let bankOwner = await strategyIns.owner();
        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [bankOwner]}
        );
        let bankOwnerSigner = await ethers.provider.getSigner(bankOwner);

        await bankIns.connect(bankOwnerSigner).setEmergencyEnabled(43, true)
    })
    it("deposit", async function () {
        await chef.$connect(signer).$depositTokens(0, USDT, HPT, "3000000000000000000", "3000000000000000000", 0 ,0)
    })
    it("withdraw", async function () {
        const usdt = await ethers.getContractAt(erc20Artifact,USDT);
        const hpt = await ethers.getContractAt(erc20Artifact,HPT);

        console.log('usdt', (await usdt.balanceOf(signerAddress)).toString())
        console.log('hpt', (await hpt.balanceOf(signerAddress)).toString())
        await chef.$connect(signer).$withdrawTokens(0, USDT, HPT, '1000000000', 0 ,0)
        console.log('usdt', (await usdt.balanceOf(signerAddress)).toString())
        console.log('hpt', (await hpt.balanceOf(signerAddress)).toString())
    })
    it("deposit", async function () {
        await chef.$connect(signer).$depositTokens(0, USDT, HPT, "3000000000000000000", "3000000000000000000", 0 ,0)
    })
    it("emergencyWithdraw", async function () {
        await chef.$emergencyWithdraw(0)
        await chef.$connect(signer).$userEmergencyWithdraw(0)
    })
    it("info", async function () {
        console.log(await chef.$getPoolData(0));
        console.log(await chef.$poolInfo(0));
    })
})
