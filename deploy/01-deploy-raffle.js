const ENTRANCE_FEE = ethers.utils.parseEther("0.1");

module.exports = async({getNamedAccounts, deployments }) => {
    const { deployer } = await getNamedAccounts();
    const {deploy, log } = deployments;

    const args = [
        ENTRANCE_FEE,
        "300", //interval in seconds
        "0x6168499c0cFfCaCD319c818142124B7A15E857ab", //address vrfCoordinatorV2 =
        "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc", //gaslane: bytes32 keyHash 
        "123", //subscription ID
        "500000", //gaslLimit
    ]
    
    const raffle = await deploy("Raffle", {
        from: deployer,
        args: args,
        log: true,
    
    });
    

}


