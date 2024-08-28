// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IMerge {
    enum LockedStatus {
        Locked,
        OneWay,
        TwoWay
    }

    error MergeLocked();
    error VultToWeweNotAllwed();
    error InvalidTokenReceived();
    error ZeroAmount();
}
