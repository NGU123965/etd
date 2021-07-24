pragma solidity ^0.5.8;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract TokenVesting is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event TokensReleased(address token, uint256 amount);
    event TokenVestingRevoked(address token);

    address private _beneficiary;

    uint256 private _cliff;
    uint256 private _start;
    uint256 private _duration;

    bool private _revocable;

    mapping (address => uint256) private _released;
    mapping (address => uint256) private _revoked;
    mapping (address => uint256) private _refunded;

    constructor (address beneficiary, uint256 start, uint256 cliffDuration, uint256 duration, bool revocable) public {
        require(beneficiary != address(0), "TokenVesting: beneficiary is the zero address");
        require(cliffDuration <= duration, "TokenVesting: cliff is longer than duration");
        require(duration > 0, "TokenVesting: duration is 0");
        require(start.add(duration) > block.timestamp, "TokenVesting: final time is before current time");

        _beneficiary = beneficiary;
        _revocable = revocable;
        _duration = duration;
        _cliff = start.add(cliffDuration);
        _start = start;
    }

    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    function cliff() public view returns (uint256) {
        return _cliff;
    }

    function start() public view returns (uint256) {
        return _start;
    }

    function duration() public view returns (uint256) {
        return _duration;
    }

    function revocable() public view returns (bool) {
        return _revocable;
    }

    function released(address token) public view returns (uint256) {
        return _released[token];
    }

    function revoked(address token) public view returns (bool) {
        return (_revoked[token] != 0);
    }

    function release(IERC20 token) public onlyOwner {
        uint256 unreleased = _releasableAmount(token);

        require(unreleased > 0, "TokenVesting: no tokens are due");

        _released[address(token)] = _released[address(token)].add(unreleased);

        token.safeTransfer(_beneficiary, unreleased);

        emit TokensReleased(address(token), unreleased);
    }

    function revoke(IERC20 token) public onlyOwner {
        require(_revocable, "TokenVesting: cannot revoke");
        require(_revoked[address(token)] == 0, "TokenVesting: token already revoked");

        uint256 balance = token.balanceOf(address(this));

        _revoked[address(token)] = block.timestamp;

        uint256 unreleased = _releasableAmount(token);
        uint256 refund = balance.sub(unreleased);

        _refunded[address(token)] = refund;

        token.safeTransfer(owner(), refund);

        emit TokenVestingRevoked(address(token));
    }

    function vested(IERC20 token) public view returns (uint256) {
        return _vestedAmount(token);
    }

    function _releasableAmount(IERC20 token) private view returns (uint256) {
        return _vestedAmount(token).sub(_released[address(token)]);
    }

    function _vestedAmount(IERC20 token) private view returns (uint256) {
        uint256 currentBalance = token.balanceOf(address(this));
        uint256 totalBalance = currentBalance.add(_released[address(token)]).add(_refunded[address(token)]);

        if (block.timestamp < _cliff) {
            return 0;
        } else if (block.timestamp >= _start.add(_duration) && _revoked[address(token)] == 0) {
            return totalBalance;
        } else if (_revoked[address(token)] > 0) {
            return totalBalance.mul(_revoked[address(token)].sub(_start)).div(_duration);
        } else {
            return totalBalance.mul(block.timestamp.sub(_start)).div(_duration);
        }
    }
}