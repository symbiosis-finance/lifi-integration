import { ethers, network } from 'hardhat'
import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import sgConfig from '../config/stargate'
import { Executor, ERC20Proxy, PeripheryRegistryFacet } from '../typechain'
import { verifyContract } from './9999_verify_all_facets.ts'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  let sgRouter = ethers.constants.AddressZero
  if (sgConfig[network.name]) {
    sgRouter = sgConfig[network.name].stargateRouter
  }

  const diamond = await ethers.getContract('LiFiDiamond')

  const registryFacet = <PeripheryRegistryFacet>(
    await ethers.getContractAt('PeripheryRegistryFacet', diamond.address)
  )

  await deploy('ERC20Proxy', {
    from: deployer,
    log: true,
    args: [deployer],
    deterministicDeployment: true,
  })

  const erc20Proxy: ERC20Proxy = await ethers.getContract('ERC20Proxy')
  const erc20ProxyAddr = await registryFacet.getPeripheryContract('ERC20Proxy')

  if (erc20ProxyAddr !== erc20Proxy.address) {
    console.log('Updating periphery registry...')
    await registryFacet.registerPeripheryContract(
      'ERC20Proxy',
      erc20Proxy.address
    )
    console.log('Done!')
  }

  await deploy('Executor', {
    from: deployer,
    log: true,
    args: [deployer, erc20Proxy.address],
    deterministicDeployment: true,
  })

  const executor: Executor = await ethers.getContract('Executor')
  const executorAddr = await registryFacet.getPeripheryContract('Executor')

  let tx
  if (executorAddr !== executor.address) {
    console.log('Updating periphery registry...')
    tx = await registryFacet.registerPeripheryContract(
      'Executor',
      executor.address
    )
    await tx.wait()
    console.log('Done!')
  }

  tx = await erc20Proxy.setAuthorizedCaller(executor.address, true)
  await tx.wait()

  await verifyContract(hre, 'Executor', {
    address: executor.address,
    args: [deployer, erc20Proxy.address],
  })
  await verifyContract(hre, 'ERC20Proxy', {
    address: erc20Proxy.address,
    args: [deployer],
  })
}

export default func
func.id = 'deploy_executor'
func.tags = ['DeployExecutor']
func.dependencies = ['DeployPeripheryRegistryFacet']