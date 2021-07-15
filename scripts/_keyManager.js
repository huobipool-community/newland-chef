const keythereum = require("keythereum");
const prompt = require('prompt-sync')();
const fs = require('fs')
const os = require('os')
const home = os.homedir()

function createKey() {
    let password = prompt('Input password for new address: ', {echo: '*'});;

    let params = { keyBytes: 32, ivBytes: 16 };
    let dk = keythereum.create(params);
    let keyObject = keythereum.dump(password, dk.privateKey, dk.salt, dk.iv);
    console.log(`Address ${keyObject.address} created`)

    let keystoreDir = home + '/.ethereum/keystore'
    if (!fs.existsSync(keystoreDir)) {
        fs.mkdirSync(keystoreDir)
    }
    keythereum.exportToFile(keyObject, keystoreDir);
}

function importKey(address) {
    address = address.replace(/^0x/, '');
    let password;

    let keyObject
    try {
        keyObject = keythereum.importFromFile(address);
    } catch (e) {
        return ''
    }
    if (keyObject) {
        password = prompt(`Input password for ${address}: `, {echo: '*'});
    }
    return '0x' + keythereum.recover(password, keyObject).toString('hex');
}

module.exports = {
    createKey,
    importKey
}

if (process.argv[2] === 'createKey') {
    createKey()
}