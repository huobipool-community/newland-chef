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
    let emergency = await $deploy('Treasury')

    let chef = await $deploy('BoosterStakingChef',
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

    console.log('---done')
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
