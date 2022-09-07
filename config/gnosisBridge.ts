interface GnosisBridgeConfig {
  [key: string]: {
    xDaiBridge: string
    token: string
    dstChainId: number
  }
}

const config: GnosisBridgeConfig = {
  hardhat: {
    xDaiBridge: '0x4aa42145Aa6Ebf72e164C9bBC74fbD3788045016',
    token: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    dstChainId: 100,
  },
  mainnet: {
    xDaiBridge: '0x4aa42145Aa6Ebf72e164C9bBC74fbD3788045016',
    token: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    dstChainId: 100,
  },
}

export default config
