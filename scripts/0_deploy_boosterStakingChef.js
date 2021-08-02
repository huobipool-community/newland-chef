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
        '0',
        0,
        '0',
        BOO,
        '0xb3fc6b9be3ad6b2917d304d4f5645a311bcfd0a8',
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
