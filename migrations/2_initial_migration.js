const Poa_factory = artifacts.require("poa_factory");
module.exports = function (deployer) {
  deployer.deploy(Poa_factory);
};
