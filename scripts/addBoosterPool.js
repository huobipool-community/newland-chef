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

    // HBTC/USDT=56
    await chef.$add(10, 56)
    // ETH/USDT=57
    await chef.$add(10, 57)

    console.log('---done')
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
