let dataPath = process.cwd() + '/scripts/_data.json'
let fs = require('fs')
let artifactPath = process.cwd() + '/artifacts'
let Web3 = require('web3');
let web3 = global.web3 || new Web3('http://localhost:8545')
let configs = require('./_config')
let config
for(let configKey of Object.keys(configs)) {
    config = configs[configKey]
    if (config.$import) {
        config.$configKey = configKey
        break
    }
}
if (!config) {
    throw 'no config found with $import: true'
}

async function deploy(name, ...args) {
    const [deployer] = await ethers.getSigners();
    console.log(`------Deploying ${name} with the account:`, deployer.address);

    let getContractFactoryName = name
    let flPath = artifactPath + '/contracts/' + name + '_fl.sol'
    if (fs.existsSync(flPath) && fs.readdirSync(flPath).length > 0) {
        getContractFactoryName = 'contracts/' + name + '_fl.sol:' + name
        console.log(getContractFactoryName)
    }
    const Contract = await ethers.getContractFactory(getContractFactoryName);
    let contract;
    let chainId = (await ethers.provider.getNetwork()).chainId
    if (!fs.existsSync(dataPath)) {
        fs.writeFileSync(dataPath, JSON.stringify({}, null, 2))
    }
    let data = JSON.parse(String(fs.readFileSync(dataPath)))

    let dataKey = [chainId, config.$configKey].join('-')
    if (!data[dataKey]) {
        data[dataKey] = {}
    }
    let key = name+ '/' +args.join(',')
    let chainData = data[dataKey]
    let address = chainData[key]
    if (address) {
        contract = Contract.attach(address);
        console.log(`Exist Contract ${name} address: ${contract.address}`);
    } else {
        contract = await Contract.deploy(...args)
        contract.$isNew = true
        console.log('\x1B[32m%s\x1B[39m', `Deploy Contract ${name} address: ${contract.address}`);
        chainData[key] = contract.address;
        fs.writeFileSync(dataPath, JSON.stringify(data, null, 2))
    }

    loggerObj(name, contract)
    return contract
}

async function getAddress(name, chainId) {
    return (await getContract(name, chainId)).address
}

async function getContract(name, chainId) {
    let result = await $eachContract(async (c, n, a) => {
        if (n === name) {
            return c
        }
    }, chainId)
    return result[0];
}

async function selectContracts(name, opt = {}, chainId) {
    return await $eachContract(async (c, n, a) => {
        if (n === name) {
            let valid = true
            for (let index of Object.keys(opt)) {
                if (String(opt[index]).toLowerCase() !== String(a[index]).toLowerCase()) {
                    valid = false
                }
            }
            if (valid) {
                return c
            }
        }
    }, chainId);
}

async function getDeployInitData(address, chainId) {
    if (chainId !== 0 && !chainId) {
        chainId = (await ethers.provider.getNetwork()).chainId
    }
    let dataKey = [chainId, config.$configKey].join('-')
    let data = JSON.parse(String(fs.readFileSync(dataPath)))[dataKey]
    if (!data) {
        return null
    }
    let name;
    let args;
    for (let key of Object.keys(data)) {
        if (data[key].toLowerCase() === address.toLowerCase()) {
            let strs = key.split('/');
            name = strs[0]
            args = strs[1]
            break
        }
    }
    if (!name || !args) {
        return null
    }

    let sourcePath = process.cwd() + '/contracts/' + name + '.sol'
    let argsArray = args.split(',')

    let source = String(fs.readFileSync(sourcePath))
    let methodArgs = source.split(/constructor\s*\(/g)[1].split(/\)\s*public/g)[0]
    let methodTypes = methodArgs.split(',').filter(s => s).map(s => s.trim().split(/\s+/)[0])

    for(let i = 0;i<methodTypes.length;i++) {
        if (!isBaseType(methodTypes[i])) {
            methodTypes[i] = 'address'
        }
    }
    return web3.eth.abi.encodeParameters(methodTypes, argsArray).replace(/^0x/, '')
}

function isBaseType(type) {
    for (let prefix of ['address', 'uint', 'int', 'byte', 'string']) {
        if (type.startsWith(prefix)) {
            return true;
        }
    }
    return false
}

function loggerObj(name, obj) {
    for (let key of Object.keys(obj)) {
        if (typeof obj[key] === "function") {
            let origin = obj[key]
            obj["$" + key] = async (...args) => {
                console.log('\x1B[32m%s\x1B[39m', `#${name}.${key} ${args}`);
                return await origin(...args);
            }
        }
    }
    return obj
}

function encodeParams(types, ...args) {
    return web3.eth.abi.encodeParameters(types, args)
}

function decodeParams(types, data) {
    return web3.eth.abi.decodeParameters(types, data)
}

async function evmGoSec(seconds) {
    console.log('\x1B[32m%s\x1B[39m', "#evm_increaseTime " + seconds)
    return await ethers.provider.send("evm_increaseTime", [seconds])
}

async function eachContract(fn, chainId) {
    if (chainId !== 0 && !chainId) {
        chainId = (await ethers.provider.getNetwork()).chainId
    }
    if (!fs.existsSync(dataPath)) {
        return null
    }
    let data = JSON.parse(String(fs.readFileSync(dataPath)))

    let dataKey = [chainId, config.$configKey].join('-')
    if (!data[dataKey]) {
        data[dataKey] = {}
    }
    let chainData = data[dataKey]

    let result = []
    for (let key of Object.keys(chainData)) {
        let strs = key.split('/')
        let name = strs[0]
        let args = strs[1].split(',')

        let getContractFactoryName = name
        let flPath = artifactPath + '/contracts/' + name + '_fl.sol'
        if (fs.existsSync(flPath) && fs.readdirSync(flPath).length > 0) {
            getContractFactoryName = 'contracts/' + name + '_fl.sol:' + name
        }
        const Contract = await ethers.getContractFactory(getContractFactoryName);

        let contract = Contract.attach(chainData[key]);
        loggerObj(name, contract);
        contract.$connect = signer => loggerObj(name, contract.connect(signer));

        let val = await fn(contract, name, args)
        if (val) {
            result.push(val)
        }
    }
    return result
}

async function sleep(milliseconds) {
    return new Promise(resolve => {
        setTimeout(() => {
            resolve()
        }, milliseconds)
    })
}


global.$deploy = deploy
global.$getAddress = getAddress
global.$getContract = getContract
global.$getDeployInitData = getDeployInitData
global.$encodeParams = encodeParams
global.$decodeParams = decodeParams
global.$evmGoSec = evmGoSec
global.$config = config
global.$eachContract = eachContract
global.$selectContracts = selectContracts
global.$sleep = sleep

