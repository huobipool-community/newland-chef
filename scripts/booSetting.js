
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

async function main() {
    let chef = await $getContract('BoosterStakingChef')

    // await chef.$setHptPerBlock(0);
    // await chef.$emergencyWithdraw(0);
    // await chef.$setProfitAddress('0xb3fc6b9be3ad6b2917d304d4f5645a311bcfd0a8')
    console.log('---done')
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

