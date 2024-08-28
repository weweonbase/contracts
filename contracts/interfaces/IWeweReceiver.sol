// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IWeweReceiver {
    function receiveApproval(address from, uint256 amount, address token, bytes calldata extraData) external;
}
