import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("BroMergeModule", m => {
	const broMerge = m.contract("BroMerge");

	// const rate = 3645;
	// m.call("broMerge", "setRate", BigInt(rate));

	return { broMerge };
});
