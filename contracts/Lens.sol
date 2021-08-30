// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

interface IMasterChef {
    function poolInfo(uint256 _pid) external view returns(
        address lpToken,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint256 accHptPerShare,
        uint256 mdxChefPid,
        uint256 lpBalance,
        uint256 accMdxPerShare);
    function mdxProfitRate() external view returns (uint256);
    function mdxChef() external view returns (address);
}
interface IMdxChef {
    function poolInfo(uint256 _pid) external view returns(
        address lpToken,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint256 accMdxPerShare,
        uint256 accMultLpPerShare,
        uint256 totalAmount
    );
    function reward(uint256 blockNumber) external view returns(uint256);
    function totalAllocPoint() external view returns(uint256);
}

contract Main {
    using SafeMath for uint256;

    function mdxRewardPerBlock(uint256 _pid, IMasterChef masterChef) external view returns(uint256) {
        (
        ,
        ,
        ,
        ,
        uint256 mdxChefPid,
        uint256 lpBalance,
        ) = masterChef.poolInfo(_pid);

        IMdxChef mdxChef = IMdxChef(masterChef.mdxChef());

        uint256 mdxTotalAllocPoint = mdxChef.totalAllocPoint();
        (
        ,
        uint256 allocPoint,
        ,
        ,
        ,
        uint256 totalAmount
        ) = mdxChef.poolInfo(mdxChefPid);

        uint256 mdxPerBlock = mdxChef.reward(block.number).mul(allocPoint).div(mdxTotalAllocPoint);
        mdxPerBlock = mdxPerBlock.mul(lpBalance).div(totalAmount);
        uint one = 1e18;
        mdxPerBlock = mdxPerBlock.mul(one.sub(masterChef.mdxProfitRate())).div(one);
        return mdxPerBlock;
    }
}
