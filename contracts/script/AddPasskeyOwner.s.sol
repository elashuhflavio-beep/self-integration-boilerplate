// script/AddPasskeyOwner.s.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

interface ISafe {
    function nonce() external view returns (uint256);
    function getThreshold() external view returns (uint256);
    function isOwner(address) external view returns (bool);
    function addOwnerWithThreshold(address owner, uint256 _threshold) external;
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    )
        external
        view
        returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    )
        external
        payable
        returns (bool);
}

contract AddPasskeyOwner is Script {
    ISafe constant SAFE = ISafe(0x0ec204c1cd97E9B90823AB4c6Ea530f9f1df4994);
    address constant PERSONAL = 0xb45B9a2e25e3A327E30eeD062205D8D1D4fD3567;

    function run() external {
        uint256 step = vm.envOr("STEP", uint256(1));
        if (step == 1) addPasskey();
        else if (step == 2) sendToPersonal();
        else revert("STEP debe ser 1 o 2");
    }

    // Paso 1: añadir el SafeWebAuthnSignerProxy como dueño, umbral 1
    function addPasskey() internal {
        address passkeySigner = vm.envAddress("PASSKEY_SIGNER");
        require(passkeySigner.code.length > 0, "el proxy de la passkey no esta desplegado");
        require(!SAFE.isOwner(passkeySigner), "ya es duena");

        bytes memory data = abi.encodeCall(ISafe.addOwnerWithThreshold, (passkeySigner, 1));
        _run(address(SAFE), 0, data);

        if (vm.envOr("OWNER_SIG", bytes("")).length > 0) {
            require(SAFE.isOwner(passkeySigner) && SAFE.getThreshold() == 1, "algo no cuadra");
        }
    }

    // Paso 2: enviar ETH a la cartera personal (solo después del paso 1)
    function sendToPersonal() internal {
        address passkeySigner = vm.envAddress("PASSKEY_SIGNER");
        require(SAFE.isOwner(passkeySigner), "primero completa el paso 1 (passkey como duena)");

        // AMOUNT_WEI opcional; si no se pasa, envía todo el saldo
        uint256 amount = vm.envOr("AMOUNT_WEI", address(SAFE).balance);
        require(amount > 0, "la Safe no tiene saldo");
        require(amount <= address(SAFE).balance, "monto mayor que el saldo");

        uint256 before = PERSONAL.balance;
        _run(PERSONAL, amount, "");

        if (vm.envOr("OWNER_SIG", bytes("")).length > 0) {
            require(PERSONAL.balance >= before + amount, "no llego el ETH");
        }
    }

    // Simula e imprime el safeTxHash; solo ejecuta si hay OWNER_SIG
    function _run(address to, uint256 value, bytes memory data) internal {
        uint256 nonce = SAFE.nonce();
        bytes32 txHash = SAFE.getTransactionHash(to, value, data, 0, 0, 0, 0, address(0), address(0), nonce);

        console.log("to:");
        console.logAddress(to);
        console.log("value (wei):");
        console.logUint(value);
        console.log("nonce:");
        console.logUint(nonce);
        console.log("data:");
        console.logBytes(data);
        console.log("safeTxHash a firmar:");
        console.logBytes32(txHash);

        bytes memory sig = vm.envOr("OWNER_SIG", bytes(""));
        if (sig.length == 0) return;

        vm.startBroadcast();
        SAFE.execTransaction(to, value, data, 0, 0, 0, 0, address(0), payable(address(0)), sig);
        vm.stopBroadcast();
    }
}
