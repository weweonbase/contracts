// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWeweReceiver} from "../interfaces/IWeweReceiver.sol";
import {IERC1363Receiver} from "../token/ERC1363/IERC1363Receiver.sol";
import {IMerge} from "../interfaces/IMerge.sol";

contract Merge is IMerge, IWeweReceiver, IERC1363Receiver, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public virtualWeweBalance = 10_000_000_000 * 1e18;
    uint256 public weweBalance;
    uint256 public vultBalance;
    IERC20 public immutable wewe;
    IERC20 public immutable vult;

    LockedStatus public lockedStatus;

    constructor(address _wewe, address _vult) {
        wewe = IERC20(_wewe);
        vult = IERC20(_vult);
    }

    /// @notice Wewe token approveAndCall
    function receiveApproval(
        address from,
        uint256 amount,
        address token,
        bytes calldata extraData
    ) external nonReentrant {
        if (msg.sender != address(wewe)) {
            revert InvalidTokenReceived();
        }
        if (lockedStatus == LockedStatus.Locked) {
            revert MergeLocked();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        // wewe in, vult out
        uint256 vultOut = quoteVult(amount);
        wewe.safeTransferFrom(from, address(this), amount);
        vult.safeTransfer(from, vultOut);
        weweBalance += amount;
        vultBalance -= vultOut;
    }

    /*
     * @inheritdoc IERC1363Receiver
     * Vult token transferAndCall
     */
    function onTransferReceived(
        address operator,
        address from,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bytes4) {
        if (msg.sender != address(vult)) {
            revert InvalidTokenReceived();
        }
        if (lockedStatus != LockedStatus.TwoWay) {
            revert VultToWeweNotAllwed();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        // vult in, wewe out
        uint256 weweOut = quoteWewe(amount);
        vult.safeTransferFrom(from, address(this), amount);
        wewe.safeTransfer(from, weweOut);
        vultBalance += amount;
        weweBalance -= weweOut;

        return this.onTransferReceived.selector;
    }

    function deposit(IERC20 token, uint256 amount) external onlyOwner {
        if (token != wewe && token != vult) {
            revert InvalidTokenReceived();
        }

        token.safeTransferFrom(msg.sender, address(this), amount);
        if (token == wewe) {
            weweBalance += amount;
        } else {
            // Vult
            vultBalance += amount;
        }
    }

    function setLockedStatus(LockedStatus newStatus) external onlyOwner {
        lockedStatus = newStatus;
    }

    function setVirtualWeweBalance(uint256 newVirtualBalance) external onlyOwner {
        virtualWeweBalance = newVirtualBalance;
    }

    function quoteVult(uint256 w) public view returns (uint256 v) {
        uint256 W = weweBalance + virtualWeweBalance;
        uint256 V = vultBalance;
        v = (w * V) / (w + W);
    }

    function quoteWewe(uint256 v) public view returns (uint256 w) {
        uint256 W = weweBalance + virtualWeweBalance;
        uint256 V = vultBalance;
        w = (v * W) / (v + V);
    }
}
