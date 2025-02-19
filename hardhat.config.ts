import type { HardhatUserConfig } from 'hardhat/config';
import dotenv from 'dotenv';
import '@nomicfoundation/hardhat-toolbox-viem';
import '@nomicfoundation/hardhat-foundry';
import '@nomicfoundation/hardhat-verify';

dotenv.config();

const config: HardhatUserConfig = {
  solidity: '0.8.28',
  networks: {
    localBase: {
      chainId: 8453,
      url: 'http://localhost:8545',
      accounts: [
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
      ],
    },
    base: {
      chainId: 8453,
      url: 'https://base-mainnet.core.chainstack.com/15a121c3b3c72ddcb7ed95356e985b44',
      accounts: [`0x${process.env.BASE_PRIVATE_KEY}`],
    },
    sepolia: {
      chainId: 11155111,
      url: 'https://ethereum-sepolia.core.chainstack.com/2a3d5515d972bc6c2e2563674d69cd19',
      accounts: [`0x${process.env.SEPOLIA_PRIVATE_KEY}`],
    },
  },
  sourcify: {
    enabled: true,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
