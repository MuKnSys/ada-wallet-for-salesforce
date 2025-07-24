import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import { getRecord } from 'lightning/uiRecordApi';

import TRANSACTION_STATUS_FIELD from '@salesforce/schema/Outbound_Transaction__c.Transaction_Status__c';
import TRANSACTION_HASH_FIELD from '@salesforce/schema/Outbound_Transaction__c.Transaction_Hash__c';
import TO_ADDRESS_FIELD from '@salesforce/schema/Outbound_Transaction__c.To_Address__c';
import MEMO_FIELD from '@salesforce/schema/Outbound_Transaction__c.Memo__c';
import WALLET_FIELD from '@salesforce/schema/Outbound_Transaction__c.Wallet__c';
import OTL_ASSET_FIELD from '@salesforce/schema/Outbound_Transaction_Line__c.Asset__c';
import OTL_AMOUNT_FIELD from '@salesforce/schema/Outbound_Transaction_Line__c.Amount__c';

import CARDANO_SERIALIZATION from '@salesforce/resourceUrl/cardanoSerialization';
import BLAKE from '@salesforce/resourceUrl/blake';

import getEpochParameters from '@salesforce/apex/TransactionController.getEpochParameters';
import getTransactionLinesForOutbound from '@salesforce/apex/TransactionController.getTransactionLinesForOutbound';
import getOutboundTransaction from '@salesforce/apex/TransactionController.getOutboundTransaction';
import updateOutboundTransactionWithSignedCbor from '@salesforce/apex/TransactionController.updateOutboundTransactionWithSignedCbor';
import loadWallet from '@salesforce/apex/TransactionController.loadWallet';

class CardanoTransactionError extends Error {
    constructor(message, code, details = {}) {
        super(message);
        this.name = 'CardanoTransactionError';
        this.code = code;
        this.details = details;
    }
}

export default class PrepareAndSignTransaction extends LightningElement {
    @api recordId;
    @track isLoading = false;
    @track outboundTransaction;
    @track librariesLoaded = false;
    @track isLoadingLibraries = false;
    @track transactionLines = [];

    cardanoLib = null;
    blakeLib = null;

    @wire(getRecord, { recordId: '$recordId', fields: [TRANSACTION_STATUS_FIELD, TRANSACTION_HASH_FIELD] })
    wiredRecord({ error, data }) {
        if (data && data.fields) {
            if (!this.outboundTransaction) {
                this.outboundTransaction = {};
            }

            const statusApi = TRANSACTION_STATUS_FIELD.fieldApiName;
            const hashApi   = TRANSACTION_HASH_FIELD.fieldApiName;

            const statusVal = data.fields[statusApi] ? data.fields[statusApi].value : null;
            const hashVal   = data.fields[hashApi]   ? data.fields[hashApi].value   : null;

            this.outboundTransaction = {
                ...this.outboundTransaction,
                Transaction_Status__c: statusVal,
                Transaction_Hash__c: hashVal
            };
        }
    }

    renderedCallback() {
        if (!this.librariesLoaded && !this.isLoadingLibraries) {
            this.isLoadingLibraries = true;
            this.loadLibraries()
                .then(() => {
                    this.isLoadingLibraries = false;
                })
                .catch((error) => {
                    this.isLoadingLibraries = false;
                    this.showToast('Error', 'Failed to load required libraries. Please refresh the page.', 'error');
                });
        }
    }

    async loadLibraries() {
        if (this.librariesLoaded) {
            return;
        }
        
        this.isLoadingLibraries = true;
        
        try {
            const scripts = [
                { name: 'cardanoSerialization', url: `${CARDANO_SERIALIZATION}/cardanoSerialization/bundle.js` },
                { name: 'blake', url: BLAKE }
            ];
            
            for (const script of scripts) {
                await loadScript(this, script.url);
            }
            
            if (!window.cardanoSerialization) {
                throw new Error('Cardano serialization library not found on window object');
            }
            if (!window.Blake2b) {
                throw new Error('Blake2b library not found on window object');
            }
            
            this.cardanoLib = window.cardanoSerialization;
            this.blakeLib = window.Blake2b;
            
            if (!this.cardanoLib) {
                throw new Error('Cardano serialization library is null or undefined');
            }
            
            this.librariesLoaded = true;
            
        } catch (error) {
            this.showToast('Error', 'Failed to load required libraries: ' + error.message, 'error');
        } finally {
            this.isLoadingLibraries = false;
        }
    }

    validateAddress(address) {
        try {
            this.cardanoLib.Address.from_bech32(address);
            return true;
        } catch (error) {
            throw new CardanoTransactionError(`Invalid address format: ${address}`, 'INVALID_ADDRESS', { address });
        }
    }

    collectAndValidateUTXOs(walletData) {
        const utxos = this.cardanoLib.TransactionUnspentOutputs.new();
        const inputUtxosDetails = [];
        let totalLovelace = 0;
        let totalAssets = new Map();

        for (const address of walletData.receivingAddresses) {
            for (const utxo of address.utxos || []) {
                const utxoData = this.processUTXO(utxo, address);
                if (utxoData) {
                    utxos.add(utxoData.cslUtxo);
                    inputUtxosDetails.push(utxoData.details);
                    totalLovelace += utxoData.details.lovelace;
                    this.updateAssetTotals(totalAssets, utxoData.details.assets);
                }
            }
        }

        for (const address of walletData.changeAddresses) {
            for (const utxo of address.utxos || []) {
                const utxoData = this.processUTXO(utxo, address);
                if (utxoData) {
                    utxos.add(utxoData.cslUtxo);
                    inputUtxosDetails.push(utxoData.details);
                    totalLovelace += utxoData.details.lovelace;
                    this.updateAssetTotals(totalAssets, utxoData.details.assets);
                }
            }
        }

        return { utxos, inputUtxosDetails, totalLovelace, totalAssets };
    }

    processUTXO(utxo, address) {
        try {
            if (!utxo.tx_hash || typeof utxo.tx_index !== 'number' || !utxo.amount) {
                return null;
            }

            const input = this.cardanoLib.TransactionInput.new(
                this.cardanoLib.TransactionHash.from_hex(utxo.tx_hash),
                utxo.tx_index
            );

            const value = this.cardanoLib.Value.new(this.cardanoLib.BigNum.from_str('0'));
            const multiAsset = this.cardanoLib.MultiAsset.new();
            const utxoAssets = [];
            let lovelace = 0;

            for (const asset of utxo.amount) {
                if (asset.unit === 'lovelace') {
                    lovelace = parseInt(asset.quantity);
                    value.set_coin(this.cardanoLib.BigNum.from_str(asset.quantity));
                    utxoAssets.push({
                        unit: 'lovelace',
                        quantity: asset.quantity,
                        policyId: null,
                        assetName: null
                    });
                } else {
                    const policyIdHex = asset.unit.slice(0, 56);
                    const assetNameHex = asset.unit.slice(56);
                    const policyId = this.cardanoLib.ScriptHash.from_bytes(this.hexToBytes(policyIdHex));
                    const assetName = this.cardanoLib.AssetName.new(this.hexToBytes(assetNameHex));
                    const assets = this.cardanoLib.Assets.new();
                    assets.insert(assetName, this.cardanoLib.BigNum.from_str(asset.quantity));
                    multiAsset.insert(policyId, assets);
                    utxoAssets.push({
                        unit: asset.unit,
                        quantity: asset.quantity,
                        policyId: policyIdHex,
                        assetName: this.hexToString(assetNameHex)
                    });
                }
            }

            if (multiAsset.len() > 0) {
                value.set_multiasset(multiAsset);
            }

            const output = this.cardanoLib.TransactionOutput.new(
                this.cardanoLib.Address.from_bech32(utxo.address),
                value
            );

            return {
                cslUtxo: this.cardanoLib.TransactionUnspentOutput.new(input, output),
                details: {
                    txHash: utxo.tx_hash,
                    txIndex: utxo.tx_index,
                    address: utxo.address,
                    paymentKeyHash: address.paymentKeyHash,
                    lovelace: lovelace,
                    assets: utxoAssets
                }
            };
        } catch (error) {
            return null;
        }
    }

    updateAssetTotals(totalAssets, assets) {
        for (const asset of assets) {
            if (asset.unit !== 'lovelace') {
                const current = totalAssets.get(asset.unit) || 0;
                totalAssets.set(asset.unit, current + parseInt(asset.quantity));
            }
        }
    }

    convertAssetsToOutputs(outputs, walletData) {
        const multiAsset = this.cardanoLib.MultiAsset.new();
        const outputValue = this.cardanoLib.Value.new(this.cardanoLib.BigNum.from_str('0'));
        let totalLovelace = 0;
        
        for (const output of outputs) {
            if (output.unit === 'lovelace') {
                const lovelaceAmount = Math.floor(output.amount * 1000000);
                totalLovelace += lovelaceAmount;
            } else {
                const assetInfo = walletData.walletSummary.totalBalance.assets.find(
                    asset => asset.unit === output.unit
                );
                
                if (!assetInfo) {
                    throw new CardanoTransactionError(`Asset ${output.ticker} not found in wallet cache`, 'ASSET_NOT_FOUND', { asset: output.ticker });
                }

                const decimals = assetInfo.decimals || 0;
                const convertedAmount = Math.floor(output.amount * Math.pow(10, decimals));
                
                const policyIdHex = output.unit.slice(0, 56);
                const assetNameHex = output.unit.slice(56);
                const policyId = this.cardanoLib.ScriptHash.from_bytes(this.hexToBytes(policyIdHex));
                const assetName = this.cardanoLib.AssetName.new(this.hexToBytes(assetNameHex));
                const assets = this.cardanoLib.Assets.new();
                assets.insert(assetName, this.cardanoLib.BigNum.from_str(convertedAmount.toString()));
                multiAsset.insert(policyId, assets);
            }
        }

        outputValue.set_coin(this.cardanoLib.BigNum.from_str(totalLovelace.toString()));
        if (multiAsset.len() > 0) {
            outputValue.set_multiasset(multiAsset);
        }

        return { outputValue };
    }

    calculateMinimumADA(outputValue, minUTxOValue) {
        const utxoEntrySizeWithoutVal = 27;
        const coinSize = 0;
        const adaOnlyUTxOSize = utxoEntrySizeWithoutVal + coinSize;
        
        if (!outputValue.multiasset() || outputValue.multiasset().len() === 0) {
            return minUTxOValue;
        }
        
        const multiAsset = outputValue.multiasset();
        const policies = multiAsset.keys();
        const numPIDs = policies.len();
        
        let numAssets = 0;
        let sumAssetNameLengths = 0;
        
        for (let i = 0; i < policies.len(); i++) {
            const policy = policies.get(i);
            const assets = multiAsset.get(policy);
            numAssets += assets.len();
            
            const assetNames = assets.keys();
            for (let j = 0; j < assetNames.len(); j++) {
                const assetName = assetNames.get(j);
                const assetNameBytes = assetName.name();
                sumAssetNameLengths += assetNameBytes.length;
            }
        }
        
        const pidSize = 28;
        const roundupBytesToWords = (bytes) => Math.floor((bytes + 7) / 8);
        const sizeB = 6 + roundupBytesToWords((numAssets * 12) + sumAssetNameLengths + (numPIDs * pidSize));
        
        const quot = (a, b) => Math.floor(a / b);
        const minAda = Math.max(
            minUTxOValue,
            quot(minUTxOValue, adaOnlyUTxOSize) * (utxoEntrySizeWithoutVal + sizeB)
        );
        
        return minAda;
    }

    createWitnesses(actualInputs, inputUtxosDetails, walletData, txHash) {
        const witnessSet = this.cardanoLib.TransactionWitnessSet.new();
        const vkeyWitnesses = this.cardanoLib.Vkeywitnesses.new();

        const addressToKeyInfo = new Map();
        
        if (walletData.receivingAddresses && walletData.receivingAddresses.length > 0) {
            for (const addr of walletData.receivingAddresses) {
                const privateKey = addr.privateKey || addr.xpriv;
                addressToKeyInfo.set(addr.address, { 
                    paymentKeyHash: addr.paymentKeyHash,
                    keyMatch: addr.keyMatch,
                    privateKey: privateKey
                });
            }
        }
        
        if (walletData.changeAddresses && walletData.changeAddresses.length > 0) {
            for (const addr of walletData.changeAddresses) {
                const privateKey = addr.privateKey || addr.xpriv;
                addressToKeyInfo.set(addr.address, { 
                    paymentKeyHash: addr.paymentKeyHash,
                    keyMatch: addr.keyMatch,
                    privateKey: privateKey
                });
            }
        }

        for (let i = 0; i < actualInputs.len(); i++) {
            const input = actualInputs.get(i);
            const txHashHex = this.bytesToHex(input.transaction_id().to_bytes());
            const txIndex = input.index();
            
            const inputUtxo = inputUtxosDetails.find(utxo => 
                utxo.txHash === txHashHex && utxo.txIndex === txIndex
            );
            
            if (!inputUtxo) {
                throw new CardanoTransactionError(`No UTXO details found for input ${i}`, 'UTXO_NOT_FOUND', { inputIndex: i, txHash: txHashHex, txIndex });
            }
            
            const keyInfo = addressToKeyInfo.get(inputUtxo.address);
            if (!keyInfo) {
                throw new CardanoTransactionError(`No key info found for address ${inputUtxo.address}`, 'KEY_NOT_FOUND', { address: inputUtxo.address });
            }

            let rawKey = null;
            try {
                if (!keyInfo.privateKey) {
                    throw new CardanoTransactionError(`No private key found for address ${inputUtxo.address}`, 'PRIVATE_KEY_NOT_FOUND', { address: inputUtxo.address });
                }
                
                const bip32PrivateKey = this.cardanoLib.Bip32PrivateKey.from_bech32(keyInfo.privateKey);
                rawKey = bip32PrivateKey.to_raw_key();
                
            } catch (e) {
                throw new CardanoTransactionError(`Failed to retrieve signing key for address ${inputUtxo.address}`, 'SIGNING_VERIFICATION_ERROR', { address: inputUtxo.address, error: e.message });
            }

            const witness = this.cardanoLib.make_vkey_witness(txHash, rawKey);
            vkeyWitnesses.add(witness);
        }

        witnessSet.set_vkeys(vkeyWitnesses);
        
        return witnessSet;
    }

    hexToBytes(hex) {
        const bytes = new Uint8Array(hex.length / 2);
        for (let i = 0; i < hex.length; i += 2) {
            bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
        }
        return bytes;
    }

    bytesToHex(bytes) {
        return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
    }

    hexToString(hex) {
        const bytes = this.hexToBytes(hex);
        return new TextDecoder().decode(bytes);
    }

    async loadWalletData(walletId) {
        try {
            const walletData = await loadWallet({ walletId: walletId });
            return walletData;
        } catch (error) {
            this.showToast('Error', `Failed to load wallet: ${error.message}`, 'error');
            throw error;
        }
    }

    async fetchEpochParameters() {
        try {
            const paramsJson = await getEpochParameters();
            return JSON.parse(paramsJson);
        } catch (error) {
            this.showToast('Error', `Failed to fetch epoch parameters: ${error.message}`, 'error');
            throw error;
        }
    }

    async buildAndSignTransaction() {
        this.isLoading = true;
        try {
            let outboundTransactionRecord = null;
            let toAddress = null;
            try {
                outboundTransactionRecord = await getOutboundTransaction({ outboundTransactionId: this.recordId });
                const TO_ADDRESS_API = TO_ADDRESS_FIELD.fieldApiName;
                toAddress = outboundTransactionRecord && outboundTransactionRecord[TO_ADDRESS_API]
                    ? outboundTransactionRecord[TO_ADDRESS_API]
                    : null;
            } catch (e) {
                this.showToast('Error', 'Failed to fetch transaction details', 'error');
                return;
            }

            if (!toAddress) {
                this.showToast('Error', 'Recipient address is required but not found in transaction record', 'error');
                return;
            }

            try {
                await this.fetchTransactionLines();
                if (!this.transactionLines || this.transactionLines.length === 0) {
                    this.showToast('Error', 'No transaction lines found for this transaction', 'error');
                    return;
                }
            } catch (fetchError) {
                this.showToast('Error', 'Failed to fetch transaction lines: ' + (fetchError.message || 'Unknown error'), 'error');
                return;
            }

            try {
                const WALLET_API = WALLET_FIELD.fieldApiName;
                const walletData = await this.loadWalletData(outboundTransactionRecord[WALLET_API]);
                const protocolParams = await this.fetchEpochParameters();

                const linearFee = this.cardanoLib.LinearFee.new(
                    this.cardanoLib.BigNum.from_str(protocolParams.min_fee_a.toString()),
                    this.cardanoLib.BigNum.from_str(protocolParams.min_fee_b.toString())
                );
                const poolDeposit = this.cardanoLib.BigNum.from_str(protocolParams.pool_deposit.toString());
                const keyDeposit = this.cardanoLib.BigNum.from_str(protocolParams.key_deposit.toString());
                const maxValueSize = protocolParams.max_val_size;
                const maxTxSize = protocolParams.max_tx_size;
                const coinsPerUtxoByte = this.cardanoLib.BigNum.from_str(protocolParams.coins_per_utxo_word.toString());

                const txBuilderCfg = this.cardanoLib.TransactionBuilderConfigBuilder.new()
                    .fee_algo(linearFee)
                    .pool_deposit(poolDeposit)
                    .key_deposit(keyDeposit)
                    .max_value_size(maxValueSize)
                    .max_tx_size(maxTxSize)
                    .coins_per_utxo_byte(coinsPerUtxoByte)
                    .build();
                const txBuilder = this.cardanoLib.TransactionBuilder.new(txBuilderCfg);

                let auxData = null;

                const MEMO_API = MEMO_FIELD.fieldApiName;
                if (outboundTransactionRecord[MEMO_API] && outboundTransactionRecord[MEMO_API].trim() !== '') {
                    try {
                        const memo = outboundTransactionRecord[MEMO_API].trim();
                        const generalMetadata = this.cardanoLib.GeneralTransactionMetadata.new();
                        const metadataKey = this.cardanoLib.BigNum.from_str("674");
                        const metadataValue = this.cardanoLib.encode_json_str_to_metadatum(
                            JSON.stringify({ memo: memo }),
                            this.cardanoLib.MetadataJsonSchema.BasicConversions
                        );
                        generalMetadata.insert(metadataKey, metadataValue);
                        auxData = this.cardanoLib.AuxiliaryData.new();
                        auxData.set_metadata(generalMetadata);
                        txBuilder.set_auxiliary_data(auxData);
                    } catch (metaError) {
                        auxData = null;
                    }
                }

                const outputs = this.transactionLines.map(line => {
                    if (line.Asset__c && (line.Asset__c.toLowerCase() === 'ada' || line.Asset__c === 'lovelace')) {
                        return {
                            unit: 'lovelace',
                            amount: parseFloat(line.Amount__c || 0),
                            ticker: 'ADA'
                        };
                    }
                    let tokenUnit = line.Asset__c;
                    if (line.Asset__c && line.Asset__c !== 'lovelace' && line.Asset__c.toLowerCase() !== 'ada') {
                        const asset = walletData.walletSummary.totalBalance.assets.find(
                            a => (a.ticker && a.ticker.toLowerCase() === line.Asset__c.toLowerCase()) ||
                                (a.assetName && a.assetName.toLowerCase() === line.Asset__c.toLowerCase())
                        );
                        if (asset) {
                            tokenUnit = asset.unit;
                        }
                    }
                    return {
                        unit: tokenUnit,
                        amount: parseFloat(line.Amount__c || 0),
                        ticker: line.Asset__c
                    };
                });
                
                let totalRequiredLovelace = 0;
                const requiredAssets = new Map();
                
                for (const output of outputs) {
                    const normalizedUnit = (output.unit && output.unit.toLowerCase() === 'ada') ? 'lovelace' : output.unit;
                    if (normalizedUnit === 'lovelace') {
                        const lovelaceAmount = Math.floor(output.amount * 1000000);
                        totalRequiredLovelace += lovelaceAmount;
                    } else {
                        const assetInfo = this.findAssetInfo(walletData, output.ticker, normalizedUnit);
                        if (!assetInfo) {
                            const availableAssets = this.getAllAvailableAssets(walletData);
                            const availableAssetNames = availableAssets.length > 0 ? availableAssets.join(', ') : 'No assets found';
                            
                            let errorMessage = `Asset "${output.ticker}" not found in wallet. Available assets: ${availableAssetNames}.`;
                            
                            if (availableAssets.length === 0) {
                                errorMessage += ' Your wallet appears to be empty or has no assets. Please add assets to your wallet first.';
                            } else {
                                errorMessage += ' Please check the asset name or ensure the asset is available in your wallet.';
                            }
                            
                            throw new CardanoTransactionError(
                                errorMessage,
                                'ASSET_NOT_FOUND', 
                                { 
                                    ticker: output.ticker, 
                                    unit: output.unit,
                                    availableAssets: availableAssets,
                                    debugInfo: {
                                        walletSummaryAssets: walletData.walletSummary?.totalBalance?.assets || [],
                                        receivingAddressesCount: walletData.receivingAddresses?.length || 0,
                                        changeAddressesCount: walletData.changeAddresses?.length || 0
                                    }
                                }
                            );
                        }
                        const decimals = assetInfo.decimals || 0;
                        const rawAmount = Math.floor(output.amount * Math.pow(10, decimals));
                        const current = requiredAssets.get(output.unit) || 0;
                        requiredAssets.set(output.unit, current + rawAmount);
                    }
                }

                const { outputValue } = this.convertAssetsToOutputs(outputs, walletData);

                this.validateAddress(toAddress);
                const recipientAddress = this.cardanoLib.Address.from_bech32(toAddress);
                const txOutput = this.cardanoLib.TransactionOutput.new(recipientAddress, outputValue);
                txBuilder.add_output(txOutput);

                const utxoResult = this.collectAndValidateUTXOs(walletData);
                const utxos = utxoResult.utxos;
                const inputUtxosDetails = utxoResult.inputUtxosDetails;
                const totalLovelace = utxoResult.totalLovelace;
                const totalAssets = utxoResult.totalAssets;

                const changeAddress = this.cardanoLib.Address.from_bech32(walletData.changeAddresses[0].address);
                const changeConfig = this.cardanoLib.ChangeConfig.new(changeAddress);
                
                try {
                    txBuilder.add_inputs_from_and_change(utxos, 3, changeConfig);
                } catch (selectionError) {
                    let errorMessage = selectionError.toString();
                    let actualRequiredLovelace = totalRequiredLovelace;
                    let shortfall = actualRequiredLovelace - totalLovelace;
                    let minAdaForOutput = 0;
                    let actualFeeLovelace = 0;
                    
                    if (errorMessage.includes('Not enough ADA leftover to include non-ADA assets in a change address')) {
                        const mockChangeValue = this.cardanoLib.Value.new(this.cardanoLib.BigNum.from_str('0'));
                        const mockMultiAsset = this.cardanoLib.MultiAsset.new();
                        
                        for (const [unit, amount] of totalAssets) {
                            if (unit !== 'lovelace') {
                                const policyIdHex = unit.slice(0, 56);
                                const assetNameHex = unit.slice(56);
                                const policyId = this.cardanoLib.ScriptHash.from_bytes(this.hexToBytes(policyIdHex));
                                const assetName = this.cardanoLib.AssetName.new(this.hexToBytes(assetNameHex));
                                const assets = this.cardanoLib.Assets.new();
                                assets.insert(assetName, this.cardanoLib.BigNum.from_str(amount.toString()));
                                mockMultiAsset.insert(policyId, assets);
                            }
                        }
                        
                        if (mockMultiAsset.len() > 0) {
                            mockChangeValue.set_multiasset(mockMultiAsset);
                        }
                        
                        const minAdaForChange = this.calculateMinimumADA(mockChangeValue, parseInt(protocolParams.min_utxo_value || 1000000));
                        const actualFee = txBuilder.min_fee();
                        actualFeeLovelace = parseInt(actualFee.to_str());
                        
                        actualRequiredLovelace = totalRequiredLovelace + minAdaForChange + actualFeeLovelace;
                        shortfall = actualRequiredLovelace - totalLovelace;
                        
                        let recipientAdaAmount = 0;
                        const adaLine = this.transactionLines.find(line => 
                            line.Asset__c === 'ADA' || line.Asset__c === 'lovelace'
                        );
                        if (adaLine) {
                            recipientAdaAmount = parseFloat(adaLine.Amount__c || 0);
                        }
                        
                        const availableAda = (totalLovelace / 1000000).toFixed(6);
                        const recipientAda = recipientAdaAmount.toFixed(6);
                        const minChangeAda = (minAdaForChange / 1000000).toFixed(6);
                        const feeAda = (actualFeeLovelace / 1000000).toFixed(6);
                        const totalRequiredAda = (actualRequiredLovelace / 1000000).toFixed(6);
                        const shortfallAda = (shortfall / 1000000).toFixed(6);
                        
                        errorMessage = `Insufficient ADA for multi-asset change: You have ${availableAda} ADA but need approximately ${totalRequiredAda} ADA (${recipientAda} ADA for recipient + ${minChangeAda} ADA minimum for change with tokens + ${feeAda} ADA fees). Add at least ${shortfallAda} ADA to your wallet.`;
                    } else if (errorMessage.includes('UTxO Balance Insufficient') || errorMessage.includes('insufficient')) {
                        const mockOutputValue = this.cardanoLib.Value.new(this.cardanoLib.BigNum.from_str('0'));
                        
                        const nonLovelaceAssets = this.transactionLines.filter(line => 
                            line.Asset__c && line.Asset__c !== 'ADA' && line.Asset__c !== 'lovelace'
                        );
                        
                        if (nonLovelaceAssets.length > 0) {
                            const mockMultiAsset = this.cardanoLib.MultiAsset.new();
                            
                            for (const line of nonLovelaceAssets) {
                                const assetUnit = line.Asset__c;
                                
                                if (assetUnit && assetUnit.length >= 56 && /^[0-9a-fA-F]+$/.test(assetUnit)) {
                                    const policyIdHex = assetUnit.substring(0, 56);
                                    const assetNameHex = assetUnit.substring(56);
                                    
                                    try {
                                        const policyId = this.cardanoLib.ScriptHash.from_hex(policyIdHex);
                                        const assetName = this.cardanoLib.AssetName.new(this.hexToBytes(assetNameHex));
                                        const assets = this.cardanoLib.Assets.new();
                                        assets.insert(assetName, this.cardanoLib.BigNum.from_str('1'));
                                        mockMultiAsset.insert(policyId, assets);
                                    } catch (assetError) {
                                        // Skip invalid assets
                                    }
                                }
                            }
                            
                            if (mockMultiAsset.len() > 0) {
                                mockOutputValue.set_multiasset(mockMultiAsset);
                            }
                        }
                        
                        minAdaForOutput = this.calculateMinimumADA(mockOutputValue, parseInt(protocolParams.min_utxo_value || 1000000));
                        const actualFee = txBuilder.min_fee();
                        actualFeeLovelace = parseInt(actualFee.to_str());
                        
                        actualRequiredLovelace = totalRequiredLovelace + minAdaForOutput + actualFeeLovelace;
                        shortfall = actualRequiredLovelace - totalLovelace;
                        
                        let recipientAdaAmount = 0;
                        const adaLine = this.transactionLines.find(line => 
                            line.Asset__c === 'ADA' || line.Asset__c === 'lovelace'
                        );
                        if (adaLine) {
                            recipientAdaAmount = parseFloat(adaLine.Amount__c || 0);
                        }
                        
                        const availableAda = (totalLovelace / 1000000).toFixed(6);
                        const recipientAda = recipientAdaAmount.toFixed(6);
                        const minUtxoAda = (minAdaForOutput / 1000000).toFixed(6);
                        const feeAda = (actualFeeLovelace / 1000000).toFixed(6);
                        const totalRequiredAda = (actualRequiredLovelace / 1000000).toFixed(6);
                        const shortfallAda = (shortfall / 1000000).toFixed(6);
                        
                        errorMessage = `Insufficient ADA: You have ${availableAda} ADA but need approximately ${totalRequiredAda} ADA (${recipientAda} ADA for recipient + ${minUtxoAda} ADA minimum UTXO + ${feeAda} ADA fees). Add at least ${shortfallAda} ADA to your wallet.`;
                    }
                    
                    throw new CardanoTransactionError(errorMessage, 'INSUFFICIENT_FUNDS', {
                        available: (totalLovelace / 1000000).toFixed(6),
                        required: (actualRequiredLovelace / 1000000).toFixed(6),
                        shortfall: (shortfall / 1000000).toFixed(6),
                        breakdown: {
                            recipient: (totalRequiredLovelace / 1000000).toFixed(6),
                            minUtxo: (minAdaForOutput / 1000000).toFixed(6),
                            fees: (actualFeeLovelace / 1000000).toFixed(6)
                        }
                    });
                }

                const txBody = txBuilder.build();
                const actualInputs = txBody.inputs();
                
                const txBodyBytes = txBody.to_bytes();
                const hash = new this.blakeLib(32).update(txBodyBytes).digest();
                const txHash = this.cardanoLib.TransactionHash.from_bytes(hash);
                
                if (!txHash || typeof txHash.to_bytes !== 'function') {
                    throw new Error(`Failed to create valid transaction hash object. Type: ${typeof txHash}, Constructor: ${txHash ? txHash.constructor.name : 'N/A'}`);
                }

                const witnessSet = this.createWitnesses(actualInputs, inputUtxosDetails, walletData, txHash);

                let finalAuxData = null;
                try {
                    if (txBody.auxiliary_data && typeof txBody.auxiliary_data === 'function') {
                        finalAuxData = txBody.auxiliary_data();
                    } else {
                        finalAuxData = auxData;
                    }
                } catch (auxError) {
                    finalAuxData = auxData;
                }
                
                const signedTx = this.cardanoLib.Transaction.new(
                    txBody,
                    witnessSet,
                    finalAuxData
                );
                
                const signedBytes = signedTx.to_bytes();
                const signedCborHex = this.bytesToHex(signedBytes);

                try {
                    await updateOutboundTransactionWithSignedCbor({
                        recordId: this.recordId,
                        signedCbor: signedCborHex
                    });
                    this.showToast('Success', 'Transaction signed and updated successfully!', 'success');
                    this.isLoading = false;
                    this.dispatchEvent(new CustomEvent('transactionSigned'));
                } catch (updateError) {
                    let apexMsg = updateError && updateError.body && updateError.body.message
                        ? updateError.body.message
                        : (updateError.message || JSON.stringify(updateError));
                    this.showToast('Error', `Failed to update outbound transaction: ${apexMsg}`, 'error');
                    this.isLoading = false;
                }

            } catch (error) {
                let userMessage = error.message;
                
                if (error instanceof CardanoTransactionError) {
                    switch (error.code) {
                        case 'ASSET_NOT_FOUND':
                            userMessage = error.message;
                            break;
                        case 'INSUFFICIENT_FUNDS':
                            userMessage = error.message;
                            break;
                        case 'INVALID_ADDRESS':
                            userMessage = `Invalid recipient address: ${error.details.address}. Please check the address format.`;
                            break;

                        default:
                            userMessage = `Transaction error: ${error.message}`;
                    }
                } else if (error.message.includes('Asset') && error.message.includes('not found')) {
                    userMessage = `Asset not found in wallet. Please check the asset name or ensure the asset is available in your wallet.`;
                } else if (error.message.includes('insufficient') || error.message.includes('Insufficient')) {
                    userMessage = `Insufficient funds: ${error.message}`;
                } else if (error.message.includes('UTxO Balance Insufficient')) {
                    userMessage = `Insufficient ADA in wallet to create transaction. Please add more ADA to cover the transaction amount, fees, and minimum UTXO requirements.`;
                }
                
                                this.showToast('Error', `Failed to build transaction: ${userMessage}`, 'error');
                this.isLoading = false;
            }
        } catch (error) {
            let userMessage = error.message;
            
            if (error.message.includes('No transaction lines found')) {
                userMessage = 'No transaction lines found. Please add at least one asset to send.';
            } else if (error.message.includes('Recipient address is required')) {
                userMessage = 'Recipient address is required. Please set a valid Cardano address.';
            } else if (error.message.includes('Failed to fetch transaction lines')) {
                userMessage = 'Failed to load transaction details. Please try again or contact support.';
            } else if (error.message.includes('Failed to load wallet')) {
                userMessage = 'Failed to load wallet data. Please check your wallet configuration.';
            } else if (error.message.includes('Failed to fetch epoch parameters')) {
                userMessage = 'Failed to connect to Cardano network. Please check your internet connection and try again.';
            }
            
            this.showToast('Error', `Failed to prepare transaction: ${userMessage}`, 'error');
            this.isLoading = false;
        }
    }

    async fetchTransactionLines() {
        try {
            const lines = await getTransactionLinesForOutbound({ outboundTransactionId: this.recordId });

            // Normalize field names to work with/without namespace
            const ASSET_API  = OTL_ASSET_FIELD.fieldApiName;
            const AMOUNT_API = OTL_AMOUNT_FIELD.fieldApiName;

            this.transactionLines = (lines || []).map(rec => ({
                Asset__c  : rec[ASSET_API],
                Amount__c : rec[AMOUNT_API]
            }));
            
            if (!this.transactionLines || this.transactionLines.length === 0) {
                throw new Error('No transaction lines found. Please add at least one asset to send.');
            }
            
            const invalidLines = this.transactionLines.filter(line => 
                !line.Asset__c || !line.Amount__c || parseFloat(line.Amount__c) <= 0
            );
            
            if (invalidLines.length > 0) {
                const invalidAssets = invalidLines.map(line => line.Asset__c || 'Unknown').join(', ');
                throw new Error(`Invalid transaction lines found for assets: ${invalidAssets}. Please check asset names and amounts.`);
            }
            
        } catch (error) {
            let userMessage = error.message;
            if (error.message.includes('No transaction lines found')) {
                userMessage = 'No assets found to send. Please add at least one asset to the transaction.';
            } else if (error.message.includes('Invalid transaction lines')) {
                userMessage = error.message;
            } else {
                userMessage = 'Failed to load transaction details. Please try again or contact support.';
            }
            
            this.showToast('Error', `Failed to fetch transaction lines: ${userMessage}`, 'error');
            throw error;
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissible'
        });
        this.dispatchEvent(event);
    }

    getAllAvailableAssets(walletData) {
        const assets = new Set();
        
        assets.add('ADA');
        assets.add('lovelace');
        
        if (walletData.walletSummary && walletData.walletSummary.totalBalance && walletData.walletSummary.totalBalance.assets) {
            walletData.walletSummary.totalBalance.assets.forEach(asset => {
                if (asset.ticker) {
                    assets.add(asset.ticker);
                }
                if (asset.assetName) {
                    assets.add(asset.assetName);
                }
                if (asset.unit && asset.unit !== 'lovelace') {
                    assets.add(asset.unit);
                }
            });
        }
        
        const allAddresses = [
            ...(walletData.receivingAddresses || []),
            ...(walletData.changeAddresses || [])
        ];
        
        allAddresses.forEach((addr) => {
            if (addr.utxos) {
                addr.utxos.forEach(utxo => {
                    if (utxo.amount) {
                        utxo.amount.forEach(amount => {
                            if (amount.unit && amount.unit !== 'lovelace') {
                                assets.add(amount.unit);
                            }
                        });
                    }
                });
            }
        });
        
        return Array.from(assets).sort();
    }

    findAssetInfo(walletData, ticker, unit) {
        if (!walletData.walletSummary || !walletData.walletSummary.totalBalance || !walletData.walletSummary.totalBalance.assets) {
            return null;
        }
        
        const assets = walletData.walletSummary.totalBalance.assets;
        
        let assetInfo = assets.find(asset => asset.unit === unit);
        if (assetInfo) {
            return assetInfo;
        }
        
        assetInfo = assets.find(asset => asset.ticker && asset.ticker.toLowerCase() === ticker.toLowerCase());
        if (assetInfo) {
            return assetInfo;
        }
        
        assetInfo = assets.find(asset => asset.assetName && asset.assetName.toLowerCase() === ticker.toLowerCase());
        if (assetInfo) {
            return assetInfo;
        }
        
        assetInfo = assets.find(asset => 
            (asset.ticker && asset.ticker.toLowerCase().includes(ticker.toLowerCase())) ||
            (asset.assetName && asset.assetName.toLowerCase().includes(ticker.toLowerCase()))
        );
        if (assetInfo) {
            return assetInfo;
        }
        
        return null;
    }

    get isSent() {
        return this.outboundTransaction &&
            this.outboundTransaction.Transaction_Status__c === 'Sent' &&
            this.outboundTransaction.Transaction_Hash__c;
    }

    get notSent() {
        return !this.isSent;
    }

    get transactionHash() {
        return this.outboundTransaction ? this.outboundTransaction.Transaction_Hash__c : '';
    }

    get cardanoScanUrl() {
        return this.transactionHash
            ? `https://cardanoscan.io/transaction/${this.transactionHash}`
            : '';
    }
}