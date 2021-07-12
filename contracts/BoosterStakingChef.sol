// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IMdexChef.sol";
import "./library/TransferHelper.sol";
import "./interface/IStakingRewards.sol";
import "./Treasury.sol";
import "./AccessSetting.sol";

contract MdexStakingChef is AccessSetting, IStakingRewards {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 mdxRewardDebt;
        uint256 hptRewarded;  //accumlated total
        uint256 mdxRewarded;  //accumlated total
        address goblin;
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. HPTs to distribute per block.
        uint256 lastRewardBlock; // Last block number that HPTs distribution occurs.
        uint256 accHptPerShare; // Accumulated HPTs per share, times 1e12. See below.
        uint256 mdxChefPid;
        uint256 lpBalance;
        uint256 accMdxPerShare;
        Treasury treasury;
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
    // The block number when HPT mining starts.
    uint256 public startBlock;
    uint256 public hptRewardBalance;
    uint256 public mdxRewardBalance;
    uint256 public hptRewardTotal;
    uint256 public mdxRewardTotal;
    IMdexChef public mdxChef;
    uint256 public mdxProfitRate;
    IERC20 public mdx;
    uint256 one = 1e18;
    address public treasuryAddress;

    mapping(address => uint) poolLenMap;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address token, address indexed user, address to, uint amount);

    constructor(
        IERC20 _hpt,
        uint256 _hptPerBlock,
        uint256 _startBlock,
        IMdexChef _mdxChef,
        uint256 _mdxProfitRate,
        IERC20 _mdx,
        address _treasuryAddress
    ) public {
        hpt = _hpt;
        hptPerBlock = _hptPerBlock;
        startBlock = _startBlock;
        mdxChef = _mdxChef;
        mdxProfitRate = _mdxProfitRate;
        mdx = _mdx;
        treasuryAddress = _treasuryAddress;
    }

    function getRewardToken() external view override returns(address) {
        return address(mdx);
    }

    function getPid(address lpToken) public view override returns(uint) {
        if (poolLenMap[lpToken] > 0) {
            return poolLenMap[lpToken] - 1;
        }
        return uint(-1);
    }

    function setTreasuryAddress(address _treasuryAddress) public onlyOwner {
        treasuryAddress = _treasuryAddress;
    }

    function setHptPerBlock(uint _hptPerBlock) public onlyOwner {
        massUpdatePools();
        hptPerBlock = _hptPerBlock;
    }

    function mdxRewardPerBlock(uint256 _pid) external view returns(uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 mdxTotalAllocPoint = mdxChef.totalAllocPoint();
        IMdexChef.MdxPoolInfo memory mdxPoolInfo = mdxChef.poolInfo(pool.mdxChefPid);

        uint256 mdxPerBlock = mdxChef.reward(block.number).mul(mdxPoolInfo.allocPoint).div(mdxTotalAllocPoint);
        mdxPerBlock = mdxPerBlock.mul(pool.lpBalance).div(mdxPoolInfo.totalAmount);
        mdxPerBlock = mdxPerBlock.mul(one.sub(mdxProfitRate)).div(one);
        return mdxPerBlock;
    }

    function hptRewardPerBlock(uint _pid) external view returns(uint)  {
        PoolInfo storage pool = poolInfo[_pid];
        return hptPerBlock.mul(pool.allocPoint).div(totalAllocPoint);
    }

    function setMdxProfitRate(uint _mdxProfitRate) public onlyOwner {
        massUpdatePools();
        mdxProfitRate = _mdxProfitRate;
    }

    function poolLength() external view override returns (uint256) {
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
        uint _mdxChefPid
    ) public onlyOwner {
        require(poolLenMap[address(_lpToken)] == 0, 'lp pool already exist');
        massUpdatePools();
        uint256 lastRewardBlock =
        block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        Treasury treasury= new Treasury();
        mdx.approve(address(treasury), uint256(-1));
        hpt.approve(address(treasury), uint256(-1));

        poolInfo.push(
            PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accHptPerShare: 0,
            mdxChefPid: _mdxChefPid,
            lpBalance: 0,
            accMdxPerShare: 0,
            treasury: treasury
            })
        );
        poolLenMap[address(_lpToken)] = poolInfo.length;
    }

    // Update the given pool's HPT allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint _mdxChefPid
    ) public onlyOwner {
        require(address(poolInfo[_pid].lpToken) != address(0), 'pid not exist');
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].mdxChefPid = _mdxChefPid;
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
        return userInfo[pid][user].hptRewarded + _pendingHpt(pid, user);
    }

    function userTotalMdxReward(uint pid, address user) public view returns(uint) {
        return userInfo[pid][user].mdxRewarded + _pendingMdx(pid, user);
    }

    // View function to see pending HPTs on frontend.
    function pendingHpt(uint256 _pid, address _user)
    external
    view
    returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        return _pendingHpt(_pid, _user) + pool.treasury.userTokenAmt(_user, address(hpt));
    }

    function _pendingHpt(uint256 _pid, address _user)
    internal
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
        return _pendingMdx(_pid, _user) + pool.treasury.userTokenAmt(_user, address(mdx));
    }

    // View function to see pending HPTs on frontend.
    function _pendingMdx(uint256 _pid, address _user)
    internal
    view
    returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMdxPerShare = pool.accMdxPerShare;
        uint256 lpSupply = pool.lpBalance;
        if (lpSupply != 0) {
            uint256 mdxReward;
            (mdxReward,) = mdxChef.pending(pool.mdxChefPid, address(this));
            uint256 mdxProfit = mdxReward.mul(mdxProfitRate).div(one);
            mdxReward = mdxReward.sub(mdxProfit);
            accMdxPerShare = accMdxPerShare.add(
                mdxReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accMdxPerShare).div(1e12).sub(user.mdxRewardDebt);
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

        //claim mdex reward
        uint256 mdxBalancePrior = mdx.balanceOf(address(this));
        mdxChef.withdraw(pool.mdxChefPid, 0);
        uint256 mdxBalanceNew = mdx.balanceOf(address(this));
        if (mdxBalanceNew > mdxBalancePrior) {
            uint256 delta = mdxBalanceNew.sub(mdxBalancePrior);
            //keep profit to owner by mdxProfitRate
            uint256 mdxProfit = delta.mul(mdxProfitRate).div(one);
            mdx.transfer(treasuryAddress, mdxProfit);

            uint256 mdxReward = delta.sub(mdxProfit);
            mdxRewardBalance = mdxRewardBalance.add(mdxReward);
            mdxRewardTotal = mdxRewardTotal.add(mdxReward);
            pool.accMdxPerShare = pool.accMdxPerShare.add(
                mdxReward.mul(1e12).div(lpSupply)
            );
        }

        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for HPT allocation.
    function deposit(uint256 _pid, uint256 _amount, address _user) public override onlyOps {
        PoolInfo storage pool = poolInfo[_pid];
        updatePool(_pid);

        UserInfo storage user = userInfo[_pid][_user];
        if (user.goblin != address(0)) {
            require(msg.sender == user.goblin, 'only goblin');
        } else {
            user.goblin = msg.sender;
        }
        if (user.amount > 0) {
            // reward hpt
            uint256 hptPending =
            user.amount.mul(pool.accHptPerShare).div(1e12).sub(
                user.rewardDebt
            );
            safeHptTransfer(_pid, pool, _user, hptPending);

            // reward mdx
            uint256 mdxPending =
            user.amount.mul(pool.accMdxPerShare).div(1e12).sub(
                user.mdxRewardDebt
            );
            safeMdxTransfer(_pid, pool, _user, mdxPending);
        }

        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            pool.lpToken.approve(address(mdxChef), 0);
            pool.lpToken.approve(address(mdxChef), _amount);
            mdxChef.deposit(pool.mdxChefPid, _amount);
        }

        pool.lpBalance = pool.lpBalance.add(_amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accHptPerShare).div(1e12);
        user.mdxRewardDebt = user.amount.mul(pool.accMdxPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount, address _user) public override onlyOps {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        if (user.goblin == address(0)) {
            return;
        }
        require(msg.sender == user.goblin, 'only goblin');

        if (user.amount < _amount) {
            _amount = user.amount;
        }
        updatePool(_pid);

        {
            // reward hpt
            uint256 pending =
            user.amount.mul(pool.accHptPerShare).div(1e12).sub(
                user.rewardDebt
            );
            safeHptTransfer(_pid, pool, _user, pending);

            // reward mdx
            uint256 mdxPending =
            user.amount.mul(pool.accMdxPerShare).div(1e12).sub(
                user.mdxRewardDebt
            );
            safeMdxTransfer(_pid, pool, _user, mdxPending);
        }

        pool.lpBalance = pool.lpBalance.sub(_amount);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accHptPerShare).div(1e12);
        user.mdxRewardDebt = user.amount.mul(pool.accMdxPerShare).div(1e12);

        if (_amount > 0) {
            mdxChef.withdraw(pool.mdxChefPid, _amount);
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claim(uint _pid, address token, address _user, address to) public override onlyOps returns(uint) {
        PoolInfo storage pool = poolInfo[_pid];
        withdraw(_pid, 0, _user);
        uint amount = pool.treasury.userTokenAmt(_user, address(token));
        if (amount > 0) {
            pool.treasury.withdraw(_user, address(token), amount, to);
            emit Claim(token, _user, to, amount);
        }
        return amount;
    }

    function claimAll(uint _pid, address _user, address to) public override onlyOps {
        claim(_pid, address(hpt), _user, to);
        claim(_pid, address(mdx), _user, to);
    }

    function safeHptTransfer(uint256 pid, PoolInfo memory pool, address _to, uint256 _amount) internal {
        hptRewardBalance = hptRewardBalance.sub(_amount);
        userInfo[pid][_to].hptRewarded += _amount;
        uint256 hptBal = hpt.balanceOf(address(this));
        if (_amount > hptBal) {
            _amount = hptBal;
        }
        if (_amount > 0) {
            pool.treasury.deposit(_to, address(hpt), _amount);
        }
    }

    function safeMdxTransfer(uint256 pid, PoolInfo memory pool, address _to, uint256 _amount) internal {
        mdxRewardBalance = mdxRewardBalance.sub(_amount);
        userInfo[pid][_to].mdxRewarded += _amount;
        uint256 mdxBal = mdx.balanceOf(address(this));
        if (_amount > mdxBal) {
            _amount = mdxBal;
        }
        if (_amount > 0) {
            pool.treasury.deposit(_to, address(mdx), _amount);
        }
    }

fallback() external {}
receive() payable external {}
}

