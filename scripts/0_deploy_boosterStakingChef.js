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
    let chef = await $deploy('BoosterStakingChef',
        HPT,
        '10000000000000000',
        0,
        '100000000000000000',
        BOO,
        '0x2f1178bd9596ab649014441dDB83c2f240B5527C',
        MDX_FACTORY,
        WHT,
        MDX_CHEF
    )

    if (chef.$isNew) {
        // USDT-HPT
        await chef.$add(10, TenBankHall, 43)
    }

    console.log('---done')
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
