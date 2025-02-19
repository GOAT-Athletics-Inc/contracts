// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IGOATAI {
    function buyFeeBps() external view returns (uint256);
    function sellFeeBps() external view returns (uint256);
    function feeRecipients() external view returns (address[] memory);
    function feeRecipientSplits() external view returns (uint256[] memory);
    function feeBurnSplit() external view returns (uint256);

    function setBuyFeeBps(uint256 feeBps) external;
    function setSellFeeBps(uint256 feeBps) external;
    function setFeeSplits(
        address[] calldata recipients,
        uint256[] calldata splitsBps
    ) external;

    function isLPPair(address account) external view returns (bool);
    function setLPPair(address lpPair, bool _isLpPair) external;

    function isExempt(address account) external view returns (bool);
    function setExempt(address[] calldata accounts, bool exempt) external;
}
