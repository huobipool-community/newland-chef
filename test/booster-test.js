let {MDX_ROUTER,
    USDT,
    MDX,
    WHT,
    HPT,
    BOO,
    MDX_FACTORY,
    TenBankHall
} = $config;
let erc20Artifact = '@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20'

let chef
let signer
let signerAddress = '0x2f1178bd9596ab649014441dDB83c2f240B5527C'
describe("BoosterStakingChef", function () {
    before(async function () {
        chef = await $deploy('BoosterStakingChef',
            HPT,
            '10000000000000000',
            0,
            '100000000000000000',
            BOO,
            '0x2f1178bd9596ab649014441dDB83c2f240B5527C',
            MDX_FACTORY,
            WHT
        )

        if (chef.$isNew) {
            await chef.$add(10, TenBankHall, 15)
        }

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [signerAddress]}
        );
        signer = await ethers.provider.getSigner(signerAddress);

        const usdt = await ethers.getContractAt(erc20Artifact,USDT);
        const hpt = await ethers.getContractAt(erc20Artifact,HPT);

        await usdt.connect(signer).approve(chef.address,"3000000000000000000");
        await hpt.connect(signer).approve(chef.address,"3000000000000000000");
    })
    it("deposit", async function () {
        await chef.$connect(signer).$depositTokens(0, USDT, HPT, "3000000000000000000", "3000000000000000000", 0 ,0)
    })
    it("withdraw", async function () {
        await chef.$connect(signer).$withdrawTokens(0, USDT, HPT, '1000000000', 0 ,0)
    })
})
