// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IWrappedTokenGatewayV3} from "@aave/periphery-v3/contracts/misc/interfaces/IWrappedTokenGatewayV3.sol";

/**
 * @title The WETH Gateway contract is a helper to easily wrap and unwrap ETH
 * @dev For more details, see: https://docs.aave.com/developers/periphery-contracts/wethgateway
*/
interface IWETHGatewayV3 is IWrappedTokenGatewayV3 {

    function getWETHAddress() external view returns (address wETHAddress);

}
