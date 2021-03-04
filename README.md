### newland-chef

#### Owner 配置管理接口

##### revoke 提取合约内的全部HPT

##### setTreasuryAddress 设置收益地址

- _treasuryAddress 类型address

##### transferOwnership 转移owner权限

- newOwner 类型address

##### setHptPerBlock 设置每个block发放的HPT奖励数量

- _hptPerBlock 类型uint256

##### setMdxProfitRate 设置mdx利润百分比

- _mdxProfitRate 类型uint256 分母为1e18

##### add 添加池子

- _allocPoint  份额占比
- _lpToken   LP token address
- _mdxChefPid  mdx质押池PID
- _withUpdate 是否执行更新

##### set 更新池子信息

- _pid  池子IP
- _allocPoint  份额占比
- _mdxChefPid  mdx质押池PID
- _withUpdate 是否执行更新


