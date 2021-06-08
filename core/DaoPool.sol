// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "../library/IERC20.sol";
import "../library/Ownable.sol";
import "../library/EnumerableSet.sol";
import "../library/SafeERC20.sol";
import "../library/SafeMath.sol";

contract DaoPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 lastDepositTime;
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 allocPoint;       // How many allocation points assigned to this pool. KSAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that KSAs distribution occurs.
        uint256 accKsaPerShare; // Accumulated KSAs per share, times 1e12.
        uint256 totalAmount;    // Total amount of current pool deposit.
        uint256 lockTime;       // min lock time
    }

    // The KSA Token!
    IERC20 public ksa;
    // KSA tokens created per block.
    uint256 public ksaPerBlock;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Control mining
    bool public paused = false;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when KSA mining starts.
    uint256 public startBlock;
    // How many blocks are halved
    uint256 public halvingPeriod = 864000;
    //
    uint256 public remainRewards;
    //
    uint256 public totalDeposits;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event MineRewards(address indexed user, uint256 amount);
    event AddDaoLp(uint256 pid, uint256 allocPoint, uint256 lockTime);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IERC20 _ksa,
        uint256 _ksaPerDay,
        uint256 _totalMintSupply,
        uint256 _startBlock
    ) public {
        ksa = _ksa;
        ksaPerBlock = _ksaPerDay.div(28800);
        remainRewards = _totalMintSupply;
        startBlock = _startBlock;
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
    }
    
    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function setPause() public onlyOwner {
        paused = !paused;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, uint256 _lockTime, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            allocPoint : _allocPoint,
            lastRewardBlock : lastRewardBlock,
            accKsaPerShare : 0,
            totalAmount : 0,
            lockTime : _lockTime
        }));
        emit AddDaoLp(poolLength() - 1, _allocPoint, _lockTime);
    }

    // Update the given pool's KSA allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function phase(uint256 blockNumber) public view returns (uint256) {
        if (halvingPeriod == 0) {
            return 0;
        }
        if (blockNumber > startBlock) {
            return (blockNumber.sub(startBlock).sub(1)).div(halvingPeriod);
        }
        return 0;
    }

    function reward(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        return ksaPerBlock.mul(9 ** _phase).div(10 ** _phase);
    }
    
    function getKsaBlockReward(uint256 _lastRewardBlock) public view returns (uint256) {
        uint256 blockReward = 0;
        uint256 n = phase(_lastRewardBlock);
        uint256 m = phase(block.number);
        while (n < m) {
            n++;
            uint256 r = n.mul(halvingPeriod).add(startBlock);
            blockReward = blockReward.add((r.sub(_lastRewardBlock)).mul(reward(r)));
            _lastRewardBlock = r;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(reward(block.number)));
        return blockReward;
    }

    // Update reward variables for all pools. Be careful of gas spending!
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
        uint256 lpSupply = totalDeposits;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockReward = getKsaBlockReward(pool.lastRewardBlock);
        if (blockReward <= 0) {
            return;
        }
        uint256 ksaReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        bool minRet = _swapMint(ksaReward);
        if (minRet) {
            pool.accKsaPerShare = pool.accKsaPerShare.add(ksaReward.mul(1e12).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    // View function to see pending KSAs on frontend.
    function pending(uint256 _pid, address _user) external view returns (uint256, uint256){
        uint256 ksaAmount = pendingKsa(_pid, _user);
        return (ksaAmount, 0);
    }

    function _swapMint(uint256 _amount) private returns (bool) {
        if (_amount > remainRewards) {
            return false;
        }
        remainRewards = remainRewards.sub(_amount);
        return true;
    }

    function pendingKsa(uint256 _pid, address _user) private view returns (uint256){
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accKsaPerShare = pool.accKsaPerShare;
        uint256 lpSupply = totalDeposits;
        if (user.amount > 0) {
            if (block.number > pool.lastRewardBlock) {
                uint256 blockReward = getKsaBlockReward(pool.lastRewardBlock);
                uint256 ksaReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
                accKsaPerShare = accKsaPerShare.add(ksaReward.mul(1e12).div(lpSupply));
                return user.amount.mul(accKsaPerShare).div(1e12).sub(user.rewardDebt);
            }
            if (block.number == pool.lastRewardBlock) {
                return user.amount.mul(accKsaPerShare).div(1e12).sub(user.rewardDebt);
            }
        }
        return 0;
    }

    // Deposit LP tokens to HecoPool for KSA allocation.
    function deposit(uint256 _pid, uint256 _amount) public notPause {
        depositKsa(_pid, _amount, msg.sender);
        if (_amount > 0) {
            UserInfo storage user = userInfo[_pid][msg.sender];
            user.lastDepositTime = block.timestamp;
        }
    }

    function depositKsa(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pendingAmount = user.amount.mul(pool.accKsaPerShare).div(1e12).sub(user.rewardDebt);
            if (pendingAmount > 0) {
                safeKsaTransfer(_user, pendingAmount);
            }
        }
        if (_amount > 0) {
            ksa.safeTransferFrom(_user, address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
            totalDeposits = totalDeposits.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accKsaPerShare).div(1e12);
        emit Deposit(_user, _pid, _amount);
    }

    // Withdraw LP tokens from HecoPool.
    function withdraw(uint256 _pid, uint256 _amount) public notPause {
        withdrawKsa(_pid, _amount, msg.sender);
    }

    function withdrawKsa(uint256 _pid, uint256 _amount, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(block.timestamp.sub(user.lastDepositTime) >= pool.lockTime, "not enough lock time");
        require(user.amount >= _amount, "withdrawKsa: not good");
        updatePool(_pid);
        uint256 pendingAmount = user.amount.mul(pool.accKsaPerShare).div(1e12).sub(user.rewardDebt);
        if (pendingAmount > 0) {
            safeKsaTransfer(_user, pendingAmount);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            totalDeposits = totalDeposits.sub(_amount);
            ksa.safeTransfer(_user, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accKsaPerShare).div(1e12);
        emit Withdraw(_user, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public notPause {
        emergencyWithdrawKsa(_pid, msg.sender);
    }

    function emergencyWithdrawKsa(uint256 _pid, address _user) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        ksa.safeTransfer(_user, amount);
        pool.totalAmount = pool.totalAmount.sub(amount);
        totalDeposits = totalDeposits.sub(amount);
        emit EmergencyWithdraw(_user, _pid, amount);
    }

    // Safe KSA transfer function, just in case if rounding error causes pool to not have enough KSAs.
    function safeKsaTransfer(address _to, uint256 _amount) internal {
        uint256 ksaBal = ksa.balanceOf(address(this));
        if (_amount > ksaBal) {
            ksa.safeTransfer(_to, ksaBal);
            emit MineRewards(_to, ksaBal);
        } else {
            ksa.safeTransfer(_to, _amount);
            emit MineRewards(_to, _amount);
        }
    }

    modifier notPause() {
        require(paused == false, "Mining has been suspended");
        _;
    }
}
