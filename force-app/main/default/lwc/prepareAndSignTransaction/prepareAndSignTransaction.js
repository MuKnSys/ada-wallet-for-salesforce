import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import CARDANO_SERIALIZATION from '@salesforce/resourceUrl/cardanoSerialization';
import BIP39 from '@salesforce/resourceUrl/bip39';
import BLAKE from '@salesforce/resourceUrl/blake';
import getEpochParameters from '@salesforce/apex/BlockfrostService.getEpochParameters';
import getTransactionLinesForOutbound from '@salesforce/apex/UTXOController.getTransactionLinesForOutbound';
import getOutboundTransaction from '@salesforce/apex/UTXOController.getOutboundTransaction';
import loadWallet from '@salesforce/apex/TransactionController.loadWallet';
import updateOutboundTransactionWithSignedCbor from '@salesforce/apex/UTXOController.updateOutboundTransactionWithSignedCbor';

// Enhanced error handling class
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
    @track tokens = [];
    @track epochParameters = null;

    // Cardano library references
    cardanoLib = null;
    blakeLib = null;

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
            // Load required libraries using static imports
            const scripts = [
                { name: 'cardanoSerialization', url: `${CARDANO_SERIALIZATION}/cardanoSerialization/bundle.js` },
                { name: 'bip39', url: BIP39 },
                { name: 'blake', url: BLAKE }
            ];
            
            for (const script of scripts) {
                await loadScript(this, script.url);
            }
            
            // Verify that libraries are available on window object
            if (!window.cardanoSerialization) {
                throw new Error('Cardano serialization library not found on window object');
            }
            if (!window.bip39) {
                throw new Error('BIP39 library not found on window object');
            }
            
            // Store reference to Cardano library
            this.cardanoLib = window.cardanoSerialization;
            this.blakeLib = window.Blake2b;
            
            if (!this.cardanoLib) {
                throw new Error('Cardano serialization library is null or undefined');
            }
            
            // Test key CSL objects
            const testObjects = [
                'Bip32PrivateKey',
                'TransactionHash',
                'PrivateKey',
                'PublicKey',
                'Vkeywitnesses',
                'TransactionWitnessSet'
            ];
            
            for (const objName of testObjects) {
                if (!this.cardanoLib[objName]) {
                    throw new Error(`CSL library missing required object: ${objName}`);
                }
            }
            
            this.librariesLoaded = true;
            console.log('[loadLibraries] All libraries loaded successfully');
            
        } catch (error) {
            console.error('[loadLibraries] Error loading libraries:', error);
            this.showToast('Error', 'Failed to load required libraries: ' + error.message, 'error');
        } finally {
            this.isLoadingLibraries = false;
        }
    }

    // Input validation utilities
    validateAddress(address) {
        try {
            this.cardanoLib.Address.from_bech32(address);
            return true;
        } catch (error) {
            throw new CardanoTransactionError(`Invalid address format: ${address}`, 'INVALID_ADDRESS', { address });
        }
    }

    validateAmount(amount, assetName = 'ADA') {
        if (typeof amount !== 'number' || amount <= 0) {
            throw new CardanoTransactionError(`Invalid ${assetName} amount: ${amount}`, 'INVALID_AMOUNT', { amount, assetName });
        }
        return true;
    }

    validateAssetUnit(unit) {
        if (unit === 'lovelace') return true;
        if (typeof unit === 'string' && unit.length >= 56) return true;
        throw new CardanoTransactionError(`Invalid asset unit: ${unit}`, 'INVALID_ASSET_UNIT', { unit });
    }

    // Enhanced UTXO collection with validation
    collectAndValidateUTXOs(walletData) {
        const utxos = this.cardanoLib.TransactionUnspentOutputs.new();
        const inputUtxosDetails = [];
        let totalLovelace = 0;
        let totalAssets = new Map();

        console.log('\n[UTXOS] === DETAILED UTXO COLLECTION ===');
        console.log(`[UTXOS] Processing ${walletData.receivingAddresses.length} receiving addresses`);
        console.log(`[UTXOS] Processing ${walletData.changeAddresses.length} change addresses`);

        // Collect UTXOs from receiving addresses
        for (const address of walletData.receivingAddresses) {
            console.log(`[UTXOS] Processing receiving address: ${address.address}`);
            console.log(`[UTXOS]   UTXOs count: ${address.utxos ? address.utxos.length : 0}`);
            
            for (const utxo of address.utxos || []) {
                const utxoData = this.processUTXO(utxo, address);
                if (utxoData) {
                    utxos.add(utxoData.cslUtxo);
                    inputUtxosDetails.push(utxoData.details);
                    totalLovelace += utxoData.details.lovelace;
                    this.updateAssetTotals(totalAssets, utxoData.details.assets);
                    
                    console.log(`[UTXOS]   ✅ UTXO ${utxoData.details.txHash}:${utxoData.details.txIndex}`);
                    console.log(`[UTXOS]     Lovelace: ${utxoData.details.lovelace}`);
                    console.log(`[UTXOS]     Assets: ${utxoData.details.assets.length}`);
                    for (const asset of utxoData.details.assets) {
                        if (asset.unit !== 'lovelace') {
                            console.log(`[UTXOS]       ${asset.unit}: ${asset.quantity}`);
                        }
                    }
                }
            }
        }

        // Collect UTXOs from change addresses
        for (const address of walletData.changeAddresses) {
            console.log(`[UTXOS] Processing change address: ${address.address}`);
            console.log(`[UTXOS]   UTXOs count: ${address.utxos ? address.utxos.length : 0}`);
            
            for (const utxo of address.utxos || []) {
                const utxoData = this.processUTXO(utxo, address);
                if (utxoData) {
                    utxos.add(utxoData.cslUtxo);
                    inputUtxosDetails.push(utxoData.details);
                    totalLovelace += utxoData.details.lovelace;
                    this.updateAssetTotals(totalAssets, utxoData.details.assets);
                    
                    console.log(`[UTXOS]   ✅ UTXO ${utxoData.details.txHash}:${utxoData.details.txIndex}`);
                    console.log(`[UTXOS]     Lovelace: ${utxoData.details.lovelace}`);
                    console.log(`[UTXOS]     Assets: ${utxoData.details.assets.length}`);
                    for (const asset of utxoData.details.assets) {
                        if (asset.unit !== 'lovelace') {
                            console.log(`[UTXOS]       ${asset.unit}: ${asset.quantity}`);
                        }
                    }
                }
            }
        }

        console.log(`\n[UTXOS] === UTXO COLLECTION SUMMARY ===`);
        console.log(`[UTXOS] Total UTXOs collected: ${inputUtxosDetails.length}`);
        console.log(`[UTXOS] Total lovelace: ${totalLovelace} (${(totalLovelace / 1000000).toFixed(6)} ADA)`);
        console.log(`[UTXOS] Total unique assets: ${totalAssets.size}`);
        
        // Show detailed asset breakdown
        for (const [unit, amount] of totalAssets) {
            console.log(`[UTXOS] Asset ${unit}: ${amount} raw units`);
        }
        
        console.log(`[UTXOS] === END UTXO COLLECTION SUMMARY ===\n`);

        return { utxos, inputUtxosDetails, totalLovelace, totalAssets };
    }

    processUTXO(utxo, address) {
        try {
            // Validate UTXO structure
            if (!utxo.tx_hash || typeof utxo.tx_index !== 'number' || !utxo.amount) {
                console.warn(`[WARNING] Skipping invalid UTXO: ${JSON.stringify(utxo)}`);
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
                    this.validateAssetUnit(asset.unit);
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
            console.warn(`[WARNING] Failed to process UTXO ${utxo.tx_hash}:${utxo.tx_index}: ${error.message}`);
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

    // Enhanced asset conversion with validation
    convertAssetsToOutputs(outputs, walletData) {
        const multiAsset = this.cardanoLib.MultiAsset.new();
        const outputValue = this.cardanoLib.Value.new(this.cardanoLib.BigNum.from_str('0'));
        const sentAssets = [];
        let totalLovelace = 0;

        console.log('  [ASSET CONVERSION]');
        
        for (const output of outputs) {
            if (output.unit === 'lovelace') {
                const lovelaceAmount = Math.floor(output.amount * 1000000);
                this.validateAmount(lovelaceAmount, 'lovelace');
                const standardizedAmount = output.amount;
                console.log(`    ${output.ticker}: ${output.amount} ADA → ${lovelaceAmount} lovelace`);
                totalLovelace += lovelaceAmount;
                sentAssets.push({
                    unit: 'lovelace',
                    ticker: output.ticker,
                    quantity: lovelaceAmount.toString(),
                    policyId: null,
                    assetName: null,
                    decimals: 6,
                    standardizedAmount: standardizedAmount
                });
            } else {
                this.validateAssetUnit(output.unit);
                const assetInfo = walletData.walletSummary.totalBalance.assets.find(
                    asset => asset.unit === output.unit
                );
                
                if (!assetInfo) {
                    throw new CardanoTransactionError(`Asset ${output.ticker} not found in wallet cache`, 'ASSET_NOT_FOUND', { asset: output.ticker });
                }

                const decimals = assetInfo.decimals || 0;
                const convertedAmount = Math.floor(output.amount * Math.pow(10, decimals));
                this.validateAmount(convertedAmount, output.ticker);
                
                const standardizedAmount = output.amount;
                console.log(`    ${output.ticker}: ${output.amount} whole units → ${convertedAmount} (${decimals} decimals)`);
                
                const policyIdHex = output.unit.slice(0, 56);
                const assetNameHex = output.unit.slice(56);
                const policyId = this.cardanoLib.ScriptHash.from_bytes(this.hexToBytes(policyIdHex));
                const assetName = this.cardanoLib.AssetName.new(this.hexToBytes(assetNameHex));
                const assets = this.cardanoLib.Assets.new();
                assets.insert(assetName, this.cardanoLib.BigNum.from_str(convertedAmount.toString()));
                multiAsset.insert(policyId, assets);
                
                sentAssets.push({
                    unit: output.unit,
                    ticker: output.ticker,
                    quantity: convertedAmount.toString(),
                    policyId: policyIdHex,
                    assetName: this.hexToString(assetNameHex),
                    decimals: decimals,
                    standardizedAmount: standardizedAmount
                });
            }
        }

        outputValue.set_coin(this.cardanoLib.BigNum.from_str(totalLovelace.toString()));
        if (multiAsset.len() > 0) {
            outputValue.set_multiasset(multiAsset);
        }

        return { outputValue, sentAssets };
    }

    // Enhanced minimum ADA calculation using official Cardano specification
    calculateMinimumADA(outputValue, protocolParams) {
        // Constants from Cardano specification
        const minUTxOValue = parseInt(protocolParams.min_utxo_value || 1000000); // 1 ADA in lovelace
        const utxoEntrySizeWithoutVal = 27;
        const coinSize = 0; // Note: this will change to 2 in next fork
        const adaOnlyUTxOSize = utxoEntrySizeWithoutVal + coinSize; // 27
        
        console.log(`[calculateMinimumADA] Using Cardano specification constants:`);
        console.log(`  - minUTxOValue: ${minUTxOValue} lovelace (${minUTxOValue / 1000000} ADA)`);
        console.log(`  - utxoEntrySizeWithoutVal: ${utxoEntrySizeWithoutVal}`);
        console.log(`  - coinSize: ${coinSize}`);
        console.log(`  - adaOnlyUTxOSize: ${adaOnlyUTxOSize}`);
        
        // Case 1: ADA-only UTXO
        if (!outputValue.multiasset() || outputValue.multiasset().len() === 0) {
            const minAda = minUTxOValue;
            console.log(`[calculateMinimumADA] ADA-only UTXO: minAda = ${minAda} lovelace (${minAda / 1000000} ADA)`);
            return minAda;
        }
        
        // Case 2: Multi-asset UTXO
        console.log(`[calculateMinimumADA] Multi-asset UTXO detected, calculating size...`);
        
        const multiAsset = outputValue.multiasset();
        const policies = multiAsset.keys();
        const numPIDs = policies.len();
        
        // Calculate token bundle size
        let numAssets = 0;
        let sumAssetNameLengths = 0;
        
        for (let i = 0; i < policies.len(); i++) {
            const policy = policies.get(i);
            const assets = multiAsset.get(policy);
            numAssets += assets.len();
            
            // Calculate sum of asset name lengths
            const assetNames = assets.keys();
            for (let j = 0; j < assetNames.len(); j++) {
                const assetName = assetNames.get(j);
                const assetNameBytes = assetName.name();
                sumAssetNameLengths += assetNameBytes.length;
            }
        }
        
        const pidSize = 28; // Policy ID size (28 bytes)
        
        // Calculate size B using the Cardano formula
        // size B = 6 + roundupBytesToWords (((numAssets B) * 12) + (sumAssetNameLengths B) + ((numPids B) * pidSize))
        const roundupBytesToWords = (bytes) => Math.floor((bytes + 7) / 8);
        const sizeB = 6 + roundupBytesToWords((numAssets * 12) + sumAssetNameLengths + (numPIDs * pidSize));
        
        console.log(`[calculateMinimumADA] Token bundle analysis:`);
        console.log(`  - numAssets: ${numAssets}`);
        console.log(`  - numPIDs: ${numPIDs}`);
        console.log(`  - sumAssetNameLengths: ${sumAssetNameLengths} bytes`);
        console.log(`  - pidSize: ${pidSize} bytes`);
        console.log(`  - size B: ${sizeB} words`);
        
        // Calculate minAda using the Cardano formula
        // minAda (u) = max (minUTxOValue, (quot (minUTxOValue, adaOnlyUTxOSize)) * (utxoEntrySizeWithoutVal + (size B)))
        const quot = (a, b) => Math.floor(a / b);
        const minAda = Math.max(
            minUTxOValue,
            quot(minUTxOValue, adaOnlyUTxOSize) * (utxoEntrySizeWithoutVal + sizeB)
        );
        
        console.log(`[calculateMinimumADA] Multi-asset calculation:`);
        console.log(`  - quot(minUTxOValue, adaOnlyUTxOSize): ${quot(minUTxOValue, adaOnlyUTxOSize)}`);
        console.log(`  - utxoEntrySizeWithoutVal + sizeB: ${utxoEntrySizeWithoutVal + sizeB}`);
        console.log(`  - minAda: ${minAda} lovelace (${minAda / 1000000} ADA)`);
        
        return minAda;
    }

    // Enhanced witness creation with robust key verification
    createWitnesses(actualInputs, inputUtxosDetails, walletData, txHash) {
        const witnessSet = this.cardanoLib.TransactionWitnessSet.new();
        const vkeyWitnesses = this.cardanoLib.Vkeywitnesses.new();
        let witnessCount = 0;

        console.log('\n[DEBUG] Transaction inputs analysis:');
        console.log(`[DEBUG] Total inputs: ${actualInputs.len()}`);

        // Build address to key mapping with private keys
        const addressToKeyInfo = new Map();
        
        // Add all wallet addresses to the mapping with their private keys
        if (walletData.receivingAddresses && walletData.receivingAddresses.length > 0) {
            for (const addr of walletData.receivingAddresses) {
                // Handle both 'privateKey' and 'xpriv' field names
                const privateKey = addr.privateKey || addr.xpriv;
                console.log(`[createWitnesses] Adding receiving address: ${addr.address} with private key: ${privateKey ? 'YES' : 'NO'}`);
                addressToKeyInfo.set(addr.address, { 
                    paymentKeyHash: addr.paymentKeyHash,
                    keyMatch: addr.keyMatch,
                    privateKey: privateKey // xpriv format
                });
            }
        }
        
        if (walletData.changeAddresses && walletData.changeAddresses.length > 0) {
            for (const addr of walletData.changeAddresses) {
                // Handle both 'privateKey' and 'xpriv' field names
                const privateKey = addr.privateKey || addr.xpriv;
                console.log(`[createWitnesses] Adding change address: ${addr.address} with private key: ${privateKey ? 'YES' : 'NO'}`);
                addressToKeyInfo.set(addr.address, { 
                    paymentKeyHash: addr.paymentKeyHash,
                    keyMatch: addr.keyMatch,
                    privateKey: privateKey // xpriv format
                });
            }
        }

        // Log all addresses in the wallet for debugging
        console.log(`[createWitnesses] Wallet addresses available for signing:`, {
            receivingAddresses: walletData.receivingAddresses?.map(addr => addr.address) || [],
            changeAddresses: walletData.changeAddresses?.map(addr => addr.address) || [],
            totalAddresses: addressToKeyInfo.size,
            allAddresses: Array.from(addressToKeyInfo.keys())
        });

        for (let i = 0; i < actualInputs.len(); i++) {
            const input = actualInputs.get(i);
            const txHashHex = this.bytesToHex(input.transaction_id().to_bytes());
            const txIndex = input.index();
            
            console.log(`\n[DEBUG] Input ${i}:`);
            console.log(`  TX Hash: ${txHashHex}`);
            console.log(`  TX Index: ${txIndex}`);
            
            const inputUtxo = inputUtxosDetails.find(utxo => 
                utxo.txHash === txHashHex && utxo.txIndex === txIndex
            );
            
            if (!inputUtxo) {
                throw new CardanoTransactionError(`No UTXO details found for input ${i}`, 'UTXO_NOT_FOUND', { inputIndex: i, txHash: txHashHex, txIndex });
            }

            console.log(`  Address: ${inputUtxo.address}`);
            console.log(`  UTXO Payment Key Hash: ${inputUtxo.paymentKeyHash}`);
            
            const keyInfo = addressToKeyInfo.get(inputUtxo.address);
            if (!keyInfo) {
                console.error(`[createWitnesses] Address not found in wallet: ${inputUtxo.address}`);
                console.error(`[createWitnesses] Available addresses:`, Array.from(addressToKeyInfo.keys()));
                throw new CardanoTransactionError(`No key info found for address ${inputUtxo.address}`, 'KEY_NOT_FOUND', { address: inputUtxo.address });
            }

            // Convert xpriv to raw private key for signing
            let rawKey = null;
            try {
                if (!keyInfo.privateKey) {
                    throw new CardanoTransactionError(`No private key found for address ${inputUtxo.address}`, 'PRIVATE_KEY_NOT_FOUND', { address: inputUtxo.address });
                }

                console.log(`[createWitnesses] Converting xpriv to raw private key for address: ${inputUtxo.address}`);
                
                // Convert xpriv (BIP32 extended private key) to raw private key
                const bip32PrivateKey = this.cardanoLib.Bip32PrivateKey.from_bech32(keyInfo.privateKey);
                rawKey = bip32PrivateKey.to_raw_key();
                
                console.log(`[createWitnesses] Successfully converted xpriv to raw private key for address: ${inputUtxo.address}`);
                
            } catch (e) {
                console.error(`[createWitnesses] Error converting private key for address ${inputUtxo.address}:`, e.message);
                throw new CardanoTransactionError(`Failed to retrieve signing key for address ${inputUtxo.address}`, 'SIGNING_VERIFICATION_ERROR', { address: inputUtxo.address, error: e.message });
            }

            const witness = this.cardanoLib.make_vkey_witness(txHash, rawKey);
            vkeyWitnesses.add(witness);
            witnessCount++;
            
            console.log(`[createWitnesses] Created witness ${witnessCount} for address: ${inputUtxo.address}`);
        }

        witnessSet.set_vkeys(vkeyWitnesses);
        console.log(`[STEP 13] Created ${witnessCount} vkey witnesses for ${actualInputs.len()} transaction inputs.`);
        
        return witnessSet;
    }

    // Utility functions for hex/bytes conversion
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

    /**
     * Load wallet data from Salesforce
     */
    async loadWalletData(walletId) {
        try {
            console.log(`[loadWalletData] Starting wallet load for walletId: ${walletId}`);
            
            // Get complete wallet data from Apex
            const walletData = await loadWallet({ walletId: walletId });
            
            console.log(`[loadWalletData] Wallet data received from Apex:`, {
                hasReceivingAddresses: !!walletData.receivingAddresses,
                hasChangeAddresses: !!walletData.changeAddresses,
                hasWalletSummary: !!walletData.walletSummary,
                receivingAddressesLength: walletData.receivingAddresses?.length || 0,
                changeAddressesLength: walletData.changeAddresses?.length || 0
            });
            
            return walletData;
        } catch (error) {
            console.error(`[loadWalletData] Error loading wallet:`, error);
            this.showToast('Error', `Failed to load wallet: ${error.message}`, 'error');
            throw error;
        }
    }

    /**
     * Fetch epoch parameters from Blockfrost
     */
    async fetchEpochParameters() {
        try {
            console.log('[fetchEpochParameters] Fetching epoch parameters from Blockfrost...');
            const paramsJson = await getEpochParameters();
            this.epochParameters = JSON.parse(paramsJson);
            
            console.log('[fetchEpochParameters] Epoch parameters loaded successfully:', JSON.stringify(this.epochParameters, null, 2));
            
            return this.epochParameters;
        } catch (error) {
            console.error('[fetchEpochParameters] Error fetching epoch parameters:', error);
            this.showToast('Error', `Failed to fetch epoch parameters: ${error.message}`, 'error');
            throw error;
        }
    }

    /**
     * Build and sign transaction method (called from HTML template)
     */
    async buildAndSignTransaction() {
        this.isLoading = true;
        try {
            // Fetch Outbound_Transaction__c record directly
            let outboundTransactionRecord = null;
            let toAddress = null;
            try {
                outboundTransactionRecord = await getOutboundTransaction({ outboundTransactionId: this.recordId });
                toAddress = outboundTransactionRecord && outboundTransactionRecord.To_Address__c ? outboundTransactionRecord.To_Address__c : null;
            } catch (e) {
                this.showToast('Error', 'Failed to fetch transaction details', 'error');
                return;
            }

            // Validate that we have a toAddress
            if (!toAddress) {
                this.showToast('Error', 'Recipient address is required but not found in transaction record', 'error');
                return;
            }

            try {
                await this.fetchTransactionLines();
                // Validate that we have transaction lines
                if (!this.transactionLines || this.transactionLines.length === 0) {
                    this.showToast('Error', 'No transaction lines found for this transaction', 'error');
                    return;
                }
            } catch (fetchError) {
                this.showToast('Error', 'Failed to fetch transaction lines: ' + (fetchError.message || 'Unknown error'), 'error');
                return;
            }

            try {
                // Load wallet data and epoch parameters
                const walletData = await this.loadWalletData(outboundTransactionRecord.Wallet__c);
                const protocolParams = await this.fetchEpochParameters();
                
                console.log(`[buildAndSignTransaction] === STARTING TRANSACTION BUILD ===`);
                console.log(`[buildAndSignTransaction] Transaction ID: ${this.recordId}`);
                console.log(`[buildAndSignTransaction] Recipient Address: ${toAddress}`);
                console.log(`[buildAndSignTransaction] Wallet ID: ${outboundTransactionRecord.Wallet__c}`);
                console.log(`[buildAndSignTransaction] Transaction Lines Count: ${this.transactionLines.length}`);
                
                // Log network epoch parameters for transaction building
                console.log('\n[NETWORK PARAMS] === NETWORK EPOCH PARAMETERS ===');
                console.log(`[NETWORK PARAMS] Epoch: ${protocolParams.epoch || 'N/A'}`);
                console.log(`[NETWORK PARAMS] min_fee_a: ${protocolParams.min_fee_a}`);
                console.log(`[NETWORK PARAMS] min_fee_b: ${protocolParams.min_fee_b}`);
                console.log(`[NETWORK PARAMS] pool_deposit: ${protocolParams.pool_deposit}`);
                console.log(`[NETWORK PARAMS] key_deposit: ${protocolParams.key_deposit}`);
                console.log(`[NETWORK PARAMS] max_val_size: ${protocolParams.max_val_size}`);
                console.log(`[NETWORK PARAMS] max_tx_size: ${protocolParams.max_tx_size}`);
                console.log(`[NETWORK PARAMS] coins_per_utxo_word: ${protocolParams.coins_per_utxo_word}`);
                console.log(`[NETWORK PARAMS] protocol_major: ${protocolParams.protocol_major || 'N/A'}`);
                console.log(`[NETWORK PARAMS] protocol_minor: ${protocolParams.protocol_minor || 'N/A'}`);
                console.log(`[NETWORK PARAMS] min_utxo: ${protocolParams.min_utxo || 'N/A'}`);
                console.log(`[NETWORK PARAMS] max_collateral_inputs: ${protocolParams.max_collateral_inputs || 'N/A'}`);
                console.log(`[NETWORK PARAMS] max_block_size: ${protocolParams.max_block_size || 'N/A'}`);
                console.log(`[NETWORK PARAMS] max_block_header_size: ${protocolParams.max_block_header_size || 'N/A'}`);
                console.log(`[NETWORK PARAMS] max_tx_ex_units: ${JSON.stringify(protocolParams.max_tx_ex_units || 'N/A')}`);
                console.log(`[NETWORK PARAMS] max_block_ex_units: ${JSON.stringify(protocolParams.max_block_ex_units || 'N/A')}`);
                console.log(`[NETWORK PARAMS] cost_models: ${JSON.stringify(protocolParams.cost_models || 'N/A')}`);
                console.log(`[NETWORK PARAMS] price_mem: ${protocolParams.price_mem || 'N/A'}`);
                console.log(`[NETWORK PARAMS] price_step: ${protocolParams.price_step || 'N/A'}`);
                console.log(`[NETWORK PARAMS] max_tx_ex_units: ${JSON.stringify(protocolParams.max_tx_ex_units || 'N/A')}`);
                console.log(`[NETWORK PARAMS] max_block_ex_units: ${JSON.stringify(protocolParams.max_block_ex_units || 'N/A')}`);
                console.log(`[NETWORK PARAMS] === END NETWORK PARAMETERS ===\n`);
                
                // Initialize protocol parameters from Blockfrost data
                console.log('\n[STEP 3] Initializing TransactionBuilder with protocol parameters...');
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
                console.log('[STEP 3] TransactionBuilder initialized with Blockfrost parameters.');

                // Convert transaction lines to outputs format
                const outputs = this.transactionLines.map(line => {
                    // ADA normalization
                    if (line.Asset__c && (line.Asset__c.toLowerCase() === 'ada' || line.Asset__c === 'lovelace')) {
                        return {
                            unit: 'lovelace',
                            amount: parseFloat(line.Amount__c || 0),
                            ticker: 'ADA'
                        };
                    }
                    // For tokens, find the correct unit from wallet assets by ticker or asset name
                    let tokenUnit = line.Asset__c;
                    if (line.Asset__c && line.Asset__c !== 'lovelace' && line.Asset__c.toLowerCase() !== 'ada') {
                        // Try to find by ticker or asset name
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
                        ticker: line.Ticker__c || line.Asset__c
                    };
                });

                console.log('\n[STEP 4] === TRANSACTION OUTPUTS ANALYSIS ===');
                console.log('[STEP 4] Transaction lines converted to outputs:');
                console.log(JSON.stringify(outputs, null, 2));
                
                console.log('\n[STEP 4] === OUTPUTS VALIDATION ===');
                console.log(`[STEP 4] Total outputs: ${outputs.length}`);
                let totalAdaOutputs = 0;
                outputs.forEach((output, index) => {
                    if (output.unit === 'lovelace') {
                        totalAdaOutputs += output.amount;
                        console.log(`[STEP 4] Output ${index}: ADA output = ${output.amount} ADA`);
                    } else {
                        console.log(`[STEP 4] Output ${index}: Token output = ${output.amount} ${output.ticker}`);
                    }
                });
                console.log(`[STEP 4] Total ADA in outputs: ${totalAdaOutputs} ADA`);
                console.log('[STEP 4] === END OUTPUTS VALIDATION ===\n');
                
                // Calculate total required amounts using proper decimal conversion
                let totalRequiredLovelace = 0;
                const requiredAssets = new Map();
                
                console.log('\n[STEP 4] === ASSET CONVERSION ANALYSIS ===');
                console.log(`[STEP 4] Processing ${outputs.length} outputs:`);
                outputs.forEach((output, index) => {
                    console.log(`[STEP 4] Output ${index}: unit=${output.unit}, amount=${output.amount}, ticker=${output.ticker}`);
                    console.log(`[STEP 4]   Original line: Asset=${this.transactionLines[index].Asset__c}, Amount=${this.transactionLines[index].Amount__c}`);
                });
                
                console.log('\n[STEP 4] === TRANSACTION LINES DEBUG ===');
                console.log(`[STEP 4] Total transaction lines: ${this.transactionLines.length}`);
                this.transactionLines.forEach((line, index) => {
                    console.log(`[STEP 4] Line ${index}: Asset=${line.Asset__c}, Amount=${line.Amount__c}, Ticker=${line.Ticker__c || 'N/A'}, Asset=${line.Asset__c || 'N/A'}`);
                });
                console.log('[STEP 4] === END TRANSACTION LINES DEBUG ===\n');
                
                for (const output of outputs) {
                    // Normalize ADA/ada to 'lovelace' for lookup
                    const normalizedUnit = (output.unit && output.unit.toLowerCase() === 'ada') ? 'lovelace' : output.unit;
                    if (normalizedUnit === 'lovelace') {
                        const lovelaceAmount = Math.floor(output.amount * 1000000);
                        totalRequiredLovelace += lovelaceAmount;
                        console.log(`[STEP 4] Required ADA: ${output.amount} → ${lovelaceAmount} lovelace (6 decimals)`);
                        console.log(`[STEP 4] Running total required lovelace: ${totalRequiredLovelace} (${(totalRequiredLovelace / 1000000).toFixed(6)} ADA)`);
                    } else {
                        // Use the helper method for enhanced asset lookup
                        const assetInfo = this.findAssetInfo(walletData, output.ticker, normalizedUnit);
                        if (!assetInfo) {
                            // Use helper method to get all available assets
                            const availableAssets = this.getAllAvailableAssets(walletData);
                            const availableAssetNames = availableAssets.length > 0 ? availableAssets.join(', ') : 'No assets found';
                            
                            // Enhanced error message with debugging info
                            let errorMessage = `Asset "${output.ticker}" not found in wallet. Available assets: ${availableAssetNames}.`;
                            
                            // Add helpful suggestions
                            if (availableAssets.length === 0) {
                                errorMessage += ' Your wallet appears to be empty or has no assets. Please add assets to your wallet first.';
                            } else {
                                errorMessage += ' Please check the asset name or ensure the asset is available in your wallet.';
                            }
                            
                            // Add debugging info for development
                            console.error('[ASSET_NOT_FOUND] Debug info:', {
                                requestedAsset: output.ticker,
                                requestedUnit: output.unit,
                                availableAssets: availableAssets,
                                walletSummaryAssets: walletData.walletSummary?.totalBalance?.assets || [],
                                receivingAddressesCount: walletData.receivingAddresses?.length || 0,
                                changeAddressesCount: walletData.changeAddresses?.length || 0
                            });
                            
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
                        console.log(`[STEP 4] Required ${output.ticker}: ${output.amount} → ${rawAmount} raw units (${decimals} decimals)`);
                        console.log(`[STEP 4]   Asset details: unit=${output.unit}, policyId=${assetInfo.policyId}, decimals=${decimals}`);
                    }
                }
                console.log('[STEP 4] === END ASSET CONVERSION ANALYSIS ===\n');
                
                console.log(`[STEP 4] Total required lovelace: ${totalRequiredLovelace} (${(totalRequiredLovelace / 1000000).toFixed(6)} ADA)`);
                console.log(`[STEP 4] Required assets (raw units):`, Array.from(requiredAssets.entries()));
                
                // Show human-readable summary
                console.log('\n[STEP 4] === HUMAN READABLE SUMMARY ===');
                console.log(`[STEP 4] Total required ADA: ${(totalRequiredLovelace / 1000000).toFixed(6)}`);
                for (const [unit, rawAmount] of requiredAssets) {
                    const assetInfo = walletData.walletSummary.totalBalance.assets.find(
                        asset => asset.unit === unit
                    );
                    const decimals = assetInfo ? assetInfo.decimals || 0 : 0;
                    const ticker = assetInfo ? assetInfo.ticker || unit : unit;
                    const humanAmount = (rawAmount / Math.pow(10, decimals)).toFixed(decimals);
                    console.log(`[STEP 4] Total required ${ticker}: ${humanAmount}`);
                }
                console.log('[STEP 4] === END HUMAN READABLE SUMMARY ===\n');
                console.log('[STEP 4] === END OUTPUTS ANALYSIS ===\n');

                // Create MultiAsset for transaction outputs
                console.log('\n[STEP 4] Preparing transaction outputs and asset conversion...');
                const { outputValue, sentAssets } = this.convertAssetsToOutputs(outputs, walletData);
                console.log('[STEP 4] Transaction outputs prepared.');

                // Get the actual required lovelace from the output value (like the old version)
                const actualRequiredLovelace = parseInt(outputValue.coin().to_str());
                console.log(`[STEP 4] Actual required lovelace from output: ${actualRequiredLovelace} (${(actualRequiredLovelace / 1000000).toFixed(6)} ADA)`);
                console.log(`[STEP 4] This replaces the previous calculation and should be accurate`);

                // Note: Minimum ADA calculation is now handled automatically by the transaction builder
                console.log(`[MIN_ADA] Output ADA amount: ${outputValue.coin().to_str()} lovelace (${(actualRequiredLovelace / 1000000).toFixed(6)} ADA)`);
                console.log(`[MIN_ADA] Transaction builder will automatically adjust minimum ADA requirements during build`);

                // Set transaction output
                console.log('\n[STEP 5] Adding transaction output for recipient...');
                this.validateAddress(toAddress);
                const recipientAddress = this.cardanoLib.Address.from_bech32(toAddress);
                const txOutput = this.cardanoLib.TransactionOutput.new(recipientAddress, outputValue);
                txBuilder.add_output(txOutput);
                console.log(`[STEP 5] Output added for recipient: ${toAddress}`);

                // Collect and validate UTXOs
                console.log('\n[STEP 6] Collecting UTXOs from wallet...');
                console.log('[STEP 6] Calling collectAndValidateUTXOs...');
                
                let utxos, inputUtxosDetails, totalLovelace, totalAssets;
                try {
                    const utxoResult = this.collectAndValidateUTXOs(walletData);
                    utxos = utxoResult.utxos;
                    inputUtxosDetails = utxoResult.inputUtxosDetails;
                    totalLovelace = utxoResult.totalLovelace;
                    totalAssets = utxoResult.totalAssets;
                    
                    console.log(`[STEP 6] ✅ Collected ${inputUtxosDetails.length} UTXOs from wallet.`);
                    console.log(`[STEP 6] UTXOs object type: ${typeof utxos}`);
                    console.log(`[STEP 6] UTXOs has len method: ${typeof utxos.len === 'function'}`);
                    console.log(`[STEP 6] UTXOs length: ${utxos.len()}`);
                    
                    // Log detailed UTXO information
                    console.log('\n[STEP 6] === DETAILED UTXO BREAKDOWN ===');
                    for (let i = 0; i < utxos.len(); i++) {
                        const utxo = utxos.get(i);
                        const input = utxo.input();
                        const output = utxo.output();
                        const txHashHex = this.bytesToHex(input.transaction_id().to_bytes());
                        const txIndex = input.index();
                        const address = output.address().to_bech32();
                        const value = output.amount();
                        const coin = value.coin().to_str();
                        
                        console.log(`[STEP 6] UTXO ${i}:`);
                        console.log(`  TX Hash: ${txHashHex}`);
                        console.log(`  TX Index: ${txIndex}`);
                        console.log(`  Address: ${address}`);
                        console.log(`  ADA: ${coin} lovelace (${(parseInt(coin) / 1000000).toFixed(6)} ADA)`);
                        
                        if (value.multiasset()) {
                            const multiasset = value.multiasset();
                            console.log(`[STEP 6] Has multi-asset tokens: ${multiasset.len()} policy IDs`);
                            // Log multi-asset details if needed
                        }
                        
                        // Find corresponding inputUtxosDetails
                        const utxoDetail = inputUtxosDetails.find(detail => 
                            detail.txHash === txHashHex && detail.txIndex === txIndex
                        );
                        if (utxoDetail) {
                            console.log(`  Detail match: ✅ Found in inputUtxosDetails`);
                        } else {
                            console.log(`  Detail match: ❌ NOT found in inputUtxosDetails`);
                        }
                    }
                    console.log('[STEP 6] === END DETAILED UTXO BREAKDOWN ===\n');
                    
                } catch (utxoError) {
                    console.error('[STEP 6] ❌ Error collecting UTXOs:', utxoError);
                    console.error('[STEP 6] UTXO error details:', JSON.stringify(utxoError, null, 2));
                    throw utxoError;
                }

                // Note: Funds validation will be handled by the transaction builder during build
                // This ensures we get accurate minimum ADA requirements including fees and change
                console.log('\n[STEP 6A] === FUNDS VALIDATION NOTE ===');
                console.log(`[STEP 6A] Available lovelace: ${totalLovelace} (${(totalLovelace / 1000000).toFixed(6)} ADA)`);
                console.log(`[STEP 6A] Recipient output lovelace: ${actualRequiredLovelace} (${(actualRequiredLovelace / 1000000).toFixed(6)} ADA)`);
                console.log(`[STEP 6A] Available assets:`, Array.from(totalAssets.entries()));
                console.log(`[STEP 6A] Required assets:`, Array.from(requiredAssets.entries()));
                console.log(`[STEP 6A] Transaction builder will validate sufficient funds during build`);
                console.log(`[STEP 6A] This includes minimum ADA for outputs, fees, and change requirements`);
                console.log('[STEP 6A] === END FUNDS VALIDATION NOTE ===\n');

                // Add inputs and change using the simplified approach
                console.log('\n[STEP 7] Adding inputs and change using automatic UTXO selection...');
                console.log(`[STEP 7] Using LargestFirstMultiAsset strategy for ${utxos.len()} UTXOs`);
                console.log(`[STEP 7] Strategy code: 3 (LargestFirstMultiAsset)`);
                
                // Create change configuration
                console.log('[STEP 7] Creating change configuration...');
                let changeAddress, changeConfig;
                try {
                    changeAddress = this.cardanoLib.Address.from_bech32(walletData.changeAddresses[0].address);
                    console.log(`[STEP 7] ✅ Change address created: ${walletData.changeAddresses[0].address}`);
                    
                    changeConfig = this.cardanoLib.ChangeConfig.new(changeAddress);
                    console.log('[STEP 7] ✅ Change configuration created');
                    console.log(`[STEP 7] Change config type: ${typeof changeConfig}`);
                } catch (changeError) {
                    console.error('[STEP 7] ❌ Error creating change configuration:', changeError);
                    throw changeError;
                }
                
                // Use the simplified add_inputs_from_and_change method
                console.log('[STEP 7] Calling add_inputs_from_and_change...');
                console.log('[STEP 7] Parameters:');
                console.log(`  - UTXOs: ${utxos.len()} UTXOs`);
                console.log(`  - Strategy: 3 (LargestFirstMultiAsset)`);
                console.log(`  - Change config: ${typeof changeConfig}`);
                
                try {
                    txBuilder.add_inputs_from_and_change(utxos, 3, changeConfig); // 3 = LargestFirstMultiAsset
                    console.log('[STEP 7] ✅ Inputs and change added automatically.');
                    console.log(`[STEP 7] Change address: ${walletData.changeAddresses[0].address}`);
                    
                    // Log what was added to the transaction builder
                    console.log('[STEP 7] Transaction builder state after UTXO selection:');
                    console.log(`  - Has fee set: ${txBuilder.get_fee_if_set() ? 'Yes' : 'No'}`);
                    if (txBuilder.get_fee_if_set()) {
                        console.log(`  - Fee amount: ${txBuilder.get_fee_if_set().to_str()} lovelace`);
                    }
                    console.log(`  - Change address configured: ${walletData.changeAddresses[0].address}`);
                    console.log(`  - UTXO selection strategy: LargestFirstMultiAsset (3)`);
                    
                } catch (selectionError) {
                    console.error('[STEP 7] ❌ Error in UTXO selection:', selectionError);
                    console.error('[STEP 7] Selection error details:', JSON.stringify(selectionError, null, 2));
                    
                    // Provide helpful error message for insufficient funds
                    let errorMessage = selectionError.toString();
                    // Use the actual required lovelace from the output value (correct calculation)
                    // Note: actualRequiredLovelace is defined in Step 4, but we need to use totalRequiredLovelace here
                    // since we're in a different scope. The totalRequiredLovelace should now be correct.
                    let actualRequiredLovelace = totalRequiredLovelace; // Use totalRequiredLovelace as fallback
                    let shortfall = actualRequiredLovelace - totalLovelace; // Default shortfall
                    let minAdaForOutput = 0; // Default minimum ADA
                    let actualFeeLovelace = 0; // Default fee
                    
                    if (errorMessage.includes('Not enough ADA leftover to include non-ADA assets in a change address')) {
                        console.log('[STEP 7] Handling multi-asset change output ADA requirement...');
                        
                        // Calculate minimum ADA required for the change output with multi-asset tokens
                        const mockChangeValue = this.cardanoLib.Value.new(this.cardanoLib.BigNum.from_str('0'));
                        const mockMultiAsset = this.cardanoLib.MultiAsset.new();
                        
                        // Add all remaining tokens to the mock change output
                        console.log(`[STEP 7] Total assets in wallet: ${totalAssets.size}`);
                        console.log(`[STEP 7] Available assets for change calculation:`);
                        for (const [unit, amount] of totalAssets) {
                            console.log(`[STEP 7]   ${unit}: ${amount} raw units`);
                        }
                        
                        for (const [unit, amount] of totalAssets) {
                            if (unit !== 'lovelace') {
                                console.log(`[STEP 7] Adding remaining asset to change calculation: ${unit} = ${amount} raw units`);
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
                            console.log(`[STEP 7] Mock change output has ${mockMultiAsset.len()} policies`);
                        }
                        
                        // Calculate minimum ADA for this multi-asset change output
                        const minAdaForChange = this.calculateMinimumADA(mockChangeValue, this.epochParameters);
                        
                        // Calculate actual fee using transaction builder
                        console.log('[STEP 7] Calculating actual transaction fee...');
                        const actualFee = txBuilder.min_fee();
                        actualFeeLovelace = parseInt(actualFee.to_str());
                        
                        // Total required = recipient amount + minimum ADA for change + fees
                        actualRequiredLovelace = totalRequiredLovelace + minAdaForChange + actualFeeLovelace;
                        shortfall = actualRequiredLovelace - totalLovelace;
                        
                        // Find the actual ADA amount being sent to the recipient
                        let recipientAdaAmount = 0;
                        const adaLine = this.transactionLines.find(line => 
                            line.Asset__c === 'ADA' || line.Asset__c === 'lovelace'
                        );
                        if (adaLine) {
                            recipientAdaAmount = parseFloat(adaLine.Amount__c || 0);
                            console.log(`[STEP 7] Found ADA transaction line: ${adaLine.Asset__c} = ${adaLine.Amount__c} → ${recipientAdaAmount} ADA`);
                        } else {
                            console.log(`[STEP 7] No ADA transaction line found, recipient ADA = 0`);
                        }
                        
                        const availableAda = (totalLovelace / 1000000).toFixed(6);
                        // Use the actual ADA amount from transaction lines
                        const recipientAda = recipientAdaAmount.toFixed(6);
                        const minChangeAda = (minAdaForChange / 1000000).toFixed(6);
                        const feeAda = (actualFeeLovelace / 1000000).toFixed(6);
                        const totalRequiredAda = (actualRequiredLovelace / 1000000).toFixed(6);
                        const shortfallAda = (shortfall / 1000000).toFixed(6);
                        
                        console.log(`[STEP 7] Multi-asset change ADA requirement breakdown:`);
                        console.log(`  - Recipient output: ${recipientAda} ADA`);
                        console.log(`  - Minimum ADA for change (with ${totalAssets.size - 1} tokens): ${minChangeAda} ADA`);
                        console.log(`  - Actual transaction fee: ${feeAda} ADA`);
                        console.log(`  - Total required: ${totalRequiredAda} ADA`);
                        console.log(`  - Available: ${availableAda} ADA`);
                        console.log(`  - Shortfall: ${shortfallAda} ADA`);
                        
                        errorMessage = `Insufficient ADA for multi-asset change: You have ${availableAda} ADA but need approximately ${totalRequiredAda} ADA (${recipientAda} ADA for recipient + ${minChangeAda} ADA minimum for change with tokens + ${feeAda} ADA fees). Add at least ${shortfallAda} ADA to your wallet.`;
                    } else if (errorMessage.includes('UTxO Balance Insufficient') || errorMessage.includes('insufficient')) {
                        console.log('[STEP 7] Calculating accurate minimum ADA requirements...');
                        
                        // Create a mock output value to calculate minimum ADA for the recipient output
                        const mockOutputValue = this.cardanoLib.Value.new(this.cardanoLib.BigNum.from_str('0'));
                        
                        // If we have multi-asset tokens in the transaction, add them to the mock output
                        // Use transaction lines to determine what assets are being sent
                        console.log('[STEP 7] === TRANSACTION LINES DEBUG ===');
                        console.log(`[STEP 7] Total transaction lines: ${this.transactionLines.length}`);
                        this.transactionLines.forEach((line, index) => {
                            console.log(`[STEP 7] Line ${index}: Asset=${line.Asset__c}, Amount=${line.Amount__c}`);
                        });
                        
                        const nonLovelaceAssets = this.transactionLines.filter(line => 
                            line.Asset__c && line.Asset__c !== 'ADA' && line.Asset__c !== 'lovelace'
                        );
                        
                        console.log(`[STEP 7] Non-lovelace assets found: ${nonLovelaceAssets.length}`);
                        nonLovelaceAssets.forEach((line, index) => {
                            console.log(`[STEP 7] Non-lovelace asset ${index}: ${line.Asset__c}`);
                        });
                        console.log('[STEP 7] === END TRANSACTION LINES DEBUG ===');
                        
                        if (nonLovelaceAssets.length > 0) {
                            console.log('[STEP 7] Adding multi-asset tokens to mock output for size calculation...');
                            const mockMultiAsset = this.cardanoLib.MultiAsset.new();
                            
                            for (const line of nonLovelaceAssets) {
                                const assetUnit = line.Asset__c;
                                console.log(`[STEP 7] Processing asset from transaction line: ${assetUnit}`);
                                
                                // Check if this looks like a valid asset unit (policy ID + asset name)
                                if (assetUnit && assetUnit.length >= 56 && /^[0-9a-fA-F]+$/.test(assetUnit)) {
                                    const policyIdHex = assetUnit.substring(0, 56);
                                    const assetNameHex = assetUnit.substring(56);
                                    
                                    console.log(`[STEP 7] Adding asset: policyId=${policyIdHex}, assetName=${assetNameHex}`);
                                    
                                    try {
                                        const policyId = this.cardanoLib.ScriptHash.from_hex(policyIdHex);
                                        const assetName = this.cardanoLib.AssetName.new(this.hexToBytes(assetNameHex));
                                        const assets = this.cardanoLib.Assets.new();
                                        assets.insert(assetName, this.cardanoLib.BigNum.from_str('1')); // Just need 1 for size calculation
                                        mockMultiAsset.insert(policyId, assets);
                                        console.log(`[STEP 7] Successfully added asset: ${assetUnit}`);
                                    } catch (assetError) {
                                        console.warn(`[STEP 7] Failed to add asset ${assetUnit}:`, assetError.message);
                                    }
                                } else {
                                    console.warn(`[STEP 7] Skipping invalid asset unit: ${assetUnit}`);
                                }
                            }
                            
                            if (mockMultiAsset.len() > 0) {
                                mockOutputValue.set_multiasset(mockMultiAsset);
                                console.log(`[STEP 7] Mock output has ${mockMultiAsset.len()} policies`);
                            } else {
                                console.log(`[STEP 7] No valid multi-asset tokens found in transaction lines`);
                            }
                        } else {
                            console.log(`[STEP 7] No non-lovelace assets found in transaction lines`);
                        }
                        
                        // Debug the mock output before calculating minimum ADA
                        console.log('[STEP 7] === MOCK OUTPUT DEBUG ===');
                        console.log(`[STEP 7] Mock output value type: ${typeof mockOutputValue}`);
                        console.log(`[STEP 7] Mock output has multiasset method: ${typeof mockOutputValue.multiasset === 'function'}`);
                        if (mockOutputValue.multiasset) {
                            const multiasset = mockOutputValue.multiasset();
                            console.log(`[STEP 7] Mock output multiasset: ${multiasset ? 'exists' : 'null'}`);
                            if (multiasset) {
                                console.log(`[STEP 7] Mock output multiasset length: ${multiasset.len()}`);
                                if (multiasset.len() > 0) {
                                    console.log(`[STEP 7] Mock output has ${multiasset.len()} policies`);
                                    const policies = multiasset.keys();
                                    for (let i = 0; i < policies.len(); i++) {
                                        const policy = policies.get(i);
                                        const policyHex = this.bytesToHex(policy.to_bytes());
                                        const assets = multiasset.get(policy);
                                        console.log(`[STEP 7] Policy ${i}: ${policyHex} with ${assets.len()} assets`);
                                    }
                                }
                            }
                        }
                        console.log('[STEP 7] === END MOCK OUTPUT DEBUG ===');
                        
                        // Calculate minimum ADA using official Cardano specification
                        minAdaForOutput = this.calculateMinimumADA(mockOutputValue, this.epochParameters);
                        
                        // Calculate actual fee using transaction builder
                        console.log('[STEP 7] Calculating actual transaction fee...');
                        const actualFee = txBuilder.min_fee();
                        actualFeeLovelace = parseInt(actualFee.to_str());
                        
                        actualRequiredLovelace = totalRequiredLovelace + minAdaForOutput + actualFeeLovelace;
                        shortfall = actualRequiredLovelace - totalLovelace;
                        
                        // Find the actual ADA amount being sent to the recipient
                        let recipientAdaAmount = 0;
                        const adaLine = this.transactionLines.find(line => 
                            line.Asset__c === 'ADA' || line.Asset__c === 'lovelace'
                        );
                        if (adaLine) {
                            recipientAdaAmount = parseFloat(adaLine.Amount__c || 0);
                            console.log(`[STEP 7] Found ADA transaction line: ${adaLine.Asset__c} = ${adaLine.Amount__c} → ${recipientAdaAmount} ADA`);
                        } else {
                            console.log(`[STEP 7] No ADA transaction line found, recipient ADA = 0`);
                        }
                        
                        const availableAda = (totalLovelace / 1000000).toFixed(6);
                        // Use the actual ADA amount from transaction lines
                        const recipientAda = recipientAdaAmount.toFixed(6);
                        const minUtxoAda = (minAdaForOutput / 1000000).toFixed(6);
                        const feeAda = (actualFeeLovelace / 1000000).toFixed(6);
                        const totalRequiredAda = (actualRequiredLovelace / 1000000).toFixed(6);
                        const shortfallAda = (shortfall / 1000000).toFixed(6);
                        
                        console.log(`[STEP 7] ADA requirement breakdown:`);
                        console.log(`  - totalRequiredLovelace: ${totalRequiredLovelace} lovelace (${(totalRequiredLovelace / 1000000).toFixed(6)} ADA)`);
                        console.log(`  - actualRequiredLovelace: ${actualRequiredLovelace} lovelace (${(actualRequiredLovelace / 1000000).toFixed(6)} ADA)`);
                        console.log(`  - minAdaForOutput: ${minAdaForOutput} lovelace (${(minAdaForOutput / 1000000).toFixed(6)} ADA)`);
                        console.log(`  - actualFeeLovelace: ${actualFeeLovelace} lovelace (${(actualFeeLovelace / 1000000).toFixed(6)} ADA)`);
                        console.log(`  - Recipient output: ${recipientAda} ADA`);
                        console.log(`  - Minimum UTXO requirement: ${minUtxoAda} ADA`);
                        console.log(`  - Actual transaction fee: ${feeAda} ADA`);
                        console.log(`  - Total required: ${totalRequiredAda} ADA`);
                        console.log(`  - Available: ${availableAda} ADA`);
                        console.log(`  - Shortfall: ${shortfallAda} ADA`);
                        
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

                // Build transaction body using the simplified approach
                console.log('\n[STEP 8] Building transaction body with automatic fee calculation and change...');
                console.log('[STEP 8] Calling txBuilder.build()...');
                
                let txBody;
                try {
                    txBody = txBuilder.build();
                    console.log('[STEP 8] ✅ Transaction body built successfully with automatic fee calculation and change.');
                    console.log(`[STEP 8] Transaction body type: ${typeof txBody}`);
                    console.log(`[STEP 8] Transaction body has inputs method: ${typeof txBody.inputs === 'function'}`);
                    console.log(`[STEP 8] Transaction body has outputs method: ${typeof txBody.outputs === 'function'}`);
                } catch (buildError) {
                    console.error('[STEP 8] ❌ Error building transaction body:', buildError);
                    console.error('[STEP 8] Build error details:', JSON.stringify(buildError, null, 2));
                    throw buildError;
                }

                // Get transaction hash for signing
                console.log('\n[STEP 9] Calculating transaction hash...');

                // Get actual transaction inputs from txBody
                console.log('[STEP 9] Getting transaction inputs...');
                let actualInputs;
                try {
                    actualInputs = txBody.inputs();
                    console.log(`[STEP 9] ✅ Transaction inputs extracted: ${actualInputs.len()} inputs`);
                    
                    // Log detailed input information
                    console.log('\n[STEP 9] === TRANSACTION INPUTS DETAILS ===');
                    for (let i = 0; i < actualInputs.len(); i++) {
                        const input = actualInputs.get(i);
                        const txHashHex = this.bytesToHex(input.transaction_id().to_bytes());
                        const txIndex = input.index();
                        console.log(`[STEP 9] Input ${i}: TX Hash: ${txHashHex}, Index: ${txIndex}`);
                    }
                    console.log('[STEP 9] === END TRANSACTION INPUTS DETAILS ===\n');
                } catch (inputsError) {
                    console.error('[STEP 9] ❌ Error getting transaction inputs:', inputsError);
                    throw inputsError;
                }

                // Calculate transaction hash using Blake2b
                console.log('[STEP 9] Calculating transaction hash using Blake2b...');
                let txHash, txHashHex;
                try {
                    const txBodyBytes = txBody.to_bytes();
                    console.log(`[STEP 9] Transaction body bytes length: ${txBodyBytes.length}`);
                    
                    // Use Blake2b to hash the transaction body
                    const hash = new window.Blake2b(32).update(txBodyBytes).digest();
                    console.log(`[STEP 9] Blake2b hash length: ${hash.length}`);
                    
                    // Create transaction hash from the digest
                    txHash = this.cardanoLib.TransactionHash.from_bytes(hash);
                    
                    // Validate txHash immediately after creation
                    if (!txHash || typeof txHash.to_bytes !== 'function') {
                        throw new Error(`Failed to create valid transaction hash object. Type: ${typeof txHash}, Constructor: ${txHash ? txHash.constructor.name : 'N/A'}`);
                    }
                    
                    txHashHex = this.bytesToHex(txHash.to_bytes());
                    console.log(`[STEP 9] ✅ Transaction hash calculated: ${txHashHex}`);
                    console.log(`[STEP 9] Hash validation: ✅ Valid transaction hash object created`);
                } catch (hashError) {
                    console.error('[STEP 9] ❌ Error calculating transaction hash:', hashError);
                    console.error('[STEP 9] Hash error details:', JSON.stringify(hashError, null, 2));
                    throw hashError;
                }

                // Get calculated fees
                console.log('\n[STEP 10] Transaction fee analysis...');
                let fees;
                try {
                    fees = txBuilder.get_fee_if_set() ? txBuilder.get_fee_if_set().to_str() : '0';
                    console.log(`[STEP 10] ✅ Transaction fee: ${fees} lovelace (${(parseInt(fees) / 1000000).toFixed(6)} ADA)`);
                    
                    // Log transaction outputs for fee analysis
                    console.log('[STEP 10] Analyzing transaction outputs...');
                    const outputs = txBody.outputs();
                    console.log(`[STEP 10] Total outputs: ${outputs.len()}`);
                    
                    for (let i = 0; i < outputs.len(); i++) {
                        const output = outputs.get(i);
                        const address = output.address().to_bech32();
                        const value = output.amount();
                        const coin = value.coin().to_str();
                        console.log(`[STEP 10] Output ${i}: Address: ${address}, ADA: ${coin} lovelace (${(parseInt(coin) / 1000000).toFixed(6)} ADA)`);
                        
                        if (value.multiasset()) {
                            const multiasset = value.multiasset();
                            console.log(`[STEP 10] Output ${i}: Has multi-asset tokens`);
                            // Log multi-asset details if needed
                        }
                    }
                } catch (feeError) {
                    console.error('[STEP 10] ❌ Error analyzing fees:', feeError);
                    throw feeError;
                }

                // Output built CBOR before signing for debugging
                console.log('\n[STEP 10A] === TRANSACTION BODY CBOR ANALYSIS ===');
                try {
                    const builtCborHex = this.bytesToHex(txBody.to_bytes());
                    console.log(`[STEP 10A] Built CBOR (before signing): ${builtCborHex}`);
                    console.log(`[STEP 10A] CBOR length: ${builtCborHex.length / 2} bytes`);
                    console.log(`[STEP 10A] CBOR preview (first 200 chars): ${builtCborHex.substring(0, 200)}...`);
                } catch (cborError) {
                    console.error('[STEP 10A] ❌ Error getting CBOR:', cborError);
                }
                console.log('[STEP 10A] === END CBOR ANALYSIS ===\n');

                // Build payment key hash to key mapping
                console.log('\n[STEP 11] Building payment key hash to key mapping...');
                // The address to key mapping is now built inside createWitnesses method
                // This simplifies the code and matches the pattern from the older version
                console.log(`[STEP 11] Address to key mapping will be built in createWitnesses method.`);

                // Create witnesses
                console.log('\n[STEP 12] Creating transaction witnesses...');
                console.log('[STEP 12] Calling createWitnesses...');
                console.log(`[STEP 12] Parameters:`);
                console.log(`  - Actual inputs: ${actualInputs.len()}`);
                console.log(`  - Input UTXO details: ${inputUtxosDetails.length}`);
                console.log(`  - Wallet data: ${walletData ? 'Available' : 'Not available'}`);
                console.log(`  - Transaction hash: ${txHashHex}`);
                
                let witnessSet;
                try {
                    witnessSet = this.createWitnesses(actualInputs, inputUtxosDetails, walletData, txHash);
                    console.log('[STEP 12] ✅ Witnesses created successfully');
                    console.log(`[STEP 12] Witness set type: ${typeof witnessSet}`);
                    console.log(`[STEP 12] Has vkeys method: ${typeof witnessSet.vkeys === 'function'}`);
                    if (witnessSet.vkeys()) {
                        console.log(`[STEP 12] Number of vkey witnesses: ${witnessSet.vkeys().len()}`);
                    }
                } catch (witnessError) {
                    console.error('[STEP 12] ❌ Error creating witnesses:', witnessError);
                    console.error('[STEP 12] Witness error details:', JSON.stringify(witnessError, null, 2));
                    throw witnessError;
                }

                // Build the signed transaction
                console.log('\n[STEP 13] Building signed transaction...');
                console.log('[STEP 13] Creating final transaction with witnesses...');
                console.log(`[STEP 13] Parameters:`);
                console.log(`  - Transaction body: ${typeof txBody}`);
                console.log(`  - Witness set: ${typeof witnessSet}`);
                console.log(`  - Auxiliary data: undefined (none)`);
                
                let signedTx, signedCborHex;
                try {
                    signedTx = this.cardanoLib.Transaction.new(
                        txBody,
                        witnessSet,
                        undefined // no auxiliary data
                    );
                    console.log('[STEP 13] ✅ Final transaction created successfully');
                    console.log(`[STEP 13] Signed transaction type: ${typeof signedTx}`);
                    console.log(`[STEP 13] Has to_bytes method: ${typeof signedTx.to_bytes === 'function'}`);
                    
                    // Convert to CBOR hex
                    console.log('[STEP 13] Converting to CBOR hex...');
                    const signedBytes = signedTx.to_bytes();
                    signedCborHex = this.bytesToHex(signedBytes);
                    console.log('[STEP 13] ✅ Transaction converted to CBOR hex successfully!');
                    console.log(`[STEP 13] Signed CBOR length: ${signedCborHex.length / 2} bytes`);
                } catch (signError) {
                    console.error('[STEP 13] ❌ Error signing transaction:', signError);
                    console.error('[STEP 13] Sign error details:', JSON.stringify(signError, null, 2));
                    throw signError;
                }

                // Update the outbound transaction with the signed CBOR
                console.log('\n[STEP 14] Updating outbound transaction with signed CBOR...');
                try {
                    await updateOutboundTransactionWithSignedCbor({
                        recordId: this.recordId,
                        signedCbor: signedCborHex
                    });
                    console.log('[STEP 14] ✅ Outbound transaction updated successfully with signed CBOR.');
                    this.showToast('Success', 'Transaction signed and updated successfully!', 'success');
                    this.isLoading = false;
                    this.dispatchEvent(new CustomEvent('transactionSigned'));
                } catch (updateError) {
                    console.error('[STEP 14] ❌ Error updating outbound transaction:', updateError);
                    console.error('[STEP 14] Update error details:', JSON.stringify(updateError, null, 2));
                    let apexMsg = updateError && updateError.body && updateError.body.message
                        ? updateError.body.message
                        : (updateError.message || JSON.stringify(updateError));
                    this.showToast('Error', `Failed to update outbound transaction: ${apexMsg}`, 'error');
                    this.isLoading = false;
                }

            } catch (error) {
                console.error('[buildAndSignTransaction] Error during transaction building:', error);
                
                // Enhanced error handling with specific messages
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
                        case 'INVALID_AMOUNT':
                            userMessage = `Invalid amount for ${error.details.assetName}: ${error.details.amount}. Amount must be greater than 0.`;
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
            console.error('[buildAndSignTransaction] Error during transaction preparation:', error);
            
            // Enhanced error handling for preparation phase
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

    /**
     * Fetch transaction lines from Salesforce
     */
    async fetchTransactionLines() {
        try {
            console.log(`[fetchTransactionLines] Fetching transaction lines for recordId: ${this.recordId}`);
            const lines = await getTransactionLinesForOutbound({ outboundTransactionId: this.recordId });
            this.transactionLines = lines;
            console.log(`[fetchTransactionLines] Transaction lines fetched: ${this.transactionLines.length}`);
            
            // Validate transaction lines
            if (!this.transactionLines || this.transactionLines.length === 0) {
                throw new Error('No transaction lines found. Please add at least one asset to send.');
            }
            
            // Check for invalid assets
            const invalidLines = this.transactionLines.filter(line => 
                !line.Asset__c || !line.Amount__c || parseFloat(line.Amount__c) <= 0
            );
            
            if (invalidLines.length > 0) {
                const invalidAssets = invalidLines.map(line => line.Asset__c || 'Unknown').join(', ');
                throw new Error(`Invalid transaction lines found for assets: ${invalidAssets}. Please check asset names and amounts.`);
            }
            
        } catch (error) {
            console.error(`[fetchTransactionLines] Error fetching transaction lines:`, error);
            
            // Enhanced error message
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

    /**
     * Show toast message
     */
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'dismissible'
        });
        this.dispatchEvent(event);
    }

    // Helper method to get all available assets from wallet data
    getAllAvailableAssets(walletData) {
        console.log('[getAllAvailableAssets] Starting asset discovery...');
        const assets = new Set();
        
        // Add ADA/lovelace
        assets.add('ADA');
        assets.add('lovelace');
        
        // Check wallet summary assets
        if (walletData.walletSummary && walletData.walletSummary.totalBalance && walletData.walletSummary.totalBalance.assets) {
            console.log(`[getAllAvailableAssets] Found ${walletData.walletSummary.totalBalance.assets.length} assets in wallet summary`);
            walletData.walletSummary.totalBalance.assets.forEach(asset => {
                if (asset.ticker) {
                    assets.add(asset.ticker);
                    console.log(`[getAllAvailableAssets] Added ticker: ${asset.ticker}`);
                }
                if (asset.assetName) {
                    assets.add(asset.assetName);
                    console.log(`[getAllAvailableAssets] Added assetName: ${asset.assetName}`);
                }
                if (asset.unit && asset.unit !== 'lovelace') {
                    assets.add(asset.unit);
                    console.log(`[getAllAvailableAssets] Added unit: ${asset.unit}`);
                }
            });
        } else {
            console.log('[getAllAvailableAssets] No wallet summary assets found');
        }
        
        // Check all addresses for assets
        const allAddresses = [
            ...(walletData.receivingAddresses || []),
            ...(walletData.changeAddresses || [])
        ];
        
        console.log(`[getAllAvailableAssets] Checking ${allAddresses.length} addresses for assets`);
        
        allAddresses.forEach((addr, index) => {
            if (addr.utxos) {
                console.log(`[getAllAvailableAssets] Address ${index} has ${addr.utxos.length} UTXOs`);
                addr.utxos.forEach(utxo => {
                    if (utxo.amount) {
                        utxo.amount.forEach(amount => {
                            if (amount.unit && amount.unit !== 'lovelace') {
                                assets.add(amount.unit);
                                console.log(`[getAllAvailableAssets] Added unit from UTXO: ${amount.unit}`);
                            }
                        });
                    }
                });
            }
        });
        
        const result = Array.from(assets).sort();
        console.log(`[getAllAvailableAssets] Final result: ${result.length} unique assets:`, result);
        return result;
    }

    // Helper method to find asset info by ticker or unit
    findAssetInfo(walletData, ticker, unit) {
        console.log(`[findAssetInfo] Looking for asset: ticker="${ticker}", unit="${unit}"`);
        
        if (!walletData.walletSummary || !walletData.walletSummary.totalBalance || !walletData.walletSummary.totalBalance.assets) {
            console.log('[findAssetInfo] No wallet summary or assets found');
            return null;
        }
        
        const assets = walletData.walletSummary.totalBalance.assets;
        console.log(`[findAssetInfo] Found ${assets.length} assets in wallet summary:`, assets.map(a => ({ ticker: a.ticker, assetName: a.assetName, unit: a.unit })));
        
        // Try exact unit match first
        let assetInfo = assets.find(asset => asset.unit === unit);
        if (assetInfo) {
            console.log(`[findAssetInfo] ✅ Found by exact unit match:`, assetInfo);
            return assetInfo;
        }
        
        // Try exact ticker match
        assetInfo = assets.find(asset => asset.ticker && asset.ticker.toLowerCase() === ticker.toLowerCase());
        if (assetInfo) {
            console.log(`[findAssetInfo] ✅ Found by exact ticker match:`, assetInfo);
            return assetInfo;
        }
        
        // Try exact asset name match
        assetInfo = assets.find(asset => asset.assetName && asset.assetName.toLowerCase() === ticker.toLowerCase());
        if (assetInfo) {
            console.log(`[findAssetInfo] ✅ Found by exact asset name match:`, assetInfo);
            return assetInfo;
        }
        
        // Try partial matches
        assetInfo = assets.find(asset => 
            (asset.ticker && asset.ticker.toLowerCase().includes(ticker.toLowerCase())) ||
            (asset.assetName && asset.assetName.toLowerCase().includes(ticker.toLowerCase()))
        );
        if (assetInfo) {
            console.log(`[findAssetInfo] ✅ Found by partial match:`, assetInfo);
            return assetInfo;
        }
        
        console.log(`[findAssetInfo] ❌ Asset not found after all matching attempts`);
        return null;
    }
}