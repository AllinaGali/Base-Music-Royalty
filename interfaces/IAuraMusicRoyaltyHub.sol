// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
interface IAuraMusicRoyaltyHub {
    function streamAudioTrack(uint256 trackId) external payable;
    function buyCommercialLicense(uint256 trackId) external payable;
}
