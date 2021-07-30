// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Treasury.sol";

import "./interface/IMdexChef.sol";
import './interface/IStrategyLink.sol';
import './interface/ITenBankHall.sol';
import "./interface/IMdexFactory.sol";
import "./interface/IMdexPair.sol";
import "./interface/IWHT.sol";
import "./interface/IActionPools.sol";
import "./interface/IStrategyConfig.sol";

import "./library/TenMath.sol";
import "./library/TransferHelper.sol";
import "./library/MdxLib.sol";

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
        IStrategyLink strategyLink;
        uint sid;
        uint mdxPid;
        bool paused;
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
    address public profitAddress;
    address public factory;
    address public WHT;
    IMdexChef public mdxChef;
    ITenBankHall public tenBankHall;
    Treasury public emergency;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address token, address indexed user, uint amount, uint actAmt);

    constructor(
        IERC20 _hpt,
        uint256 _hptPerBlock,
        uint256 _startBlock,
        uint256 _miningProfitRate,
        IERC20 _mining,
        address _profitAddress,
        address _mdxFactory,
        address _WHT,
        IMdexChef _mdxChef,
        ITenBankHall _tenBankHall
    ) public {
        hpt = _hpt;
        hptPerBlock = _hptPerBlock;
        startBlock = _startBlock;
        miningProfitRate = _miningProfitRate;
        mining = _mining;
        profitAddress = _profitAddress;
        factory = _mdxFactory;
        WHT = _WHT;
        mdxChef = _mdxChef;
        tenBankHall = _tenBankHall;
    }

    function getRewardToken() external view returns(address) {
        return address(mining);
    }

    function setEmergencyAddress(Treasury _emergency) public onlyOwner {
        if (address(emergency) == address(0)) {
            emergency = _emergency;
        }
    }

    function setProfitAddress(address _profitAddress) public onlyOwner {
        profitAddress = _profitAddress;
    }

    function getPoolData(uint _pid) public view returns(uint mdxPerBlock, uint mdxPoolTotalAmount, uint depositFee, uint withdrawFee, uint refundFee) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 mdxTotalAllocPoint = mdxChef.totalAllocPoint();
        IMdexChef.MdxPoolInfo memory mdxPoolInfo = mdxChef.poolInfo(pool.mdxPid);
        IStrategyConfig config = IStrategyConfig(pool.strategyLink.sconfig());

        mdxPerBlock = mdxChef.reward(block.number).mul(mdxPoolInfo.allocPoint).div(mdxTotalAllocPoint);

        mdxPoolTotalAmount = mdxPoolInfo.totalAmount;
        (,depositFee) = config.getDepositFee(address(pool.strategyLink), pool.miningChefPid);
        (,withdrawFee) = config.getWithdrawFee(address(pool.strategyLink), pool.miningChefPid);
        (,refundFee) = config.getRefundFee(address(pool.strategyLink), pool.miningChefPid);
    }

    function setHptPerBlock(uint _hptPerBlock) public onlyOwner {
        massUpdatePools();
        hptPerBlock = _hptPerBlock;
    }

    function miningRewardPerBlock(uint256 _pid) external view returns(uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        IActionPools acPool = IActionPools(pool.strategyLink.compActionPool());
        uint[] memory ids = getPoolClaimIds(_pid);
        uint rewardPerBlock = 0;
        for(uint i = 0; i< ids.length; i++) {
            (,, address rewardToken, uint _rewardPerBlock,,,,,,) = acPool.poolInfo(ids[i]);
            if (rewardToken == address(mining)) {
                rewardPerBlock += _rewardPerBlock;
            }
        }

        (,,,, uint256 totalLPAmount,) = pool.strategyLink.getPoolInfo(pool.miningChefPid);
        uint baseVal = 1e18;
        return rewardPerBlock.mul(baseVal.sub(miningProfitRate)).mul(pool.lpBalance).div(totalLPAmount).div(baseVal);
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
            IERC20(erc20).safeTransfer(msg.sender, eb);
        }

        uint cb = address(this).balance;
        if (cb > 0) {
            msg.sender.transfer(cb);
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        uint _sid
    ) public onlyOwner {
        massUpdatePools();
        uint256 lastRewardBlock =
        block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        (,address iLink, uint256 pid) = tenBankHall.strategyInfo(_sid);
        (, , address lpToken, uint256 poolId,,) = IStrategyLink(iLink).getPoolInfo(pid);

        poolInfo.push(
            PoolInfo({
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
            mdxPid: poolId,
            paused: false
            })
        );
    }

    // Update the given pool's reward allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint _sid
    ) public onlyOwner {
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );

        poolInfo[_pid].allocPoint = _allocPoint;

        (,address iLink, uint256 pid) = tenBankHall.strategyInfo(_sid);
        (, , address lpToken, uint256 poolId,,) = IStrategyLink(iLink).getPoolInfo(pid);

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

    function userTotalHptReward(uint pid, address user) public view returns(uint) {
        return userInfo[pid][user].hptRewarded + pendingHpt(pid, user);
    }

    function userTotalMiningReward(uint pid, address user) public view returns(uint) {
        return userInfo[pid][user].miningRewarded + pendingMining(pid, user);
    }

    function pending0(uint256 _pid, address _user)
    public
    view
    returns (uint256) {
        return pendingHpt(_pid, _user);
    }

    function pending1(uint256 _pid, address _user)
    public
    view
    returns (uint256) {
        return pendingMining(_pid, _user);
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
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);
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
            uint[] memory ids = getPoolClaimIds(_pid);
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
            PoolInfo storage pool = poolInfo[pid];
            if (!pool.paused) {
                updatePool(pid);
            }
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(!pool.paused, 'not paused');
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpBalance;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number.sub(pool.lastRewardBlock);
        uint256 hptReward =
        multiplier.mul(hptPerBlock).mul(pool.allocPoint).div(
            totalAllocPoint
        );
        hptRewardBalance = hptRewardBalance.add(hptReward);
        hptRewardTotal = hptRewardTotal.add(hptReward);
        pool.accHptPerShare = pool.accHptPerShare.add(
            hptReward.mul(1e12).div(lpSupply)
        );

        pool.strategyLink.updatePool(pool.miningChefPid, 0, 0);

        //claim mining reward
        uint256 miningBalancePrior = mining.balanceOf(address(this));
        IActionPools acPool = IActionPools(pool.strategyLink.compActionPool());
        acPool.claimIds(getPoolClaimIds(_pid));
        uint256 miningBalanceNew = mining.balanceOf(address(this));
        if (miningBalanceNew > miningBalancePrior) {
            uint256 delta = miningBalanceNew.sub(miningBalancePrior);
            //keep profit to owner by miningProfitRate
            uint256 miningProfit = delta.mul(miningProfitRate).div(1e18);
            mining.safeTransfer(profitAddress, miningProfit);

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
        address pair = IMdexFactory(factory).pairFor(tokenA, tokenB);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        if (amountADesired != 0) {
            (, , _amount) = MdxLib.addLiquidity(factory, tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin, address(this));
        }
        deposit(_pid, _amount);
    }

    function depositETH(uint256 _pid,
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin) public payable {
        uint _amount;
        address pair = IMdexFactory(factory).pairFor(token, WHT);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        if (amountTokenDesired != 0) {
            (, , _amount) = MdxLib.addLiquidityETH(WHT, factory, token, amountTokenDesired, amountTokenMin, amountETHMin, address(this));
        }
        deposit(_pid, _amount);
    }

    function withdrawTokens(uint256 _pid,
        address tokenA,
        address tokenB,
        uint rate,
        uint amountAMin,
        uint amountBMin) public {
        address pair = IMdexFactory(factory).pairFor(tokenA, tokenB);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        withdraw(_pid, rate);
        uint liquidity = pool.lpToken.balanceOf(address(this));
        if (liquidity != 0) {
            MdxLib.removeLiquidity(factory, tokenA, tokenB, liquidity, amountAMin, amountBMin, msg.sender);
        }
    }

    function withdrawETH(uint256 _pid,
        address token,
        uint rate,
        uint amountTokenMin,
        uint amountETHMin) public {
        address pair = IMdexFactory(factory).pairFor(token, WHT);
        PoolInfo storage pool = poolInfo[_pid];
        require(pair == address(pool.lpToken), "wrong pid");
        withdraw(_pid, rate);
        uint liquidity = pool.lpToken.balanceOf(address(this));
        if (liquidity != 0) {
            uint amountToken;
            uint amountETH;
            (amountToken, amountETH) = MdxLib.removeLiquidity(factory, token, WHT, liquidity, amountTokenMin, amountETHMin, address(this));
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
            pool.lpToken.approve(address(tenBankHall), 0);
            pool.lpToken.approve(address(tenBankHall), _amount);

            IMdexPair lpToken = IMdexPair(address(pool.lpToken));
            IERC20 token0 = IERC20(lpToken.token0());
            IERC20 token1 = IERC20(lpToken.token1());

            uint token0Bal = token0.balanceOf(address(this));
            uint token1Bal = token1.balanceOf(address(this));
            _amount = tenBankHall.depositLPToken(pool.sid, _amount, 0, 0, 0, 0);
            remainTransfer(token0, token0Bal);
            remainTransfer(token1, token1Bal);
        }

        uint256 addPoint = _amount;
        if(pool.totalLPReinvest > 0) {
            addPoint = _amount.mul(pool.totalPoints).div(pool.totalLPReinvest);
        }

        pool.lpBalance = pool.lpBalance.add(_amount);
        pool.totalPoints = pool.totalPoints.add(addPoint);
        uint totalLPReinvest = pool.strategyLink.pendingLPAmount(pool.miningChefPid, address(this));
        pool.totalLPReinvest = totalLPReinvest >= pool.lpBalance ? totalLPReinvest:pool.lpBalance;

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
        uint withdrawRate = withdrawLPTokenAmount.mul(1e9).div(pool.totalLPReinvest);

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

        user.lpPoints = TenMath.safeSub(user.lpPoints, removedPoint);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accHptPerShare).div(1e12);
        user.miningRewardDebt = user.amount.mul(pool.accMiningPerShare).div(1e12);

        if (withdrawRate > 0) {
            tenBankHall.withdrawLPToken(pool.sid, withdrawRate, 0, 0);
        }

        uint totalLPReinvest = pool.strategyLink.pendingLPAmount(pool.miningChefPid, address(this));
        pool.totalLPReinvest = totalLPReinvest >= pool.lpBalance ? totalLPReinvest:pool.lpBalance;

        emit Withdraw(_user, _pid, _amount);
    }

    function pendingLPAmount(uint256 _pid, address _account) public view returns (uint256 value) {
        PoolInfo storage pool = poolInfo[_pid];
        if(pool.totalPoints <= 0) {
            return 0;
        }
        uint totalLPReinvest = pool.strategyLink.pendingLPAmount(pool.miningChefPid, address(this));
        totalLPReinvest = totalLPReinvest >= pool.lpBalance ? totalLPReinvest:pool.lpBalance;

        value = userInfo[_pid][_account].lpPoints.mul(totalLPReinvest).div(pool.totalPoints);
        value = TenMath.min(value, totalLPReinvest);
    }

    function remainTransfer(IERC20 token, uint beforeBal) internal {
        uint tokenBalNew = token.balanceOf(address(this));
        if (tokenBalNew > beforeBal) {
            token.safeTransfer(msg.sender, tokenBalNew - beforeBal);
        }
    }

    function safeHptTransfer(uint256 pid, address _to, uint256 _amount) internal {
        hptRewardBalance = hptRewardBalance.sub(_amount);
        userInfo[pid][_to].hptRewarded += _amount;
        uint256 hptBal = hpt.balanceOf(address(this));
        uint amtOld = _amount;
        if (_amount > hptBal) {
            _amount = hptBal;
        }
        if (_amount > 0) {
            hpt.safeTransfer(_to, _amount);
            emit Claim(address(hpt), _to, amtOld, _amount);
        }
    }

    function safeMiningTransfer(uint256 pid, address _to, uint256 _amount) internal {
        miningRewardBalance = miningRewardBalance.sub(_amount);
        userInfo[pid][_to].miningRewarded += _amount;
        uint256 miningBal = mining.balanceOf(address(this));
        uint amtOld = _amount;
        if (_amount > miningBal) {
            _amount = miningBal;
        }
        if (_amount > 0) {
            mining.safeTransfer(_to, _amount);
            emit Claim(address(mining), _to, amtOld, _amount);
        }
    }

    function emergencyWithdraw(uint _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        require(!pool.paused, 'not paused');
        pool.paused = true;

        IMdexPair lpToken = IMdexPair(address(pool.lpToken));
        IERC20 token0 = IERC20(lpToken.token0());
        IERC20 token1 = IERC20(lpToken.token1());

        uint token0Bal = token0.balanceOf(address(this));
        uint token1Bal = token1.balanceOf(address(this));

        tenBankHall.emergencyWithdraw(pool.sid, 0, 0);

        uint token0Amt = token0.balanceOf(address(this));
        uint token1Amt = token1.balanceOf(address(this));

        if (token0Amt > token0Bal) {
            token0.approve(address(emergency), token0Amt - token0Bal);
            emergency.deposit(_pid, address(token0), token0Amt - token0Bal);
        }
        if (token1Amt > token1Bal) {
            token1.approve(address(emergency), token1Amt - token1Bal);
            emergency.deposit(_pid, address(token1), token1Amt - token1Bal);
        }
    }

    function userEmergencyWithdraw(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.paused, 'only paused');
        UserInfo storage user = userInfo[_pid][msg.sender];
        IMdexPair lpToken = IMdexPair(address(pool.lpToken));
        IERC20 token0 = IERC20(lpToken.token0());
        IERC20 token1 = IERC20(lpToken.token1());

        _userEmergencyWithdraw(_pid, address(token0));
        _userEmergencyWithdraw(_pid, address(token1));

        pool.totalPoints = TenMath.safeSub(pool.totalPoints, user.lpPoints);
        user.lpPoints = 0;
    }

    function _userEmergencyWithdraw(uint _pid, address token) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint tokenTotal = emergency.userTokenAmt(_pid, token);
        uint userToken;

        if (pool.totalPoints > user.lpPoints) {
            userToken = user.lpPoints.mul(tokenTotal).div(pool.totalPoints);
        } else {
            userToken = tokenTotal;
        }
        emergency.withdraw(_pid, token, userToken, msg.sender);
    }


fallback() external {}
receive() payable external {}
}

