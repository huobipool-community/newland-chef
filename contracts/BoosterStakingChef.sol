// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interface/IMdexChef.sol";
import './interface/IStrategyLink.sol';
import './interface/ITenBankHall.sol';
import "./interface/IMdexFactory.sol";
import "./interface/IMdexPair.sol";
import "./interface/IWHT.sol";
import "./interface/IActionPools.sol";

import "./library/TenMath.sol";
import "./library/TransferHelper.sol";

contract BoosterStakingChef is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 miningRewardDebt;
        uint256 hptRewarded;  //accumlated total
        uint256 miningRewarded;  //accumlated total
        uint256 lpPoints;       // deposit proportion
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;    //Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. HPTs to distribute per block.
        uint256 lastRewardBlock; // Last block number that HPTs distribution occurs.
        uint256 accHptPerShare; // Accumulated HPTs per share, times 1e12. See below.
        uint256 miningChefPid;
        uint256 lpBalance;
        uint256 accMiningPerShare;
        uint256 totalLPReinvest;        // total of lptoken amount with totalLPAmount and reinvest rewards，
        uint256 totalPoints;
        ITenBankHall tenBankHall;
        IStrategyLink strategyLink;
        uint sid;
        uint mdxPid;
    }

    // The HPT TOKEN!
    IERC20 public hpt;
    // HPT tokens created per block.
    uint256 public hptPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when reward mining starts.
    uint256 public startBlock;
    uint256 public hptRewardBalance;
    uint256 public miningRewardBalance;
    uint256 public hptRewardTotal;
    uint256 public miningRewardTotal;
    uint256 public miningProfitRate;
    // The reward token
    IERC20 public mining;
    address public treasuryAddress;
    address public factory;
    address public WHT;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address token, address indexed user, address to, uint amount);

    constructor(
        IERC20 _hpt,
        uint256 _hptPerBlock,
        uint256 _startBlock,
        uint256 _miningProfitRate,
        IERC20 _mining,
        address _treasuryAddress,
        address _mdxFactory,
        address _WHT
    ) public {
        hpt = _hpt;
        hptPerBlock = _hptPerBlock;
        startBlock = _startBlock;
        miningProfitRate = _miningProfitRate;
        mining = _mining;
        treasuryAddress = _treasuryAddress;
        factory = _mdxFactory;
        WHT = _WHT;
    }

    function getRewardToken() external view returns(address) {
        return address(mining);
    }

    function setTreasuryAddress(address _treasuryAddress) public onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    function setHptPerBlock(uint _hptPerBlock) public onlyOwner {
        massUpdatePools();
        hptPerBlock = _hptPerBlock;
    }

    function miningRewardPerBlock(uint256 _pid) external view returns(uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        IActionPools acPool = IActionPools(pool.strategyLink.compActionPool());
        uint[] memory ids = getPoolClaimIds(pool.miningChefPid);
        uint rewardPerBlock = 0;
        for(uint i = 0; i< ids.length; i++) {
            (,, address rewardToken, uint _rewardPerBlock,,,,,,) = acPool.poolInfo(ids[i]);
            if (rewardToken == address(mining)) {
                rewardPerBlock += _rewardPerBlock;
            }
        }

        (,,,, uint256 totalLPAmount,) = pool.strategyLink.getPoolInfo(pool.miningChefPid);
        rewardPerBlock = rewardPerBlock.mul(pool.lpBalance).div(totalLPAmount);
        uint baseVal = 1e18;
        rewardPerBlock = rewardPerBlock.mul(baseVal.sub(miningProfitRate)).div(baseVal);
        return rewardPerBlock;
    }

    function hptRewardPerBlock(uint _pid) external view returns(uint)  {
        PoolInfo storage pool = poolInfo[_pid];
        return hptPerBlock.mul(pool.allocPoint).div(totalAllocPoint);
    }

    function setMiningProfitRate(uint _miningProfitRate) public onlyOwner {
        massUpdatePools();
        miningProfitRate = _miningProfitRate;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function revoke(address erc20) public onlyOwner {
        require(erc20 != address(mining), 'not mining token');
        uint eb = IERC20(erc20).balanceOf(address(this));
        if (eb > 0) {
            IERC20(erc20).transfer(msg.sender, eb);
        }

        uint cb = address(this).balance;
        if (cb > 0) {
            msg.sender.transfer(cb);
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        ITenBankHall _tenBankHall,
        uint _sid
    ) public onlyOwner {
        massUpdatePools();
        uint256 lastRewardBlock =
        block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        (,address iLink, uint256 pid) = _tenBankHall.strategyInfo(_sid);
        (, , address lpToken, uint256 poolId,,) = IStrategyLink(iLink).getPoolInfo(pid);

        poolInfo.push(
            PoolInfo({
            tenBankHall: _tenBankHall,
            sid: _sid,
            strategyLink: IStrategyLink(iLink),
            miningChefPid: pid,
            lpToken: IERC20(lpToken),
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accHptPerShare: 0,
            lpBalance: 0,
            accMiningPerShare: 0,
            totalPoints: 0,
            totalLPReinvest: 0,
            mdxPid: poolId
            })
        );
    }

    // Update the given pool's reward allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        ITenBankHall _tenBankHall,
        uint _sid
    ) public onlyOwner {
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );

        poolInfo[_pid].allocPoint = _allocPoint;

        (,address iLink, uint256 pid) = _tenBankHall.strategyInfo(_sid);
        (, , address lpToken, uint256 poolId,,) = IStrategyLink(iLink).getPoolInfo(pid);

        poolInfo[_pid].tenBankHall = _tenBankHall;
        poolInfo[_pid].sid = _sid;
        poolInfo[_pid].strategyLink = IStrategyLink(iLink);
        poolInfo[_pid].miningChefPid = pid;
        poolInfo[_pid].lpToken = IERC20(lpToken);
        poolInfo[_pid].mdxPid = poolId;
    }

    // get booster actionPool ids
    function getPoolClaimIds(uint pid) internal view returns(uint[] memory) {
        PoolInfo storage pool = poolInfo[pid];
        IActionPools acPool = IActionPools(pool.strategyLink.compActionPool());

        return acPool.getPoolIndex(address(pool.strategyLink), pool.miningChefPid);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
    internal
    pure
    returns (uint256)
    {
        return _to.sub(_from);
    }

    function userTotalHptReward(uint pid, address user) public view returns(uint) {
        return userInfo[pid][user].hptRewarded + pendingHpt(pid, user);
    }

    function userTotalMiningReward(uint pid, address user) public view returns(uint) {
        return userInfo[pid][user].miningRewarded + pendingMining(pid, user);
    }

    function pendingHpt(uint256 _pid, address _user)
    public
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

    // View function to see pending reward on frontend.
    function pendingMining(uint256 _pid, address _user)
    public
    view
    returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMiningPerShare = pool.accMiningPerShare;
        uint256 lpSupply = pool.lpBalance;
        if (lpSupply != 0) {
            uint256 miningReward;
            IActionPools acPool = IActionPools(pool.strategyLink.compActionPool());
            uint[] memory ids = getPoolClaimIds(pool.miningChefPid);
            for(uint i = 0; i< ids.length; i++) {
                (,, address rewardToken) = acPool.getPoolInfo(ids[i]);
                if (rewardToken == address(mining)) {
                    miningReward += acPool.pendingRewards(ids[i], address(this));
                }
            }

            uint256 miningProfit = miningReward.mul(miningProfitRate).div(1e18);
            miningReward = miningReward.sub(miningProfit);
            accMiningPerShare = accMiningPerShare.add(
                miningReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accMiningPerShare).div(1e12).sub(user.miningRewardDebt);
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
        hptRewardTotal = hptRewardTotal.add(hptReward);
        pool.accHptPerShare = pool.accHptPerShare.add(
            hptReward.mul(1e12).div(lpSupply)
        );

        //claim mining reward
        uint256 miningBalancePrior = mining.balanceOf(address(this));
        IActionPools acPool = IActionPools(pool.strategyLink.compActionPool());
        acPool.claimIds(getPoolClaimIds(_pid));
        uint256 miningBalanceNew = mining.balanceOf(address(this));
        if (miningBalanceNew > miningBalancePrior) {
            uint256 delta = miningBalanceNew.sub(miningBalancePrior);
            //keep profit to owner by miningProfitRate
            uint256 miningProfit = delta.mul(miningProfitRate).div(1e18);
            mining.transfer(treasuryAddress, miningProfit);

            uint256 miningReward = delta.sub(miningProfit);
            miningRewardBalance = miningRewardBalance.add(miningReward);
            miningRewardTotal = miningRewardTotal.add(miningReward);
            pool.accMiningPerShare = pool.accMiningPerShare.add(
                miningReward.mul(1e12).div(lpSupply)
            );
        }

        pool.lastRewardBlock = block.number;
        uint totalLPReinvest = pool.strategyLink.pendingLPAmount(pool.miningChefPid, address(this));
        pool.totalLPReinvest = totalLPReinvest >= pool.lpBalance ? totalLPReinvest:pool.lpBalance;
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
        if (amountADesired != 0) {
            (, , _amount) = addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, address(this));
        }
        deposit(_pid, _amount);
    }

    function depositETH(uint256 _pid,
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin) public payable {
        uint _amount;
        address pair = pairFor(token, WHT);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        if (amountTokenDesired != 0) {
            (, , _amount) = addLiquidityETH(token, amountTokenDesired, amountTokenMin, amountETHMin, address(this));
        }
        deposit(_pid, _amount);
    }

    function withdrawTokens(uint256 _pid,
        address tokenA,
        address tokenB,
        uint rate,
        uint amountAMin,
        uint amountBMin) public {
        address pair = pairFor(tokenA, tokenB);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        withdraw(_pid, rate);
        uint liquidity = pool.lpToken.balanceOf(address(this));
        if (liquidity != 0) {
            removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, msg.sender);
        }
    }

    function withdrawETH(uint256 _pid,
        address token,
        uint rate,
        uint amountTokenMin,
        uint amountETHMin) public {
        address pair = pairFor(token, WHT);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        withdraw(_pid, rate);
        uint liquidity = pool.lpToken.balanceOf(address(this));
        if (liquidity != 0) {
            uint amountToken;
            uint amountETH;
            (amountToken, amountETH) = removeLiquidity(token, WHT, liquidity, amountTokenMin, amountETHMin, address(this));
            TransferHelper.safeTransfer(token, msg.sender, amountToken);
            IWHT(WHT).withdraw(amountETH);
            TransferHelper.safeTransferETH(msg.sender, amountETH);
        }
    }

    function deposit(uint256 _pid, uint256 _amount) internal {
        address _user = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        updatePool(_pid);

        UserInfo storage user = userInfo[_pid][_user];
        if (user.amount > 0) {
            // reward hpt
            uint256 hptPending =
            user.amount.mul(pool.accHptPerShare).div(1e12).sub(
                user.rewardDebt
            );
            safeHptTransfer(_pid, _user, hptPending);

            // reward mining
            uint256 miningPending =
            user.amount.mul(pool.accMiningPerShare).div(1e12).sub(
                user.miningRewardDebt
            );
            safeMiningTransfer(_pid, _user, miningPending);
        }

        if (_amount > 0) {
            pool.lpToken.approve(address(pool.tenBankHall), 0);
            pool.lpToken.approve(address(pool.tenBankHall), _amount);
            pool.tenBankHall.depositLPToken(pool.sid, _amount, 0, 0, 0, 0);
        }

        uint256 addPoint = _amount;
        if(pool.totalLPReinvest > 0) {
            addPoint = _amount.mul(pool.totalPoints).div(pool.totalLPReinvest);
        }

        pool.lpBalance = pool.lpBalance.add(_amount);
        pool.totalPoints = pool.totalPoints.add(addPoint);
        pool.totalLPReinvest = pool.totalLPReinvest.add(_amount);

        user.lpPoints = user.lpPoints.add(addPoint);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accHptPerShare).div(1e12);
        user.miningRewardDebt = user.amount.mul(pool.accMiningPerShare).div(1e12);
        emit Deposit(_user, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 rate) internal {
        address _user = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);

        rate = rate > 1e9 ? 1e9:rate;
        uint256 removedPoint = user.lpPoints.mul(rate).div(1e9);
        uint256 withdrawLPTokenAmount = removedPoint.mul(pool.totalLPReinvest).div(pool.totalPoints);
        withdrawLPTokenAmount = TenMath.min(withdrawLPTokenAmount, pool.totalLPReinvest);
        uint256 _amount = rate >= 1e9 ? user.amount : user.amount.mul(rate).div(1e9);
        uint withdrawRate = withdrawLPTokenAmount.div(pool.totalLPReinvest).mul(1e9);

        {
            // reward hpt
            uint256 pending =
            user.amount.mul(pool.accHptPerShare).div(1e12).sub(
                user.rewardDebt
            );
            safeHptTransfer(_pid, _user, pending);

            // reward mining
            uint256 miningPending =
            user.amount.mul(pool.accMiningPerShare).div(1e12).sub(
                user.miningRewardDebt
            );
            safeMiningTransfer(_pid, _user, miningPending);
        }

        pool.lpBalance = pool.lpBalance.sub(_amount);
        pool.totalPoints = TenMath.safeSub(pool.totalPoints, removedPoint);
        pool.totalLPReinvest = TenMath.safeSub(pool.totalLPReinvest, withdrawLPTokenAmount);

        user.lpPoints = TenMath.safeSub(user.lpPoints, removedPoint);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accHptPerShare).div(1e12);
        user.miningRewardDebt = user.amount.mul(pool.accMiningPerShare).div(1e12);

        if (withdrawRate > 0) {
            pool.tenBankHall.withdrawLPToken(pool.sid, withdrawRate, 0, 0);
        }

        emit Withdraw(_user, _pid, _amount);
    }

    function pendingLPAmount(uint256 _pid, address _account) public view returns (uint256 value) {
        PoolInfo storage pool = poolInfo[_pid];
        if(pool.totalPoints <= 0) {
            return 0;
        }
        value = userInfo[_pid][_account].lpPoints.mul(pool.totalLPReinvest).div(pool.totalPoints);
        value = TenMath.min(value, pool.totalLPReinvest);
    }

    function safeHptTransfer(uint256 pid, address _to, uint256 _amount) internal {
        hptRewardBalance = hptRewardBalance.sub(_amount);
        userInfo[pid][_to].hptRewarded += _amount;
        uint256 hptBal = hpt.balanceOf(address(this));
        if (_amount > hptBal) {
            _amount = hptBal;
        }
        if (_amount > 0) {
            hpt.transfer(_to, _amount);
        }
    }

    function safeMiningTransfer(uint256 pid, address _to, uint256 _amount) internal {
        miningRewardBalance = miningRewardBalance.sub(_amount);
        userInfo[pid][_to].miningRewarded += _amount;
        uint256 miningBal = mining.balanceOf(address(this));
        if (_amount > miningBal) {
            _amount = miningBal;
        }
        if (_amount > 0) {
            mining.transfer(_to, _amount);
        }
    }


    // ************
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
    ) internal view returns (uint amountA, uint amountB) {
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
        IMdexPair(pair).transfer(pair, liquidity);
        // send liquidity to pair
        (uint amount0, uint amount1) = IMdexPair(pair).burn(to);
        (address token0,) = IMdexFactory(factory).sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'MdexRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'MdexRouter: INSUFFICIENT_B_AMOUNT');
    }

fallback() external {}
receive() payable external {}
}

