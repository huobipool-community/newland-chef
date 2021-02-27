// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMdexChef {
    // Info of each pool.
    struct MdxPoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. MDXs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that MDXs distribution occurs.
        uint256 accMdxPerShare; // Accumulated MDXs per share, times 1e12.
        uint256 accMultLpPerShare; //Accumulated multLp per share
        uint256 totalAmount;    // Total amount of current pool deposit.
    }

    function pending(uint256 _pid, address _user) external view returns (uint256, uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function mdxPerBlock() external view returns(uint256);
    function poolInfo(uint256 i) external view returns(MdxPoolInfo memory);
    function totalAllocPoint() external view returns(uint256);
}