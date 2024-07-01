//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

library EIP712 {
    function buildDomainSeparator(string memory name, string memory version, address verifyingContract)
        internal
        view
        returns (bytes32)
    {
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        bytes32 typeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        return keccak256(abi.encode(typeHash, hashedName, hashedVersion, block.chainid, verifyingContract));
    }

    function hashTypedDataV4(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return toTypedDataHash(domainSeparator, structHash);
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
