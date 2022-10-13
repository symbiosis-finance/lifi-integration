interface AcrossConfig {
  [key: string]: {
    acrossSpokePool: string
    weth: string
  }
}

const config: AcrossConfig = {
  hardhat: {
    acrossSpokePool: '0x4D9079Bb4165aeb4084c526a32695dCfd2F77381',
    weth: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
  },
  boba: {
    acrossSpokePool: '0xBbc6009fEfFc27ce705322832Cb2068F8C1e0A58',
    weth: '0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000',
  },
  arbitrumOne: {
    acrossSpokePool: '0xB88690461dDbaB6f04Dfad7df66B7725942FEb9C',
    weth: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
  },
  optimisticEthereum: {
    acrossSpokePool: '0xa420b2d1c0841415A695b81E5B867BCD07Dff8C9',
    weth: '0x4200000000000000000000000000000000000006',
  },
  polygon: {
    acrossSpokePool: '0x69B5c72837769eF1e7C164Abc6515DcFf217F920',
    weth: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619',
  },
  mainnet: {
    acrossSpokePool: '0x4D9079Bb4165aeb4084c526a32695dCfd2F77381',
    weth: '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2',
  },

  // Testnet
  rinkeby: {
    acrossSpokePool: '0x90743806D7A66b37F31FAfd7b3447210aB55640f',
    weth: '0xDf032Bc4B9dC2782Bb09352007D4C57B75160B15',
  },
  kovan: {
    acrossSpokePool: '0x73549B5639B04090033c1E77a22eE9Aa44C2eBa0',
    weth: '0xF3A6679B266899042276804930B3bFBaf807F15b',
  },
  arbitrumTestnet: {
    acrossSpokePool: '0x3BED21dAe767e4Df894B31b14aD32369cE4bad8b',
    weth: '',
  },
  optimisticKovan: {
    acrossSpokePool: '0x2b7b7bAE341089103dD22fa4e8D7E4FA63E11084',
    weth: '0x4200000000000000000000000000000000000006',
  },
  polygonMumbai: {
    acrossSpokePool: '0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944',
    weth: '0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa',
  },
}

export default config