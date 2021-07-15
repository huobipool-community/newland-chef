let fs = require('fs')
let dataJson = require('./_data')
let abiHome = '../artifacts/contracts/'

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

let doc = '### 合约信息 \n'
let dataKey = "128-" + config.$configKey
for (let key of Object.keys(dataJson[dataKey])) {
    let ss = key.split('/')
    let name = ss[0]
    let args = '['+ss[1].split(',').join(',\n')+']'
    let address = dataJson[dataKey][key]
    doc += `
#### ${name}
- 合约地址 ${address}     
- 初始化参数
\`\`\`
${args}     
\`\`\`  
- 合约ABI
\`\`\`
${JSON.stringify(require(abiHome + `${name}.sol/${name}.json`).abi)}
\`\`\`        
`;
}

fs.writeFileSync(process.cwd() + '/README.md', doc)

console.log('---done')