// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

// import "../library/IERC20.sol";
import "https://github.com/DancGo/WFC/tree/main/library/IERC20.sol"
// import "../library/Ownable.sol";
import "https://github.com/DancGo/WFC/tree/main/library/Ownable.sol"
// import "../library/SafeERC20.sol";
import "https://github.com/DancGo/WFC/tree/main/library/SafeERC20.sol"
// import "../library/SafeMath.sol";
import "https://github.com/DancGo/WFC/tree/main/library/SafeMath.sol"

contract PromotePool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => address) private inviters;
    mapping(address => uint256) private rewards;
    // The KSA Token!
    IERC20 public ksa;
    // Control mining
    bool public paused = false;
    //
    address public swappool;

    event InviterReward(address indexed inviter, address indexed invitee, uint256 amount);

    constructor(
        IERC20 _ksa,
        address _swappool
    ) public {
        ksa = _ksa;
        swappool = _swappool;
    }

    function setPause() public onlyOwner {
        paused = !paused;
    }

    function userRewards(address _user) external view returns(uint256) {
        return rewards[_user];
    }

    function register(address _inviter) external {
        require(inviters[msg.sender] == address(0), "already exists");
        require(_inviter != msg.sender && _inviter != address(0), "already exists");
        inviters[msg.sender] = _inviter;
    }

    function checkRegister(address _user) external view returns(bool) {
        return inviters[_user] != address(0);
    }

    function deposit(address _user, uint256 _amount) public notPause {
        require(msg.sender == swappool, "not owner");
        address _inviter = inviters[_user];
        if (_inviter != address(0)) {
            rewards[_inviter] = rewards[_inviter].add(_amount);
            emit InviterReward(_inviter, _user, _amount);
        }
    }

    // Withdraw LP tokens from HecoPool.
    function withdraw(uint256 _amount) public notPause {
        require(rewards[msg.sender] >= _amount, 'not enough withdraw');
        uint256 withdrawAmount = _amount;
        uint256 poolBalance = ksa.balanceOf(address(this));
        if (withdrawAmount > poolBalance) {
            withdrawAmount = poolBalance;
        }
        if (withdrawAmount > 0) {
            rewards[msg.sender] = rewards[msg.sender].sub(withdrawAmount);
            safeKsaTransfer(msg.sender, withdrawAmount);
        }
    }

    // Safe KSA transfer function, just in case if rounding error causes pool to not have enough KSAs.
    function safeKsaTransfer(address _to, uint256 _amount) internal {
        uint256 ksaBal = ksa.balanceOf(address(this));
        if (_amount > ksaBal) {
            ksa.safeTransfer(_to, ksaBal);
        } else {
            ksa.safeTransfer(_to, _amount);
        }
    }

    modifier notPause() {
        require(paused == false, "Mining has been suspended");
        _;
    }
}
