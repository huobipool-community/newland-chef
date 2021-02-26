// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IMdexFactory.sol";
import "./interface/IMdexPair.sol";
import "./interface/IWHT.sol";
import "./interface/IMdexChef.sol";
import "./library/TransferHelper.sol";

// MasterChef is the master of Hpt. He can make Hpt and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once HPT is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 mdxRewardDebt;
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. HPTs to distribute per block.
        uint256 lastRewardBlock; // Last block number that HPTs distribution occurs.
        uint256 accHptPerShare; // Accumulated HPTs per share, times 1e12. See below.
        uint256 mdxChefPid;
        uint256 lpBalance;
        uint256 accRewardBalance;
    }
    // The HPT TOKEN!
    IERC20 public hpt;
    // Block number when bonus HPT period ends.
    uint256 public bonusEndBlock;
    // HPT tokens created per block.
    uint256 public hptPerBlock;
    // Bonus muliplier for early hpt makers.
    uint256 public constant BONUS_MULTIPLIER = 10;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when HPT mining starts.
    uint256 public startBlock;
    uint256 public hptRewardBalance;
    address public factory;
    address public WHT;
    IMdexChef public mdxChef;
    uint256 public profitRate;
    IERC20 public mdx;
    uint256 one = 1e18;
    // temp var
    uint256 mdxTempBalance;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        IERC20 _hpt,
        uint256 _hptPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        address _mdxFactory,
        address _WHT,
        IMdexChef _mdxChef,
        uint256 _profitRate,
        IERC20 _mdx
    ) public {
        hpt = _hpt;
        hptPerBlock = _hptPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
        factory = _mdxFactory;
        WHT = _WHT;
        mdxChef = _mdxChef;
        profitRate = _profitRate;
        mdx = _mdx;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function revoke() public onlyOwner {
        hpt.transfer(msg.sender, hpt.balanceOf(address(this)));
        //mdx.transfer(msg.sender, mdx.balanceOf(address(this)));
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint _mdxChefPid,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
        block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accHptPerShare: 0,
            mdxChefPid: _mdxChefPid,
            lpBalance: 0,
            accRewardBalance: 0
            })
        );
    }

    // Update the given pool's HPT allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint _mdxChefPid,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].mdxChefPid = _mdxChefPid;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
    public
    view
    returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
            bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock)
            );
        }
    }

    // View function to see pending HPTs on frontend.
    function pendingHpt(uint256 _pid, address _user)
    external
    view
    returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accHptPerShare = pool.accHptPerShare;
        uint256 lpSupply = pool.lpBalance;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
            getMultiplier(pool.lastRewardBlock, block.number);
            uint256 hptReward =
            multiplier.mul(hptPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
            accHptPerShare = accHptPerShare.add(
                hptReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accHptPerShare).div(1e12).sub(user.rewardDebt);
    }

    // View function to see pending HPTs on frontend.
    function pendingMdx(uint256 _pid, address _user)
    external
    view
    returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 mdxPendingBalance;
        (mdxPendingBalance,) = mdxChef.pending(pool.mdxChefPid, address(this));
        uint totalBalance = pool.accRewardBalance.add(mdxPendingBalance);
        return user.amount.mul(totalBalance).div(pool.lpBalance).sub(
            user.mdxRewardDebt
        );
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpBalance;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 hptReward =
        multiplier.mul(hptPerBlock).mul(pool.allocPoint).div(
            totalAllocPoint
        );
        hptRewardBalance = hptRewardBalance.add(hptReward);
        pool.accHptPerShare = pool.accHptPerShare.add(
            hptReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    function depositTokens(uint256 _pid,
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin) public {
        uint _amount;
        address pair = pairFor(tokenA, tokenB);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        mdxTempBalance = mdx.balanceOf(address(this));
        if (amountADesired == 0) {
            (, , _amount) = addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, address(this));
            mdxChef.deposit(pool.mdxChefPid, _amount);
        }
        deposit(_pid, _amount);
    }

    function depositETH(uint256 _pid,
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin) public {
        uint _amount;
        address pair = pairFor(token, WHT);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        mdxTempBalance = mdx.balanceOf(address(this));
        if (amountTokenDesired != 0) {
            (, , _amount) = addLiquidityETH(token, amountTokenDesired, amountTokenMin, amountETHMin, address(this));
            mdxChef.deposit(pool.mdxChefPid, _amount);
        }
        deposit(_pid, _amount);
    }

    // Deposit LP tokens to MasterChef for HPT allocation.
    function deposit(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            // reward hpt
            uint256 pending =
            user.amount.mul(pool.accHptPerShare).div(1e12).sub(
                user.rewardDebt
            );
            safeHptTransfer(msg.sender, pending);

            // reward mdx
            mdxChef.withdraw(pool.mdxChefPid, 0);
            rewardMdx(pool);

            uint256 mdxPending =
            user.amount.mul(pool.accRewardBalance).div(pool.lpBalance).sub(
                user.mdxRewardDebt
            );
            mdx.safeTransfer(msg.sender, mdxPending);
        }
        pool.lpBalance = pool.lpBalance.add(_amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accHptPerShare).div(1e12);
        user.mdxRewardDebt = user.amount.mul(pool.accRewardBalance).div(pool.lpBalance);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdrawTokens(uint256 _pid,
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin) public {
        address pair = pairFor(tokenA, tokenB);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        mdxTempBalance = mdx.balanceOf(address(this));
        withdraw(_pid, liquidity);
        if (liquidity != 0) {
            mdxChef.withdraw(pool.mdxChefPid, liquidity);
            removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, msg.sender);
        }
    }

    function withdrawETH(uint256 _pid,
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin) public {
        address pair = pairFor(token, WHT);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        mdxTempBalance = mdx.balanceOf(address(this));
        withdraw(_pid, liquidity);
        if (liquidity != 0) {
            mdxChef.withdraw(pool.mdxChefPid, liquidity);
            removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, msg.sender);
        }
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);

        // reward hpt
        uint256 pending =
        user.amount.mul(pool.accHptPerShare).div(1e12).sub(
            user.rewardDebt
        );
        safeHptTransfer(msg.sender, pending);

        // reward mdx
        mdxChef.withdraw(pool.mdxChefPid, 0);
        rewardMdx(pool);

        uint256 mdxPending =
        user.amount.mul(pool.accRewardBalance).div(pool.lpBalance).sub(
            user.mdxRewardDebt
        );
        mdx.safeTransfer(msg.sender, mdxPending);

        pool.lpBalance = pool.lpBalance.sub(_amount);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accHptPerShare).div(1e12);
        user.mdxRewardDebt = user.amount.mul(pool.accRewardBalance).div(pool.lpBalance);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdrawTokens(uint256 _pid,
        address tokenA,
        address tokenB,
        uint amountAMin,
        uint amountBMin) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        mdxTempBalance = mdx.balanceOf(address(this));
        mdxChef.withdraw(pool.mdxChefPid, user.amount);
        rewardMdx(pool);

        removeLiquidity(tokenA, tokenB, user.amount, amountAMin, amountBMin, msg.sender);

        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.mdxRewardDebt = 0;
    }

    function emergencyWithdrawETH(uint256 _pid,
        address token,
        uint amountTokenMin,
        uint amountETHMin) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        mdxTempBalance = mdx.balanceOf(address(this));
        mdxChef.withdraw(pool.mdxChefPid, user.amount);
        rewardMdx(pool);

        removeLiquidityETH(token, user.amount, amountTokenMin, amountETHMin, msg.sender);

        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.mdxRewardDebt = 0;
    }

    function rewardMdx(PoolInfo memory pool) internal {
        uint256 mdxBalance = mdx.balanceOf(address(this));
        if (mdxBalance > mdxTempBalance) {
            uint256 delt = mdxBalance.sub(mdxTempBalance);
            uint256 mdxProfit = delt.mul(profitRate).div(one);
            uint256 mdxReward = delt.mul(one.sub(profitRate)).div(one);
            pool.accRewardBalance = mdxTempBalance.add(mdxReward);
            mdx.transfer(owner(),mdxProfit);
        }
    }

    function safeHptTransfer(address _to, uint256 _amount) internal {
        hptRewardBalance = hptRewardBalance.sub(_amount);
        hpt.transfer(_to, _amount);
    }

    function pairFor(address tokenA, address tokenB) internal view returns (address pair){
        pair = IMdexFactory(factory).pairFor(tokenA, tokenB);
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IMdexFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IMdexFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = IMdexFactory(factory).getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = IMdexFactory(factory).quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'MdexRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = IMdexFactory(factory).quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'MdexRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to
    ) internal returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = pairFor(tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IMdexPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to
    ) internal returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WHT,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = pairFor(token, WHT);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWHT(WHT).deposit{value : amountETH}();
        assert(IWHT(WHT).transfer(pair, amountETH));
        liquidity = IMdexPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to
    ) internal returns (uint amountA, uint amountB) {
        address pair = pairFor(tokenA, tokenB);
        IMdexPair(pair).transferFrom(msg.sender, pair, liquidity);
        // send liquidity to pair
        (uint amount0, uint amount1) = IMdexPair(pair).burn(to);
        (address token0,) = IMdexFactory(factory).sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'MdexRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'MdexRouter: INSUFFICIENT_B_AMOUNT');
    }

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to
    ) internal returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WHT,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this)
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWHT(WHT).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    fallback() external {}
    receive() payable external {}
}
