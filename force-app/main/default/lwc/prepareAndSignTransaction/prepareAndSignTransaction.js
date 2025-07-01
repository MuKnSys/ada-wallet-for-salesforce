import { LightningElement, api, track, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import getWalletUTXOs from '@salesforce/apex/TransactionController.getWalletUTXOs';
import getMultipleAddressUtxosDetailed from '@salesforce/apex/BlockfrostService.getMultipleAddressUtxosDetailed';
import getEpochParameters from '@salesforce/apex/BlockfrostService.getEpochParameters';
import getCurrentSlotAndTTL from '@salesforce/apex/BlockfrostService.getCurrentSlotAndTTL';
import updateOutboundTransactionCbor from '@salesforce/apex/TransactionController.updateOutboundTransactionCbor';
import getOutboundTransactionCbor from '@salesforce/apex/TransactionController.getOutboundTransactionCbor';
import getOutboundTransactionDetails from '@salesforce/apex/TransactionController.getOutboundTransactionDetails';
import WALLET_FIELD from '@salesforce/schema/Outbound_Transaction__c.Wallet__c';
import TO_ADDRESS_FIELD from '@salesforce/schema/Outbound_Transaction__c.To_Address__c';
import AMOUNT_FIELD from '@salesforce/schema/Outbound_Transaction__c.Amount__c';
import CARDANO_SERIALIZATION from '@salesforce/resourceUrl/cardanoSerialization';
import BIP39 from '@salesforce/resourceUrl/bip39';
import BLAKE from '@salesforce/resourceUrl/blake';

export default class PrepareAndSignTransaction extends LightningElement {
    @api recordId;
    @track isLoading = false;
    @track outboundTransaction;
    @track librariesLoaded = false;
    @track stepLogs = [];
    @track currentStep = 0;
    @track totalSteps = 12;
    @track signedTransactionCbor = '';
    @track showCborDisplay = false;
    @track isLoadingLibraries = false;

    // Cardano library references
    cardanoLib = null;

    @wire(getRecord, { 
        recordId: '$recordId', 
        fields: [WALLET_FIELD, TO_ADDRESS_FIELD, AMOUNT_FIELD] 
    })
    wiredOutboundTransaction(result) {
        try {
        this.outboundTransaction = result;
        if (result.error) {
            console.error('Error loading Outbound Transaction:', result.error);
            this.showToast('Error', 'Failed to load Outbound Transaction record', 'error');
            } else if (result.data) {
                // Load existing CBOR and transaction details
                this.loadExistingTransactionData();
            }
        } catch (error) {
            console.error('Error in wiredOutboundTransaction:', error);
            this.showToast('Error', 'Failed to process transaction data', 'error');
        }
    }

    async loadExistingTransactionData() {
        try {
            if (!this.recordId) {
                return;
            }

            console.log('📋 Loading existing transaction data...');
            
            // Get transaction details
            const transactionDetails = await getOutboundTransactionDetails({ recordId: this.recordId });
            console.log('📋 Transaction details loaded:', transactionDetails);

            // Get existing CBOR if available
            const existingCbor = await getOutboundTransactionCbor({ recordId: this.recordId });
            
            if (existingCbor && existingCbor.length > 0) {
                console.log('📋 Existing CBOR found, length:', existingCbor.length / 2, 'bytes');
                this.signedTransactionCbor = existingCbor;
                this.showCborDisplay = true;
                
                // Show info toast about existing CBOR
                this.showToast('Info', 'Existing signed transaction CBOR found and loaded.', 'info');
            } else {
                console.log('📋 No existing CBOR found');
            }

        } catch (error) {
            console.error('❌ Error loading existing transaction data:', error);
            // Don't show error toast as this is not critical
        }
    }

    renderedCallback() {
        try {
            if (!this.librariesLoaded && !this.isLoadingLibraries) {
                console.log('🔄 Component rendered, starting library loading...');
                this.isLoadingLibraries = true;
                
                // Load libraries asynchronously
                this.loadLibraries()
                    .then(() => {
                        console.log('✅ Libraries loaded successfully in renderedCallback');
                        this.isLoadingLibraries = false;
                    })
                    .catch((error) => {
                        console.error('❌ Failed to load libraries in renderedCallback:', error);
                        this.isLoadingLibraries = false;
                        this.showToast('Error', 'Failed to load required libraries. Please refresh the page.', 'error');
                    });
            }
        } catch (error) {
            console.error('Error in renderedCallback:', error);
            this.isLoadingLibraries = false;
            this.showToast('Error', 'Failed to initialize component', 'error');
        }
    }

    async loadLibraries() {
        this.logStep(1, 'Loading Cardano libraries', 'info');
        
        try {
            // Load required libraries
            const scripts = [
                { name: 'cardanoSerialization', url: `${CARDANO_SERIALIZATION}/cardanoSerialization/bundle.js` },
                { name: 'bip39', url: BIP39 },
                { name: 'blake', url: BLAKE }
            ];

            for (const script of scripts) {
                try {
                    console.log(`   Loading ${script.name} from: ${script.url}`);
                    await loadScript(this, script.url);
                    console.log(`✅ ${script.name} library loaded successfully`);
                } catch (error) {
                    console.error(`❌ Failed to load ${script.name} library:`, error);
                    throw new Error(`Failed to load ${script.name} library: ${error.message}`);
                }
            }

            // Verify that libraries are available on window object
            console.log('🔍 Verifying library availability...');
            
            if (!window.cardanoSerialization) {
                throw new Error('Cardano serialization library not found on window object');
            }
            
            if (!window.bip39) {
                throw new Error('BIP39 library not found on window object');
            }
            
            if (!window.blake2b) {
                console.log('⚠️ Blake2b library not found on window object, but continuing...');
            }

            // Blake2b library loaded and ready for transaction signing
            console.log('✅ Blake2b library available for transaction hashing');

            // Debug Cardano library
            console.log('🔍 Cardano Library Debug Info:');
            console.log('   - Type:', typeof window.cardanoSerialization);
            console.log('   - Is Object:', typeof window.cardanoSerialization === 'object');
            console.log('   - Available methods:', Object.getOwnPropertyNames(window.cardanoSerialization || {}));
            console.log('   - Window.cardanoSerialization:', window.cardanoSerialization);
            console.log('   - Window.cardanoSerialization type:', typeof window.cardanoSerialization);
            
            // Test basic Cardano library functionality
            try {
                if (typeof window.cardanoSerialization.BigNum !== 'function') {
                    throw new Error('BigNum constructor not available');
                }
                
                // Test creating a simple BigNum
                const testBigNum = window.cardanoSerialization.BigNum.from_str('1000000');
                if (!testBigNum || typeof testBigNum.to_str !== 'function') {
                    throw new Error('BigNum creation failed');
                }
                
                const testValue = testBigNum.to_str();
                console.log(`   ✅ BigNum test successful: ${testValue}`);
                
                // Clean up test object
                if (typeof testBigNum.free === 'function') {
                    testBigNum.free();
                }
                
            } catch (testError) {
                console.error('❌ Cardano library functionality test failed:', testError);
                throw new Error(`Cardano library functionality test failed: ${testError.message}`);
            }
            
            console.log('[Step 1] Cardano libraries loaded successfully');

            // Store reference to Cardano library
            this.cardanoLib = window.cardanoSerialization;
            
            // Verify the reference is valid
            if (!this.cardanoLib) {
                throw new Error('Failed to store Cardano library reference');
            }

            this.librariesLoaded = true;
            console.log('✅ Library loading completed successfully');
            
        } catch (error) {
            console.error('❌ Error in loadLibraries:', error);
            this.librariesLoaded = false;
            this.cardanoLib = null;
            throw error;
        }
    }

    // Native JavaScript SHA-256 function
    async computeHash(data) {
        const buffer = new Uint8Array(data).buffer; // Convert input to ArrayBuffer
        const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
        return new Uint8Array(hashBuffer); // Return hash as Uint8Array
    }

    get walletId() {
        try {
            return this.outboundTransaction?.data?.fields?.Wallet__c?.value || null;
        } catch (error) {
            console.error('Error getting wallet ID:', error);
            return null;
        }
    }

    get transactionDetails() {
        try {
            const data = this.outboundTransaction?.data?.fields;
            if (!data) return null;
            return {
                walletId: data.Wallet__c?.value,
                toAddress: data.To_Address__c?.value,
                amount: data.Amount__c?.value
            };
        } catch (error) {
            console.error('Error getting transaction details:', error);
            return null;
        }
    }

    /**
     * Calculate minimum ADA required for a UTXO with multi-assets
     */
    calculateMinAda(multiAsset, protocolParams) {
        try {
            // Use the Cardano library's built-in min_ada_required if available
            if (this.cardanoLib && this.cardanoLib.min_ada_required) {
                try {
                    const value = this.cardanoLib.Value.new(this.cardanoLib.BigNum.from_str('1000000'));
                    if (multiAsset) {
                        value.set_multiasset(multiAsset);
                    }
                    
                    // Safe parsing of coins_per_utxo_size parameter
                    const safeCoinsPerUtxoSize = this.safeParseProtocolParam(
                        protocolParams?.coins_per_utxo_size || protocolParams?.coins_per_utxo_byte, 
                        4310, 
                        'coins_per_utxo_size'
                    );
                    
                    const minAda = this.cardanoLib.min_ada_required(
                        value,
                        false, // has_data_hash
                        this.cardanoLib.BigNum.from_str(safeCoinsPerUtxoSize.toString())
                    );
                    const result = parseInt(minAda.to_str());
                    console.log(`   ✅ Library min_ada_required result: ${result} lovelace (${result / 1000000} ADA)`);
                    return result;
                } catch (libError) {
                    console.log(`   ⚠️ Built-in min_ada_required failed: ${libError.message}, using manual calculation`);
                }
            }

            // Skip alternative library methods due to dummy address issues

            // Conservative manual calculation for multi-assets
            const baseMinAda = 1000000; // 1 ADA base minimum
            let additionalAda = 0;

            if (multiAsset) {
                try {
                    const policies = multiAsset.keys();
                    const policyCount = policies.len();
                    
                    let totalAssets = 0;
                    for (let i = 0; i < policyCount; i++) {
                        const policy = policies.get(i);
                        const assets = multiAsset.get(policy);
                        if (assets) {
                            totalAssets += assets.len();
                        }
                    }
                    
                    // Conservative estimate: ~0.15 ADA per policy + ~0.05 ADA per asset
                    additionalAda = (policyCount * 150000) + (totalAssets * 50000);
                    
                    console.log(`   Manual calculation: ${policyCount} policies, ${totalAssets} assets, additional: ${additionalAda} lovelace`);
                    
                } catch (multiAssetError) {
                    console.log(`   ⚠️ Error processing multi-asset: ${multiAssetError.message}`);
                    // Very conservative fallback: if we have multi-assets, require 1.5 ADA minimum
                    additionalAda = 500000; // 0.5 ADA extra for any multi-assets
                }
            }

            const calculatedMinAda = baseMinAda + additionalAda;
            
            // Ensure minimum of 1.2 ADA for any multi-asset UTXO
            const finalMinAda = multiAsset && additionalAda > 0 ? 
                Math.max(calculatedMinAda, 1200000) : // 1.2 ADA minimum for multi-asset
                Math.max(calculatedMinAda, 1000000);  // 1 ADA minimum for ADA-only
            
            console.log(`   Min ADA calculation: base=${baseMinAda}, additional=${additionalAda}, final=${finalMinAda} lovelace (${finalMinAda / 1000000} ADA)`);
            
            return finalMinAda;
        } catch (error) {
            console.error('Error calculating minimum ADA:', error);
            // Return a very safe default for multi-assets
            const safeDefault = multiAsset ? 1500000 : 1000000; // 1.5 ADA for multi-asset, 1 ADA for ADA-only
            console.log(`   Using safe default: ${safeDefault} lovelace (${safeDefault / 1000000} ADA)`);
            return safeDefault;
        }
    }

    /**
     * Create multi-asset structure from UTXO amount array
     */
    createMultiAssetFromAmount(amountArray) {
        try {
            const multiAsset = {};
            
            if (!amountArray || !Array.isArray(amountArray)) {
                return multiAsset;
            }

            for (const asset of amountArray) {
                if (asset.unit === 'lovelace') {
                    continue;
                }
                
                if (asset.unit.length >= 56) {
                    const policyId = asset.unit.substring(0, 56);
                    const assetName = asset.unit.substring(56);
                    
                    if (!multiAsset[policyId]) {
                        multiAsset[policyId] = {};
                    }
                    multiAsset[policyId][assetName] = parseInt(asset.quantity);
                }
            }
            
            return multiAsset;
        } catch (error) {
            console.error('Error creating multi-asset structure:', error);
            throw new Error(`Failed to create multi-asset structure: ${error.message}`);
        }
    }

    /**
     * Validate ADA address format and structure
     */
    validateAdaAddress(address) {
        try {
            console.log(`🔍 Validating ADA address: ${address}`);
            
            if (!address || typeof address !== 'string') {
                throw new Error('Address must be a non-empty string');
            }
            
            const trimmedAddress = address.trim();
            
            // Check length (ADA addresses are typically 103 characters)
            if (trimmedAddress.length < 100 || trimmedAddress.length > 110) {
                throw new Error(`Invalid address length: ${trimmedAddress.length}. Expected 100-110 characters.`);
            }
            
            // Check prefix (addr1 for mainnet, addr_test1 for testnet)
            if (!trimmedAddress.startsWith('addr1') && !trimmedAddress.startsWith('addr_test1')) {
                throw new Error(`Invalid address prefix. Expected 'addr1' or 'addr_test1', got: ${trimmedAddress.substring(0, 10)}...`);
            }
            
            // Check for valid base58 characters (including 0, but excluding O, I)
            // Base58 alphabet: 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
            const base58Regex = /^[1-9A-HJ-NP-Za-km-z0l]+$/;
            
            if (!base58Regex.test(trimmedAddress)) {
                console.error(`❌ Address contains invalid characters`);
                console.error(`❌ Failed regex: ${base58Regex}`);
                console.error(`❌ Address: ${trimmedAddress}`);
                throw new Error('Address contains invalid characters. Only base58 characters are allowed.');
            }
            
            // Additional validation with Cardano library if available
            if (this.cardanoLib) {
                try {
                    console.log('🔍 Attempting Cardano library validation...');
                    const cardanoAddress = this.cardanoLib.Address.from_bech32(trimmedAddress);
                    
                    // Safely get network ID
                    let networkId = null;
                    try {
                        networkId = cardanoAddress.network_id();
                        console.log(`   Network ID: ${networkId} (${networkId === 0 ? 'Testnet' : 'Mainnet'})`);
                    } catch (networkError) {
                        console.log(`   ⚠️ Could not get network ID: ${networkError.message}`);
                    }
                    
                    // Safely get address type
                    let addressType = 'unknown';
                    try {
                        if (typeof cardanoAddress.address_type === 'function') {
                            addressType = cardanoAddress.address_type();
                        } else if (typeof cardanoAddress.get_type === 'function') {
                            addressType = cardanoAddress.get_type();
                        } else if (typeof cardanoAddress.type === 'function') {
                            addressType = cardanoAddress.type();
                        } else {
                            console.log(`   ⚠️ Address type method not available`);
                        }
                        console.log(`   Address Type: ${addressType}`);
                    } catch (typeError) {
                        console.log(`   ⚠️ Could not get address type: ${typeError.message}`);
                    }
                    
                    // Clean up
                    try {
                        cardanoAddress.free();
                    } catch (freeError) {
                        console.log(`   ⚠️ Could not free address object: ${freeError.message}`);
                    }
                    
                    console.log('   ✅ Cardano library validation completed');
                    
                    return {
                        isValid: true,
                        network: networkId === 0 ? 'testnet' : 'mainnet',
                        addressType: addressType,
                        address: trimmedAddress
                    };
                } catch (cardanoError) {
                    console.log(`   ⚠️ Cardano library validation failed: ${cardanoError.message}`);
                    console.log(`   ⚠️ Falling back to basic validation`);
                    
                    // Don't throw error, just fall back to basic validation
                    return {
                        isValid: true,
                        network: trimmedAddress.startsWith('addr_test1') ? 'testnet' : 'mainnet',
                        addressType: 'unknown',
                        address: trimmedAddress
                    };
                }
            }
            
            // Fallback validation without Cardano library
            return {
                isValid: true,
                network: trimmedAddress.startsWith('addr_test1') ? 'testnet' : 'mainnet',
                addressType: 'unknown',
                address: trimmedAddress
            };
            
        } catch (error) {
            console.error(`❌ Address validation failed: ${error.message}`);
            return {
                isValid: false,
                error: error.message,
                address: address
            };
        }
    }

    /**
     * Validate transaction amount
     */
    validateTransactionAmount(amount) {
        try {
            console.log(`💰 Validating transaction amount: ${amount}`);
            
            if (amount === null || amount === undefined || amount === '') {
                throw new Error('Amount is required');
            }
            
            const numericAmount = parseFloat(amount);
            console.log(`   Parsed amount: ${numericAmount} (type: ${typeof numericAmount})`);
            
            if (isNaN(numericAmount)) {
                throw new Error(`Invalid amount format: ${amount}. Must be a valid number.`);
            }
            
            if (numericAmount <= 0) {
                throw new Error(`Amount must be positive. Got: ${numericAmount}`);
            }
            
            // Check for reasonable limits
            const maxAda = 45000000; // 45 billion ADA
            if (numericAmount > maxAda) {
                throw new Error(`Amount ${numericAmount} ADA exceeds maximum allowed amount of ${maxAda} ADA`);
            }
            
            const minAda = 0.000001; // 1 lovelace
            if (numericAmount < minAda) {
                throw new Error(`Amount ${numericAmount} ADA is below minimum allowed amount of ${minAda} ADA`);
            }
            
            const amountInLovelace = Math.round(numericAmount * 1000000);
            
            return {
                isValid: true,
                amount: numericAmount,
                amountInLovelace: amountInLovelace,
                formatted: `${numericAmount} ADA (${amountInLovelace} lovelace)`
            };
            
        } catch (error) {
            console.error(`❌ Amount validation failed: ${error.message}`);
            return {
                isValid: false,
                error: error.message,
                amount: amount
            };
        }
    }

    /**
     * Validate transaction details
     */
    validateTransactionDetails() {
        try {
            console.log('🔍 Starting transaction details validation...');
            
            const transactionDetails = this.transactionDetails;
            if (!transactionDetails) {
                console.error('❌ Transaction details not available');
                throw new Error('Transaction details not available');
            }
            
            console.log('📋 Raw transaction details:', {
                walletId: transactionDetails.walletId,
                toAddress: transactionDetails.toAddress,
                amount: transactionDetails.amount,
                amountType: typeof transactionDetails.amount
            });
            
            // Validate wallet ID
            if (!transactionDetails.walletId) {
                console.error('❌ Wallet ID is missing');
                throw new Error('Wallet ID is required');
            }
            console.log(`✅ Wallet ID validated: ${transactionDetails.walletId}`);
            
            // Validate recipient address
            if (!transactionDetails.toAddress) {
                console.error('❌ Recipient address is missing');
                throw new Error('Destination address is required');
            }
            
            // Enhanced address validation
            const address = transactionDetails.toAddress.trim();
            console.log(`🔍 Validating recipient address: ${address}`);
            
            // Check for basic format
            if (address.length < 100 || address.length > 110) {
                console.error(`❌ Address length invalid: ${address.length} characters`);
                throw new Error(`Invalid address length: ${address.length} characters. Expected 100-110 characters.`);
            }
            
            // Check for ADA address prefix
            if (!address.startsWith('addr')) {
                console.error(`❌ Invalid address prefix: ${address.substring(0, 10)}...`);
                throw new Error(`Invalid address format. Must start with 'addr'. Got: ${address.substring(0, 10)}...`);
            }
            
            // Check for valid characters (base58)
            const validChars = /^[1-9A-HJ-NP-Za-km-z0l]+$/;
            
            if (!validChars.test(address)) {
                console.error(`❌ Address contains invalid characters`);
                console.error(`❌ Failed regex: ${validChars}`);
                console.error(`❌ Address: ${address}`);
                throw new Error('Address contains invalid characters. Only base58 characters are allowed.');
            }
            
            console.log(`✅ Recipient address format validated: ${address.substring(0, 20)}...`);
            
            // Validate amount
            if (!transactionDetails.amount) {
                console.error('❌ Transaction amount is missing');
                throw new Error('Valid transaction amount is required');
            }
            
            const amount = parseFloat(transactionDetails.amount);
            console.log(`🔍 Validating transaction amount: ${amount} (type: ${typeof amount})`);
            
            if (isNaN(amount)) {
                console.error(`❌ Amount is not a valid number: ${transactionDetails.amount}`);
                throw new Error(`Invalid amount format: ${transactionDetails.amount}. Must be a valid number.`);
            }
            
            if (amount <= 0) {
                console.error(`❌ Amount must be positive: ${amount}`);
                throw new Error(`Amount must be positive. Got: ${amount}`);
            }
            
            // Check for reasonable amount limits
            const maxAda = 45000000; // 45 billion ADA (Cardano total supply)
            if (amount > maxAda) {
                console.error(`❌ Amount exceeds maximum: ${amount} ADA`);
                throw new Error(`Amount ${amount} ADA exceeds maximum allowed amount of ${maxAda} ADA`);
            }
            
            const minAda = 0.000001; // 1 lovelace
            if (amount < minAda) {
                console.error(`❌ Amount below minimum: ${amount} ADA`);
                throw new Error(`Amount ${amount} ADA is below minimum allowed amount of ${minAda} ADA`);
            }
            
            const amountInLovelace = Math.round(amount * 1000000);
            console.log(`✅ Amount validated: ${amount} ADA (${amountInLovelace} lovelace)`);
            
            // Return validated details
            const validatedDetails = {
                walletId: transactionDetails.walletId,
                toAddress: address,
                amount: amount,
                amountInLovelace: amountInLovelace
            };
            
            console.log('✅ Transaction details validation completed successfully');
            console.log('📊 Final validated details:', validatedDetails);
            
            return validatedDetails;
        } catch (error) {
            console.error('❌ Transaction validation failed:', error);
            throw new Error(`Transaction validation failed: ${error.message}`);
        }
    }

    /**
     * Fetch and structure wallet addresses
     */
    async fetchWalletAddresses(walletId) {
        try {
            this.logStep(2, 'Fetching wallet addresses', 'info');
            
            const utxoAddresses = await getWalletUTXOs({ walletId });
            console.log(`📡 Raw wallet addresses response:`, utxoAddresses);
            
            const receivingAddresses = [];
            const changeAddresses = [];
            const addressPrivateKeys = new Map();

            // Process receiving addresses (type '0')
            utxoAddresses.filter(addr => addr.addressType === '0').forEach(addr => {
                try {
                    console.log(`🔍 Processing receiving address:`, {
                        address: addr.address,
                        addressType: addr.addressType,
                        privateKeyType: typeof addr.privateKey,
                        privateKeyLength: addr.privateKey ? addr.privateKey.length : 'undefined',
                        privateKeyPreview: addr.privateKey ? addr.privateKey.substring(0, 20) + '...' : 'undefined',
                        privateKeyFull: addr.privateKey || 'null/undefined', // Log the full private key
                        hasPublicKey: !!addr.publicKey,
                        hasStakingKeyHash: !!addr.stakingKeyHash
                    });
                    
                receivingAddresses.push({
                    address: addr.address,
                    path: addr.path,
                    index: addr.addressIndex,
                    privateKey: addr.privateKey,
                    publicKey: addr.publicKey,
                    stakingKeyHash: addr.stakingKeyHash,
                    assets: addr.assets
                });
                addressPrivateKeys.set(addr.address, addr.privateKey);
                } catch (error) {
                    console.error('❌ Error processing receiving address:', error);
                    console.error('   Address data:', addr);
                }
            });

            // Process change addresses (type '1') 
            utxoAddresses.filter(addr => addr.addressType === '1').forEach(addr => {
                try {
                    console.log(`🔍 Processing change address:`, {
                        address: addr.address,
                        addressType: addr.addressType,
                        privateKeyType: typeof addr.privateKey,
                        privateKeyLength: addr.privateKey ? addr.privateKey.length : 'undefined',
                        privateKeyPreview: addr.privateKey ? addr.privateKey.substring(0, 20) + '...' : 'undefined',
                        privateKeyFull: addr.privateKey || 'null/undefined', // Log the full private key
                        hasPublicKey: !!addr.publicKey,
                        hasStakingKeyHash: !!addr.stakingKeyHash
                    });
                    
                changeAddresses.push({
                    address: addr.address,
                    path: addr.path,
                    index: addr.addressIndex,
                    privateKey: addr.privateKey,
                    publicKey: addr.publicKey,
                    stakingKeyHash: addr.stakingKeyHash,
                    assets: addr.assets
                });
                addressPrivateKeys.set(addr.address, addr.privateKey);
                } catch (error) {
                    console.error('❌ Error processing change address:', error);
                    console.error('   Address data:', addr);
                }
            });

            console.log(`📊 Address processing summary:`);
            console.log(`   Total addresses received: ${utxoAddresses.length}`);
            console.log(`   Receiving addresses: ${receivingAddresses.length}`);
            console.log(`   Change addresses: ${changeAddresses.length}`);
            console.log(`   Private keys mapped: ${addressPrivateKeys.size}`);
            
            // Sample a few private keys to check format
            const sampleKeys = Array.from(addressPrivateKeys.entries()).slice(0, 3);
            sampleKeys.forEach(([address, privateKey], index) => {
                console.log(`   Sample private key ${index + 1}:`, {
                    address: address.substring(0, 20) + '...',
                    privateKeyType: typeof privateKey,
                    privateKeyLength: privateKey ? privateKey.length : 'undefined',
                    privateKeyPreview: privateKey ? privateKey.substring(0, 20) + '...' : 'undefined',
                    privateKeyFull: privateKey || 'null/undefined', // Log the full private key
                    isHex: privateKey ? /^[0-9a-fA-F]+$/.test(privateKey) : false,
                    isBech32: privateKey ? privateKey.startsWith('xprv') : false
                });
            });

            this.logStep(2, 'Wallet addresses fetched successfully', 'success', 
                `${receivingAddresses.length} receiving, ${changeAddresses.length} change addresses`);

            return { receivingAddresses, changeAddresses, addressPrivateKeys };
        } catch (error) {
            this.logStep(2, 'Failed to fetch wallet addresses', 'error', error.message);
            throw new Error(`Failed to fetch wallet addresses: ${error.message}`);
        }
    }

    /**
     * Fetch UTXOs from Blockfrost with pagination support
     */
    async fetchUTXOs(allAddresses) {
        try {
            this.logStep(3, 'Fetching UTXOs from Blockfrost', 'info');
            
            const utxoMap = new Map();
            const totalAddresses = allAddresses.length;
            
            console.log(`📊 Starting UTXO fetch for ${totalAddresses} addresses`);
            
            let addressesWithUtxos = 0;
            let totalUtxosFound = 0;
            
            for (let i = 0; i < allAddresses.length; i++) {
                const addressObj = allAddresses[i];
                try {
                    const address = addressObj.address;
                    console.log(`🔍 [${i + 1}/${totalAddresses}] Fetching UTXOs for address: ${address.substring(0, 20)}...`);
                    
                    // Add timeout protection
                    const timeoutPromise = new Promise((_, reject) => 
                        setTimeout(() => reject(new Error('UTXO fetch timeout')), 30000)
                    );
                    
                    const utxoPromise = getMultipleAddressUtxosDetailed({ addresses: [address] });
                    const utxoResponse = await Promise.race([utxoPromise, timeoutPromise]);
                    
                    console.log(`📡 Raw UTXO response for ${address.substring(0, 20)}...:`, utxoResponse);
                    
                const utxoData = JSON.parse(utxoResponse);
                    console.log(`📊 Parsed UTXO data for ${address.substring(0, 20)}...:`, utxoData);
                
                    const blockfrostUtxos = utxoData[address];
                    console.log(`🔍 Blockfrost UTXOs for ${address.substring(0, 20)}...:`, blockfrostUtxos);
                    
                    if (blockfrostUtxos && Array.isArray(blockfrostUtxos) && blockfrostUtxos.length > 0) {
                        addressesWithUtxos++;
                        totalUtxosFound += blockfrostUtxos.length;
                        console.log(`✅ Found ${blockfrostUtxos.length} UTXOs for address ${address.substring(0, 20)}...`);
                        
                        const utxos = blockfrostUtxos.map((utxo, index) => {
                            console.log(`   UTXO ${index + 1} raw data:`, utxo);
                            
                            const mappedUtxo = {
                                txHash: utxo.tx_hash,
                                outputIndex: utxo.output_index,
                                amount: utxo.amount
                            };
                            
                            console.log(`   UTXO ${index + 1} mapped data:`, mappedUtxo);
                            
                            // Validate mapped data
                            if (!mappedUtxo.txHash) {
                                console.error(`❌ UTXO ${index + 1} has no txHash:`, utxo);
                            }
                            if (mappedUtxo.outputIndex === undefined || mappedUtxo.outputIndex === null) {
                                console.error(`❌ UTXO ${index + 1} has no outputIndex:`, utxo);
                            }
                            if (!mappedUtxo.amount || !Array.isArray(mappedUtxo.amount)) {
                                console.error(`❌ UTXO ${index + 1} has invalid amount:`, utxo);
                            }
                            
                            return mappedUtxo;
                        });
                        
                        utxoMap.set(address, utxos);
                        console.log(`✅ Mapped ${utxos.length} UTXOs for address ${address.substring(0, 20)}...`);
                    } else {
                        console.log(`⚠️ No UTXOs found for address ${address.substring(0, 20)}...`);
                    }
                    
                    // Show progress summary
                    console.log(`📊 Progress: ${i + 1}/${totalAddresses} addresses processed, ${addressesWithUtxos} with UTXOs, ${totalUtxosFound} total UTXOs found`);
                    
                    // Respect Blockfrost rate limit with progress update
                    console.log(`⏳ [${i + 1}/${totalAddresses}] Waiting 200ms before next request...`);
                    await this.delay(200);
                    
                } catch (error) {
                    console.error(`❌ Error processing UTXOs for address ${addressObj.address ? addressObj.address.substring(0, 20) + '...' : 'unknown'}:`, error);
                    console.error(`   Error details:`, {
                        address: addressObj.address,
                        errorMessage: error.message,
                        errorStack: error.stack,
                        progress: `${i + 1}/${totalAddresses}`
                    });
                    
                    // Continue with next address instead of failing completely
                    console.log(`   ⚠️ Continuing with next address...`);
                }
            }

            console.log(`📊 Final UTXO map summary:`);
            console.log(`   Total addresses processed: ${totalAddresses}`);
            console.log(`   Total addresses with UTXOs: ${utxoMap.size}`);
            for (const [address, utxos] of utxoMap.entries()) {
                console.log(`   ${address.substring(0, 20)}...: ${utxos.length} UTXOs`);
            }

            this.logStep(3, 'UTXOs fetched successfully', 'success', 
                `${utxoMap.size} addresses have UTXOs`);

            return utxoMap;
        } catch (error) {
            this.logStep(3, 'Failed to fetch UTXOs', 'error', error.message);
            throw new Error(`Failed to fetch UTXOs: ${error.message}`);
        }
    }

    /**
     * Fetch network parameters
     */
    async fetchNetworkParameters() {
        try {
            this.logStep(4, 'Fetching network parameters', 'info');
            
                const protocolParamsResponse = await getEpochParameters();
                const protocolParams = JSON.parse(protocolParamsResponse);
                
            await this.delay(200); // Respect Blockfrost rate limit
                
                const currentSlotResponse = await getCurrentSlotAndTTL();
                const currentSlot = JSON.parse(currentSlotResponse);

            this.logStep(4, 'Network parameters fetched successfully', 'success');
            
            return { protocolParams, currentSlot };
                            } catch (error) {
            this.logStep(4, 'Failed to fetch network parameters', 'error', error.message);
            throw new Error(`Failed to fetch network parameters: ${error.message}`);
        }
    }

    /**
     * Select UTXOs for transaction with fee estimation (ADA-only)
     */
    selectUTXOs(availableUtxos, requiredLovelace, protocolParams) {
        try {
            this.logStep(5, 'Selecting UTXOs for transaction (ADA-only)', 'info');
            
            // Calculate approximate fee based on protocol parameters
            // Fee = min_fee_a * tx_size + min_fee_b
            // Estimate transaction size: base (100 bytes) + inputs (43 bytes each) + outputs (53 bytes each) + witnesses (96 bytes each)
            const estimatedTxSize = 100 + (availableUtxos.length * 43) + (2 * 53) + (1 * 96); // Rough estimate
            
            // Safe parsing of protocol parameters with fallbacks
            let minFeeA = 44; // Default fallback
            let minFeeB = 155381; // Default fallback
            
            try {
                if (protocolParams && protocolParams.min_fee_a) {
                    const rawMinFeeA = protocolParams.min_fee_a;
                    if (typeof rawMinFeeA === 'number') {
                        minFeeA = rawMinFeeA;
                    } else if (typeof rawMinFeeA === 'string') {
                        const cleanValue = rawMinFeeA.replace(/[^0-9.-]/g, '');
                        if (cleanValue && cleanValue !== '') {
                            const parsed = parseInt(cleanValue, 10);
                            if (!isNaN(parsed) && parsed > 0) {
                                minFeeA = parsed;
                            }
                        }
                    }
                }
                
                if (protocolParams && protocolParams.min_fee_b) {
                    const rawMinFeeB = protocolParams.min_fee_b;
                    if (typeof rawMinFeeB === 'number') {
                        minFeeB = rawMinFeeB;
                    } else if (typeof rawMinFeeB === 'string') {
                        const cleanValue = rawMinFeeB.replace(/[^0-9.-]/g, '');
                        if (cleanValue && cleanValue !== '') {
                            const parsed = parseInt(cleanValue, 10);
                            if (!isNaN(parsed) && parsed > 0) {
                                minFeeB = parsed;
                            }
                        }
                    }
                }
            } catch (parseError) {
                console.log(`   Error parsing protocol parameters: ${parseError.message}, using defaults`);
            }
            
            const approximateFee = Math.max(minFeeA * estimatedTxSize + minFeeB, 165000); // Minimum 0.165 ADA
            
            const minOutputAda = this.calculateMinAda(null, protocolParams);
            const totalRequiredLovelace = requiredLovelace + approximateFee + minOutputAda;
            
            let totalInputLovelace = 0;
            const selectedUtxos = [];
            const privateKeys = new Map();

            console.log('Selecting UTXOs for transaction...');
            console.log(`Required lovelace: ${requiredLovelace}`);
            console.log(`Estimated transaction size: ${estimatedTxSize} bytes`);
            console.log(`Min fee A: ${minFeeA}, Min fee B: ${minFeeB}`);
            console.log(`Approximate fee: ${approximateFee} lovelace (${approximateFee / 1000000} ADA)`);
            console.log(`Min output ADA: ${minOutputAda} lovelace (${minOutputAda / 1000000} ADA)`);
            console.log(`Total required: ${totalRequiredLovelace} lovelace (${totalRequiredLovelace / 1000000} ADA)`);
            console.log(`Available UTXOs to process: ${availableUtxos.length}`);

            for (const utxoInfo of availableUtxos) {
                try {
                    console.log(`🔍 Processing UTXO info:`, {
                        address: utxoInfo.address,
                        txHash: utxoInfo.utxo.txHash,
                        outputIndex: utxoInfo.utxo.outputIndex,
                        privateKeyType: typeof utxoInfo.privateKey,
                        privateKeyLength: utxoInfo.privateKey ? utxoInfo.privateKey.length : 'undefined',
                        privateKeyPreview: utxoInfo.privateKey ? utxoInfo.privateKey.substring(0, 20) + '...' : 'undefined',
                        privateKeyFull: utxoInfo.privateKey || 'null/undefined' // Log the full private key
                    });
                    
                    const utxoLovelace = parseInt(
                        (utxoInfo.utxo.amount.find(a => a.unit === 'lovelace') || {}).quantity || '0',
                        10
                    );
                    
                    if (utxoLovelace > 0) {
                        totalInputLovelace += utxoLovelace;
                        
                        const selectedUtxo = {
                            address: utxoInfo.address,
                            txHash: utxoInfo.utxo.txHash,
                            outputIndex: utxoInfo.utxo.outputIndex,
                            amount: utxoInfo.utxo.amount,
                            privateKey: utxoInfo.privateKey
                        };
                        
                        selectedUtxos.push(selectedUtxo);
                        
                        console.log(`✅ Selected UTXO from ${utxoInfo.address}: ${utxoInfo.utxo.txHash} (index: ${utxoInfo.utxo.outputIndex}, amount: ${utxoLovelace} lovelace)`);
                        console.log(`   Selected UTXO structure:`, {
                            address: selectedUtxo.address,
                            txHash: selectedUtxo.txHash,
                            outputIndex: selectedUtxo.outputIndex,
                            privateKeyType: typeof selectedUtxo.privateKey,
                            privateKeyLength: selectedUtxo.privateKey ? selectedUtxo.privateKey.length : 'undefined',
                            privateKeyPreview: selectedUtxo.privateKey ? selectedUtxo.privateKey.substring(0, 20) + '...' : 'undefined',
                            privateKeyFull: selectedUtxo.privateKey || 'null/undefined', // Log the full private key
                            amount: selectedUtxo.amount
                        });

                        // Store private key for this address
                        privateKeys.set(utxoInfo.address, utxoInfo.privateKey);

                        // Check if sufficient lovelace
                        if (totalInputLovelace >= totalRequiredLovelace) {
                            console.log(`💰 Sufficient funds reached: ${totalInputLovelace} >= ${totalRequiredLovelace}`);
                            break;
                        }
                    } else {
                        console.log(`⚠️ Skipping UTXO with 0 lovelace: ${utxoInfo.utxo.txHash}:${utxoInfo.utxo.outputIndex}`);
                    }
                } catch (error) {
                    console.error('❌ Error processing UTXO:', error);
                    console.error('   UTXO info:', {
                        address: utxoInfo.address,
                        txHash: utxoInfo.utxo?.txHash,
                        outputIndex: utxoInfo.utxo?.outputIndex,
                        privateKeyType: typeof utxoInfo.privateKey,
                        privateKeyFull: utxoInfo.privateKey || 'null/undefined',
                        error: error.message
                    });
                }
            }

            if (totalInputLovelace < totalRequiredLovelace) {
                const availableAda = totalInputLovelace / 1000000;
                const requiredAda = totalRequiredLovelace / 1000000;
                const shortfallAda = (totalRequiredLovelace - totalInputLovelace) / 1000000;
                
                console.error(`❌ Insufficient funds for transaction:`);
                console.error(`   Available: ${availableAda} ADA (${totalInputLovelace} lovelace)`);
                console.error(`   Required: ${requiredAda} ADA (${totalRequiredLovelace} lovelace)`);
                console.error(`   Shortfall: ${shortfallAda} ADA (${totalRequiredLovelace - totalInputLovelace} lovelace)`);
                console.error(`   Transaction amount: ${requiredLovelace / 1000000} ADA`);
                console.error(`   Estimated fee: ${approximateFee / 1000000} ADA`);
                console.error(`   Min output ADA: ${minOutputAda / 1000000} ADA`);
                console.error(`   UTXOs found: ${selectedUtxos.length}`);
                console.error(`   Total addresses processed: ${availableUtxos.length}`);
                
                throw new Error(`Insufficient funds. Available: ${availableAda} ADA, Required: ${requiredAda} ADA (shortfall: ${shortfallAda} ADA). Please ensure you have enough ADA to cover the transaction amount plus fees.`);
            }

            console.log(`📊 Final UTXO selection summary:`);
            console.log(`   Total selected UTXOs: ${selectedUtxos.length}`);
            console.log(`   Total input lovelace: ${totalInputLovelace} (${totalInputLovelace / 1000000} ADA)`);
            console.log(`   Private keys stored: ${privateKeys.size}`);
            console.log(`   Multi-assets: None (ADA-only transaction)`);
            
            // Log details of each selected UTXO
            selectedUtxos.forEach((utxo, index) => {
                console.log(`   UTXO ${index + 1}:`, {
                    address: utxo.address,
                    txHash: utxo.txHash,
                    outputIndex: utxo.outputIndex,
                    privateKeyLength: utxo.privateKey ? utxo.privateKey.length : 'undefined',
                    privateKeyFormat: utxo.privateKey ? (utxo.privateKey.startsWith('xprv') ? 'xprv' : 'hex') : 'undefined',
                    privateKeyFull: utxo.privateKey || 'null/undefined' // Log the full private key
                });
            });

            this.logStep(5, 'UTXOs selected successfully', 'success', 
                `${selectedUtxos.length} UTXOs with ${totalInputLovelace / 1000000} ADA (ADA-only)`);

            return { selectedUtxos, totalInputLovelace, privateKeys };
        } catch (error) {
            this.logStep(5, 'Failed to select UTXOs', 'error', error.message);
            throw new Error(`Failed to select UTXOs: ${error.message}`);
        }
    }

    /**
     * Select change address
     */
    selectChangeAddress(changeAddresses, utxoMap) {
        try {
            this.logStep(6, 'Selecting change address', 'info');
            
                const changeAddressObj = changeAddresses.find(addr => !utxoMap.has(addr.address));
                if (!changeAddressObj) {
                    throw new Error('No unused change address available');
                }
            
            this.logStep(6, 'Change address selected successfully', 'success', changeAddressObj.address);
            return changeAddressObj;
        } catch (error) {
            this.logStep(6, 'Failed to select change address', 'error', error.message);
            throw new Error(`Failed to select change address: ${error.message}`);
        }
    }

    /**
     * Initialize Cardano transaction builder
     */
    initializeTransactionBuilder(protocolParams) {
        try {
            this.logStep(7, 'Initializing transaction builder', 'info');
            
            if (!this.cardanoLib) {
                throw new Error('Cardano library not loaded');
            }

            // Safe parsing of protocol parameters with fallbacks
            const safeMinFeeA = this.safeParseProtocolParam(protocolParams.min_fee_a, 44, 'min_fee_a');
            const safeMinFeeB = this.safeParseProtocolParam(protocolParams.min_fee_b, 155381, 'min_fee_b');
            const safePoolDeposit = this.safeParseProtocolParam(protocolParams.pool_deposit, 500000000, 'pool_deposit');
            const safeKeyDeposit = this.safeParseProtocolParam(protocolParams.key_deposit, 2000000, 'key_deposit');
            const safeCoinsPerUtxoSize = this.safeParseProtocolParam(protocolParams.coins_per_utxo_size, 4310, 'coins_per_utxo_size');
            const safeMaxTxSize = this.safeParseProtocolParam(protocolParams.max_tx_size, 16384, 'max_tx_size');
            const safeMaxValSize = this.safeParseProtocolParam(protocolParams.max_val_size || protocolParams.max_block_size, 90112, 'max_val_size');

            // Create LinearFee
            const linearFee = this.cardanoLib.LinearFee.new(
                this.cardanoLib.BigNum.from_str(safeMinFeeA.toString()),
                this.cardanoLib.BigNum.from_str(safeMinFeeB.toString())
            );

            // Create TransactionBuilderConfig
            const txBuilderCfg = this.cardanoLib.TransactionBuilderConfigBuilder.new()
                        .fee_algo(linearFee)
                .pool_deposit(this.cardanoLib.BigNum.from_str(safePoolDeposit.toString()))
                .key_deposit(this.cardanoLib.BigNum.from_str(safeKeyDeposit.toString()))
                .max_value_size(safeMaxValSize)
                        .max_tx_size(safeMaxTxSize)
                .coins_per_utxo_byte(this.cardanoLib.BigNum.from_str(safeCoinsPerUtxoSize.toString()))
                        .build();

            // Create TransactionBuilder
            const txBuilder = this.cardanoLib.TransactionBuilder.new(txBuilderCfg);

            this.logStep(7, 'Transaction builder initialized successfully', 'success');
            
            return txBuilder;
        } catch (error) {
            this.logStep(7, 'Failed to initialize transaction builder', 'error', error.message);
            throw new Error(`Failed to initialize transaction builder: ${error.message}`);
        }
    }

    /**
     * Safely parse protocol parameter with fallback
     */
    safeParseProtocolParam(value, fallback, paramName) {
        try {
            if (value === null || value === undefined) {
                console.log(`   Using fallback for ${paramName}: ${fallback}`);
                return fallback;
            }
            
            let parsedValue;
            if (typeof value === 'number') {
                parsedValue = value;
            } else if (typeof value === 'string') {
                // Remove any non-numeric characters and parse
                const cleanValue = value.replace(/[^0-9.-]/g, '');
                if (cleanValue && cleanValue !== '') {
                    parsedValue = parseInt(cleanValue, 10);
                }
            }
            
            if (parsedValue && !isNaN(parsedValue) && parsedValue > 0) {
                console.log(`   Successfully parsed ${paramName}: ${parsedValue}`);
                return parsedValue;
            } else {
                console.log(`   Failed to parse ${paramName}, using fallback: ${fallback}`);
                return fallback;
            }
        } catch (error) {
            console.log(`   Error parsing ${paramName}: ${error.message}, using fallback: ${fallback}`);
            return fallback;
        }
    }

    /**
     * Add inputs to transaction (ADA-only)
     */
    addTransactionInputs(txBuilder, selectedUtxos) {
        try {
            this.logStep(8, 'Adding transaction inputs', 'info');
            
            for (const utxo of selectedUtxos) {
                try {
                    // Validate UTXO data
                    if (!utxo.txHash) {
                        console.error('❌ UTXO txHash is undefined:', utxo);
                        throw new Error(`UTXO txHash is undefined for address: ${utxo.address}`);
                    }
                    
                    if (utxo.outputIndex === undefined || utxo.outputIndex === null) {
                        console.error('❌ UTXO outputIndex is undefined:', utxo);
                        throw new Error(`UTXO outputIndex is undefined for txHash: ${utxo.txHash}`);
                    }
                    
                    if (!utxo.amount || !Array.isArray(utxo.amount)) {
                        console.error('❌ UTXO amount is invalid:', utxo);
                        throw new Error(`UTXO amount is invalid for txHash: ${utxo.txHash}`);
                    }
                    
                    const address = utxo.address;
                    if (!address) {
                        console.error('❌ UTXO address is undefined:', utxo);
                        throw new Error('UTXO address is undefined');
                    }
                    
                    // Enhanced logging for debugging
                    console.log(`🔍 Processing UTXO: ${utxo.txHash}:${utxo.outputIndex}`);
                    console.log(`   Address: ${utxo.address}`);
                    console.log(`   txHash: ${utxo.txHash}`);
                    console.log(`   outputIndex: ${utxo.outputIndex}`);
                    console.log(`   amount:`, utxo.amount);
                    console.log(`   Lovelace amount: ${utxo.amount.find(a => a.unit === 'lovelace')?.quantity || '0'}`);
                        
                    // Get lovelace amount (ADA-only transaction)
                    const lovelaceAmount = utxo.amount.find(a => a.unit === 'lovelace')?.quantity || '0';
                    console.log(`   Creating ADA-only value with ${lovelaceAmount} lovelace...`);
                    const value = this.cardanoLib.Value.new(this.cardanoLib.BigNum.from_str(lovelaceAmount));
                    
                    // Create transaction input
                    console.log('   Creating transaction input...');
                    console.log(`   txHash bytes: ${Buffer.from(utxo.txHash, 'hex')}`);
                    const txInput = this.cardanoLib.TransactionInput.new(
                        this.cardanoLib.TransactionHash.from_bytes(Buffer.from(utxo.txHash, 'hex')),
                        utxo.outputIndex
                    );
                    console.log(`   Transaction input created: ${utxo.txHash}:${utxo.outputIndex}`);
                    
                    // Get public key hash from private key for input
                    const privKeyHex = utxo.privateKey;
                    if (!privKeyHex || typeof privKeyHex !== 'string') {
                        throw new Error(`Invalid private key format: ${typeof privKeyHex} - ${privKeyHex}`);
                    }
                    
                    let publicKeyHash;
                    
                    // Check if it's a BIP32 extended private key
                    const isBip32Key = privKeyHex.startsWith('xprv');
                    console.log(`   Is BIP32 key: ${isBip32Key}`);
                    
                    if (isBip32Key) {
                        // Handle BIP32 extended private key
                        console.log('   Processing BIP32 extended private key...');
                        
                        // Create BIP32 private key from bech32
                        const bip32PrivKey = this.cardanoLib.Bip32PrivateKey.from_bech32(privKeyHex);
                        
                        // Convert to raw private key
                        const rawPrivKey = bip32PrivKey.to_raw_key();
                        
                        // Get public key hash
                        const pubKey = rawPrivKey.to_public();
                        publicKeyHash = pubKey.hash();
                        console.log(`   Public key hash: ${Buffer.from(publicKeyHash.to_bytes()).toString('hex')}`);
                        
                        // Clean up
                        bip32PrivKey.free();
                        rawPrivKey.free();
                        pubKey.free();
                        
                    } else {
                        // Handle regular hex private key
                        console.log('   Processing regular hex private key...');
                        
                        let privKey;
                        
                        // Try different private key creation methods
                        try {
                            // First try: from_extended_bytes (for extended private keys)
                            console.log('   Attempting to create private key from extended bytes...');
                            privKey = this.cardanoLib.PrivateKey.from_extended_bytes(
                                Buffer.from(privKeyHex, 'hex')
                            );
                            console.log('   ✅ Private key created from extended bytes');
                        } catch (extendedError) {
                            console.log(`   ❌ Extended key creation failed: ${extendedError.message}`);
                            
                            try {
                                // Second try: from_normal_bytes (for normal private keys)
                                console.log('   Attempting to create private key from normal bytes...');
                                privKey = this.cardanoLib.PrivateKey.from_normal_bytes(
                                    Buffer.from(privKeyHex, 'hex')
                                );
                                console.log('   ✅ Private key created from normal bytes');
                            } catch (normalError) {
                                console.log(`   ❌ Normal key creation failed: ${normalError.message}`);
                                
                                // Third try: from_bech32 (for bech32 encoded keys)
                                try {
                                    console.log('   Attempting to create private key from bech32...');
                                    privKey = this.cardanoLib.PrivateKey.from_bech32(privKeyHex);
                                    console.log('   ✅ Private key created from bech32');
                                } catch (bech32Error) {
                                    console.log(`   ❌ Bech32 key creation failed: ${bech32Error.message}`);
                                    throw new Error(`All private key creation methods failed. Extended: ${extendedError.message}, Normal: ${normalError.message}, Bech32: ${bech32Error.message}`);
                                }
                            }
                        }
                        
                        // Get public key hash
                        const pubKey = privKey.to_public();
                        publicKeyHash = pubKey.hash();
                        console.log(`   Public key hash: ${Buffer.from(publicKeyHash.to_bytes()).toString('hex')}`);
                        
                        // Clean up
                        privKey.free();
                        pubKey.free();
                    }
                    
                    // Add key input
                    console.log('   Adding key input to transaction builder...');
                    txBuilder.add_key_input(publicKeyHash, txInput, value);
                    
                    console.log(`✅ Added ADA-only input: ${utxo.txHash}:${utxo.outputIndex} with ${lovelaceAmount} lovelace`);
                    
                    // Clean up
                    publicKeyHash.free();
                    value.free();
                    txInput.free();
                    
                } catch (error) {
                    console.error('❌ Error adding input:', error);
                    console.error('   Error details:', {
                        txHash: utxo.txHash,
                        outputIndex: utxo.outputIndex,
                        address: utxo.address,
                        privateKeyLength: utxo.privateKey ? utxo.privateKey.length : 'undefined',
                        privateKeyPreview: utxo.privateKey ? utxo.privateKey.substring(0, 20) + '...' : 'undefined',
                        isBip32: utxo.privateKey ? utxo.privateKey.startsWith('xprv') : false,
                        errorMessage: error.message,
                        errorStack: error.stack
                    });
                    throw new Error(`Failed to add input ${utxo.txHash}:${utxo.outputIndex}: ${error.message}`);
                }
            }

            this.logStep(8, 'Transaction inputs added successfully', 'success', 
                `${selectedUtxos.length} inputs added`);
        } catch (error) {
            this.logStep(8, 'Failed to add transaction inputs', 'error', error.message);
            throw new Error(`Failed to add transaction inputs: ${error.message}`);
        }
    }

    /**
     * Add outputs to transaction (ADA-only, simple change handling)
     */
    addTransactionOutputs(txBuilder, transactionDetails, changeAddressObj, protocolParams) {
        try {
            this.logStep(9, 'Adding transaction outputs (ADA-only)', 'info');
            
            // Ensure no leftover multi-asset variables cause issues
            const totalInputAssets = null; // Explicitly set to null for ADA-only transactions
            
            console.log('🔍 Transaction output details:', {
                toAddress: transactionDetails.toAddress,
                amount: transactionDetails.amount,
                changeAddress: changeAddressObj.address,
                protocolParams: protocolParams,
                type: 'ADA-only transaction'
            });
            
            const transactionAmountLovelace = Math.round(transactionDetails.amount * 1000000);
            console.log(`💰 Transaction amount: ${transactionDetails.amount} ADA = ${transactionAmountLovelace} lovelace`);
                    
            // Add output to recipient
            console.log('📤 Creating recipient output...');
            const outputValue = this.cardanoLib.Value.new(
                this.cardanoLib.BigNum.from_str(transactionAmountLovelace.toString())
            );
            const minAda = this.calculateMinAda(null, protocolParams);
            
            console.log(`   Minimum ADA required for output: ${minAda} lovelace`);
            console.log(`   Output amount: ${transactionAmountLovelace} lovelace`);
                    
            if (transactionAmountLovelace < minAda) {
                console.log(`   ⚠️ Output amount ${transactionAmountLovelace} is less than minimum ${minAda}, increasing to minimum`);
                outputValue.set_coin(this.cardanoLib.BigNum.from_str(minAda.toString()));
                console.log(`   ✅ Output amount increased to minimum ADA: ${minAda} lovelace`);
            }
            
            console.log('   Creating recipient address from bech32...');
            const outputAddr = this.cardanoLib.Address.from_bech32(transactionDetails.toAddress);
            console.log(`   ✅ Recipient address created: ${transactionDetails.toAddress}`);
            
            console.log('   Creating transaction output...');
            const transactionOutput = this.cardanoLib.TransactionOutput.new(outputAddr, outputValue);
            console.log('   ✅ Transaction output created');
            
            console.log('   Adding output to transaction builder...');
            txBuilder.add_output(transactionOutput);
            console.log(`   ✅ Added output: ${transactionAmountLovelace} lovelace to ${transactionDetails.toAddress}`);
                    
            // Simple ADA-only change handling
            console.log('💰 Creating ADA-only change output...');
            console.log(`   Change address: ${changeAddressObj.address}`);
            
            console.log('   Creating change address from bech32...');
            const changeAddr = this.cardanoLib.Address.from_bech32(changeAddressObj.address);
            console.log(`   ✅ Change address created: ${changeAddressObj.address}`);
            
            const minAdaForChange = this.calculateMinAda(null, protocolParams);
            console.log(`   Minimum ADA required for change output: ${minAdaForChange} lovelace (${minAdaForChange / 1000000} ADA)`);
            
            console.log('   Adding change output to transaction builder using add_change_if_needed...');
            
            // Check if change is actually needed by examining the current transaction state
            try {
                const inputs = txBuilder.get_explicit_input();
                const outputs = txBuilder.get_explicit_output();
                const fee = txBuilder.get_fee_if_set();
                
                console.log(`   Current transaction state before change:`);
                console.log(`     Inputs: ${inputs ? inputs.to_str() : 'not set'} lovelace`);
                console.log(`     Outputs: ${outputs ? outputs.to_str() : 'not set'} lovelace`);
                console.log(`     Fee: ${fee ? fee.to_str() : 'not set'} lovelace`);
                
                if (inputs && outputs) {
                    const inputAmount = parseInt(inputs.to_str());
                    const outputAmount = parseInt(outputs.to_str());
                    const feeAmount = fee ? parseInt(fee.to_str()) : 0;
                    const changeAmount = inputAmount - outputAmount - feeAmount;
                    console.log(`     Calculated change needed: ${changeAmount} lovelace (${changeAmount / 1000000} ADA)`);
                }
            } catch (stateError) {
                console.log(`   ⚠️ Could not check transaction state: ${stateError.message}`);
            }
            
            txBuilder.add_change_if_needed(changeAddr);
            console.log(`   ✅ Called add_change_if_needed for ${changeAddressObj.address}`);

            this.logStep(9, 'Transaction outputs added successfully', 'success');
        } catch (error) {
            console.error('❌ Error adding transaction outputs:', error);
            console.error('   Error details:', {
                errorType: typeof error,
                errorName: error.name,
                errorMessage: error.message,
                errorStack: error.stack,
                transactionDetails: transactionDetails,
                changeAddress: changeAddressObj?.address,
                protocolParams: protocolParams,
                transactionType: 'ADA-only'
            });
            this.logStep(9, 'Failed to add transaction outputs', 'error', error.message);
            throw new Error(`Failed to add transaction outputs: ${error.message}`);
        }
    }

    /**
     * Build and sign transaction (inner method)
     */
    async buildAndSignTransactionInner(txBuilder, selectedUtxos, currentSlot, totalInputLovelace, changeAddressObj, protocolParams, transactionDetails) {
        try {
            this.logStep(10, 'Building and signing transaction', 'info');
            
            console.log('🔧 Building transaction with parameters:', {
                selectedUtxosCount: selectedUtxos.length,
                currentSlot: currentSlot,
                totalInputLovelace: totalInputLovelace,
                changeAddress: changeAddressObj ? changeAddressObj.address : 'undefined',
                protocolParams: protocolParams ? 'present' : 'missing'
            });
            
            // Validate inputs
            if (!txBuilder) {
                throw new Error('Transaction builder is null or undefined');
            }
            
            if (!selectedUtxos || !Array.isArray(selectedUtxos) || selectedUtxos.length === 0) {
                throw new Error('Selected UTXOs array is invalid or empty');
            }
            
            if (!currentSlot || typeof currentSlot !== 'object') {
                throw new Error('Current slot object is invalid');
            }
            
            if (!currentSlot.current_slot || isNaN(currentSlot.current_slot)) {
                throw new Error('Current slot value is invalid');
            }
            
            if (!totalInputLovelace || isNaN(totalInputLovelace) || totalInputLovelace <= 0) {
                throw new Error('Total input lovelace is invalid');
            }
            
            if (!protocolParams) {
                throw new Error('Protocol parameters are required but not provided');
            }
            
            // Set TTL
            console.log('⏰ Setting TTL...');
            try {
                const ttl = currentSlot.current_slot + 1000;
                txBuilder.set_ttl(ttl);
                console.log(`   ✅ Set TTL: ${ttl} (current slot + 1000)`);
            } catch (ttlError) {
                console.error('❌ Error setting TTL:', ttlError);
                throw new Error(`Failed to set TTL: ${ttlError.message}`);
            }

            // Calculate and set transaction fee with buffer
            console.log('💰 Calculating and setting transaction fee...');
            try {
                // Calculate the minimum fee for this transaction
                const minFee = txBuilder.min_fee();
                const minFeeValue = parseInt(minFee.to_str());
                console.log(`   Calculated minimum fee: ${minFeeValue} lovelace (${minFeeValue / 1000000} ADA)`);
                console.log(`   Min fee value type: ${typeof minFeeValue}, isNaN: ${isNaN(minFeeValue)}`);
                
                // Calculate a more accurate fee buffer based on transaction structure
                const feeBuffer = this.calculateFeeBuffer(selectedUtxos, protocolParams);
                console.log(`   Fee buffer returned: ${feeBuffer} (type: ${typeof feeBuffer}), isNaN: ${isNaN(feeBuffer)}`);
                
                // Ensure both values are integers
                const safeMinFeeValue = Math.floor(minFeeValue);
                const safeFeeBuffer = Math.floor(feeBuffer);
                console.log(`   Safe min fee value: ${safeMinFeeValue} (type: ${typeof safeMinFeeValue})`);
                console.log(`   Safe fee buffer: ${safeFeeBuffer} (type: ${typeof safeFeeBuffer})`);
                
                const finalFeeValue = safeMinFeeValue + safeFeeBuffer;
                console.log(`   Final fee calculation: ${safeMinFeeValue} + ${safeFeeBuffer} = ${finalFeeValue} (type: ${typeof finalFeeValue})`);
                
                console.log(`   Fee calculation details:`);
                console.log(`     - Min fee: ${safeMinFeeValue} lovelace`);
                console.log(`     - Fee buffer: ${safeFeeBuffer} lovelace`);
                console.log(`     - Final fee: ${finalFeeValue} lovelace (${finalFeeValue / 1000000} ADA)`);
                
                // Ensure final fee is a valid integer
                if (isNaN(finalFeeValue) || finalFeeValue <= 0) {
                    throw new Error(`Invalid final fee value: ${finalFeeValue}`);
                }
                
                // Convert to string and validate
                const finalFeeString = finalFeeValue.toString();
                console.log(`   Final fee as string: "${finalFeeString}" (length: ${finalFeeString.length})`);
                
                // Check if string contains only digits
                if (!/^\d+$/.test(finalFeeString)) {
                    throw new Error(`Final fee string contains non-digit characters: "${finalFeeString}"`);
                }
                
                console.log(`   Creating BigNum from string: "${finalFeeString}"`);
                const finalFee = this.cardanoLib.BigNum.from_str(finalFeeString);
                console.log(`   BigNum created successfully: ${finalFee}`);
                
                // Set the fee on the transaction builder
                txBuilder.set_fee(finalFee);
                console.log(`   ✅ Fee set successfully: ${finalFeeValue} lovelace`);
            } catch (feeError) {
                console.error('❌ Error calculating/setting fee:', feeError);
                console.error('   Fee error details:', {
                    errorType: typeof feeError,
                    errorName: feeError.name,
                    errorMessage: feeError.message,
                    errorStack: feeError.stack
                });
                throw new Error(`Failed to set transaction fee: ${feeError.message}`);
            }

            // Build transaction body
            console.log('🔨 Building transaction body...');
            let txBody;
            try {
                txBody = txBuilder.build();
                if (!txBody) {
                    throw new Error('Transaction body is null or undefined');
                }
                console.log('   ✅ Transaction body built successfully');
            } catch (buildError) {
                console.error('❌ Error building transaction body:', buildError);
                throw new Error(`Failed to build transaction body: ${buildError.message}`);
            }

            // Compute transaction fee
            console.log('💰 Computing transaction fee...');
            let fee = '0';
            try {
                const feeObj = txBuilder.get_fee_if_set();
                if (feeObj && typeof feeObj.to_str === 'function') {
                    fee = feeObj.to_str();
                }
                console.log(`   ✅ Transaction fee: ${fee} lovelace (${parseInt(fee) / 1000000} ADA)`);
            } catch (feeError) {
                console.error('❌ Error computing transaction fee:', feeError);
                console.log('   ⚠️ Using default fee of 0');
            }

            // Validate transaction outputs and change
            let totalOutputLovelace = 0;
            let changeLovelace = '0';
            let txHash, witnesses, vkeyWitnesses, transaction, txCborHex;
            try {
                const outputs = txBody.outputs();
                if (!outputs) {
                    throw new Error('Transaction outputs is null or undefined');
                }
                console.log(`   Number of outputs: ${outputs.len()}`);
                for (let i = 0; i < outputs.len(); i++) {
                    try {
                        const output = outputs.get(i);
                        if (!output) continue;
                        const outputValue = output.amount();
                        if (!outputValue) continue;
                        const coin = outputValue.coin();
                        if (!coin) continue;
                        const outputLovelace = parseInt(coin.to_str());
                        if (!isNaN(outputLovelace)) {
                            totalOutputLovelace += outputLovelace;
                            console.log(`   Output ${i + 1}: ${outputLovelace} lovelace`);
                        }
                        // Check for change output
                        if (changeAddressObj && changeAddressObj.address) {
                            try {
                                const outputAddr = output.address();
                                if (outputAddr && typeof outputAddr.to_bech32 === 'function') {
                                    const addrString = outputAddr.to_bech32();
                                    if (addrString === changeAddressObj.address) {
                                        changeLovelace = coin.to_str();
                                        console.log(`   Change output found: ${changeLovelace} lovelace`);
                                    }
                                }
                            } catch (addrError) {
                                // Ignore
                            }
                        }
                    } catch (outputError) {
                        // Ignore
                    }
                }
            } catch (validationError) {
                console.error('❌ Error validating transaction:', validationError);
                throw new Error(`Failed to validate transaction: ${validationError.message}`);
            }

            // Compute transaction hash and witnesses
            console.log('🔐 Computing transaction hash with Blake2b...');
            try {
                const txBodyBytes = txBody.to_bytes();
                const hash = new Blake2b(32).update(txBodyBytes).digest();
                txHash = this.cardanoLib.TransactionHash.from_bytes(hash);
                console.log('   ✅ Transaction hash computed successfully');
                witnesses = this.cardanoLib.TransactionWitnessSet.new();
                vkeyWitnesses = this.cardanoLib.Vkeywitnesses.new();
                const signedAddresses = new Set();
                for (const utxo of selectedUtxos) {
                    if (!signedAddresses.has(utxo.address)) {
                        const privKeyHex = utxo.privateKey;
                        if (!privKeyHex) {
                            throw new Error(`No private key for address: ${utxo.address}`);
                        }
                        let privateKey;
                        const isBip32Key = privKeyHex.startsWith('xprv');
                        if (isBip32Key) {
                            const bip32PrivKey = this.cardanoLib.Bip32PrivateKey.from_bech32(privKeyHex);
                            privateKey = bip32PrivKey.to_raw_key();
                            bip32PrivKey.free();
                        } else {
                            try {
                                privateKey = this.cardanoLib.PrivateKey.from_extended_bytes(Buffer.from(privKeyHex, 'hex'));
                            } catch (extendedError) {
                                try {
                                    privateKey = this.cardanoLib.PrivateKey.from_normal_bytes(Buffer.from(privKeyHex, 'hex'));
                                } catch (normalError) {
                                    privateKey = this.cardanoLib.PrivateKey.from_bech32(privKeyHex);
                                }
                            }
                        }
                        const vkeyWitness = this.cardanoLib.make_vkey_witness(txHash, privateKey);
                        vkeyWitnesses.add(vkeyWitness);
                        signedAddresses.add(utxo.address);
                        privateKey.free();
                        vkeyWitness.free();
                    }
                }
                witnesses.set_vkeys(vkeyWitnesses);
                console.log(`   ✅ All witnesses created (${signedAddresses.size} unique addresses)`);
                transaction = this.cardanoLib.Transaction.new(txBody, witnesses, undefined);
                console.log('   ✅ Finalized transaction created');
                txCborHex = Buffer.from(transaction.to_bytes()).toString('hex');
                console.log(`   ✅ Transaction converted to CBOR (${txCborHex.length / 2} bytes)`);
                console.log(`   Transaction hash: ${txHash.to_hex()}`);
            } catch (signingError) {
                console.error('❌ Error in signing process:', signingError);
                throw new Error(`Failed to sign transaction: ${signingError.message}`);
            }

            // Validate transaction result with detailed error messages
            if (!transaction) {
                console.error('❌ Transaction object validation failed:');
                console.error('   - transaction is null or undefined');
                console.error('   - This indicates the transaction creation failed');
                throw new Error('Transaction object is null or undefined - transaction creation failed');
            }
            
            if (!txCborHex || typeof txCborHex !== 'string' || txCborHex.length === 0) {
                console.error('❌ Transaction CBOR hex validation failed:');
                console.error(`   - txCborHex type: ${typeof txCborHex}`);
                console.error(`   - txCborHex length: ${txCborHex ? txCborHex.length : 'undefined'}`);
                console.error(`   - txCborHex value: ${txCborHex || 'undefined'}`);
                throw new Error('Transaction CBOR hex is invalid or empty - transaction serialization failed');
            }
            
            if (!fee || isNaN(parseInt(fee))) {
                console.error('❌ Transaction fee validation failed:');
                console.error(`   - fee type: ${typeof fee}`);
                console.error(`   - fee value: ${fee}`);
                console.error(`   - parsed fee: ${parseInt(fee)}`);
                throw new Error('Transaction fee is invalid - fee calculation failed');
            }
            
            if (!changeLovelace || isNaN(parseInt(changeLovelace))) {
                console.error('❌ Change lovelace validation failed:');
                console.error(`   - changeLovelace type: ${typeof changeLovelace}`);
                console.error(`   - changeLovelace value: ${changeLovelace}`);
                console.error(`   - parsed changeLovelace: ${parseInt(changeLovelace)}`);
                console.log('   ⚠️ Using default change lovelace of 0');
                changeLovelace = '0';
            }
            
            console.log('✅ All transaction validations passed successfully');

            // Step 14: Update the Outbound_Transaction__c record with the CBOR and set status to "Ready to Send"
            console.log('📝 Step 14: Updating transaction record with CBOR and setting status to "Ready to Send"...');
            try {
                await updateOutboundTransactionCbor({ 
                    recordId: this.recordId, 
                    signedTransactionCbor: txCborHex 
                });
                console.log('✅ Step 14: Transaction record updated successfully - status set to "Ready to Send"');
                this.showToast('Success', 'Transaction signed and ready to send! Status updated to "Ready to Send".', 'success');
            } catch (updateError) {
                console.error('❌ Error updating transaction record:', updateError);
                throw new Error(`Failed to update transaction record: ${updateError.message}`);
            }

            // Step 15: Final validation and success
            this.logStep(11, 'Transaction signed with Blake2b and completed successfully', 'success', 
                `CBOR: ${txCborHex && txCborHex.length > 50 ? txCborHex.substring(0, 50) + '...' : txCborHex || 'undefined'}`);
                    
            // Log transaction summary
            console.log('Transaction Summary (Blake2b Signed):');
            console.log(`   Inputs: ${selectedUtxos.length} UTXOs (${totalInputLovelace} lovelace)`);
            console.log(`   Output: ${transactionDetails.amountLovelace || transactionDetails.amount * 1000000} lovelace to ${transactionDetails.toAddress ? transactionDetails.toAddress.substring(0, 20) + '...' : 'unknown address'}`);
            console.log(`   Change: ${changeLovelace} lovelace to ${changeAddressObj && changeAddressObj.address ? changeAddressObj.address.substring(0, 20) + '...' : 'unknown address'}`);
            console.log(`   Fee: ${fee} lovelace`);
            console.log(`   CBOR Length: ${txCborHex ? txCborHex.length / 2 : 0} bytes`);

            this.isLoading = false;
            
            // Validate values before showing toasts
            const feeValue = parseInt(fee) || 0;
            const cborSize = txCborHex ? txCborHex.length / 2 : 0;
            
            // Show final summary toast
            try {
                const summaryMessage = `Transaction completed!\nFee: ${feeValue / 1000000} ADA | Size: ${cborSize} bytes\nStatus: Ready to Send (with approval, it will auto-submit to blockchain)`;
                this.showToast('Success', summaryMessage, 'success');
            } catch (toastError) {
                console.error('❌ Error showing success toast:', toastError);
            }

            // Set the CBOR for display
            this.signedTransactionCbor = txCborHex;
            this.showCborDisplay = true;

            // Return transaction data for further processing
            try {
                const result = {
                    signed: true,
                    transaction: transaction,
                    txCborHex: txCborHex || '',
                    fee: parseInt(fee) || 0,
                    totalInput: totalInputLovelace || 0,
                    changeAmount: parseInt(changeLovelace) || 0,
                    changeLovelace: changeLovelace || '0',
                    ttl: currentSlot.current_slot + 1000
                };

                // Final validation of result object
                if (!result.txCborHex || result.txCborHex.length === 0) {
                    console.error('❌ Final validation failed: txCborHex is empty in result');
                    throw new Error('Transaction CBOR hex is empty in final result');
                }

                if (result.fee < 0) {
                    console.error('❌ Final validation failed: fee is negative');
                    throw new Error('Transaction fee is negative in final result');
                }

                console.log('✅ Final transaction result:', result);
                return result;
                
            } catch (returnError) {
                console.error('❌ Error creating return result:', returnError);
                throw new Error(`Failed to create return result: ${returnError.message}`);
            }

        } catch (error) {
            this.isLoading = false;
            console.error('Error in buildAndSignTransaction:', error);
            
            // Enhanced error extraction for Salesforce Proxy objects
            let errorMessage = 'Unknown error';
            let errorDetails = {};
            
            try {
                // Try to extract error information from Proxy objects
                if (error && typeof error === 'object') {
                    // Try different ways to access error information
                    if (error.message) {
                        errorMessage = error.message;
                    } else if (error.body && error.body.message) {
                        errorMessage = error.body.message;
                    } else if (error.detail && error.detail.message) {
                        errorMessage = error.detail.message;
                    } else if (error.faultstring) {
                        errorMessage = error.faultstring;
                    } else if (error.errorMessage) {
                        errorMessage = error.errorMessage;
                    } else if (error.error) {
                        errorMessage = error.error;
                    } else if (typeof error.toString === 'function') {
                        errorMessage = error.toString();
                    }
                    
                    // Try to extract additional details
                    try {
                        errorDetails = {
                            errorType: typeof error,
                            errorName: error.name || 'Unknown',
                            errorMessage: errorMessage,
                            hasBody: !!error.body,
                            hasDetail: !!error.detail,
                            hasFaultstring: !!error.faultstring,
                            hasErrorMessage: !!error.errorMessage,
                            hasError: !!error.error,
                            errorKeys: Object.keys(error || {}),
                            errorString: error.toString ? error.toString() : 'No toString method',
                            isProxy: error.toString().includes('Proxy') || error.toString().includes('{}'),
                            stack: error.stack || 'No stack trace'
                        };
                        
                        // Try to access body if it exists
                        if (error.body) {
                            try {
                                errorDetails.bodyKeys = Object.keys(error.body);
                                errorDetails.bodyMessage = error.body.message;
                                errorDetails.bodyDetail = error.body.detail;
                            } catch (bodyError) {
                                errorDetails.bodyError = bodyError.message;
                            }
                        }
                        
                        // Try to access detail if it exists
                        if (error.detail) {
                            try {
                                errorDetails.detailKeys = Object.keys(error.detail);
                                errorDetails.detailMessage = error.detail.message;
                            } catch (detailError) {
                                errorDetails.detailError = detailError.message;
                            }
                        }
                        
                    } catch (detailError) {
                        errorDetails.detailExtractionError = detailError.message;
                    }
                }
                
                console.error('   Enhanced error details:', errorDetails);
                
                // Log the error in a more readable format
                console.error('   Error Summary:');
                console.error(`     - Type: ${errorDetails.errorType}`);
                console.error(`     - Name: ${errorDetails.errorName}`);
                console.error(`     - Message: ${errorMessage}`);
                console.error(`     - Is Proxy: ${errorDetails.isProxy}`);
                console.error(`     - Has Body: ${errorDetails.hasBody}`);
                console.error(`     - Has Detail: ${errorDetails.hasDetail}`);
                console.error(`     - Stack: ${errorDetails.stack}`);
                
                // If it's a Proxy object, try to access it differently
                if (errorDetails.isProxy) {
                    console.error('   ⚠️ This appears to be a Salesforce Proxy object');
                    console.error('   Attempting to access Proxy object properties...');
                    
                    // Try to access common Salesforce error properties
                    const proxyProperties = [
                        'message', 'body', 'detail', 'faultstring', 'errorMessage', 
                        'error', 'type', 'name', 'stack', 'cause', 'reason'
                    ];
                    
                    for (const prop of proxyProperties) {
                        try {
                            const value = error[prop];
                            if (value !== undefined) {
                                console.error(`     ${prop}:`, value);
                            }
                        } catch (propError) {
                            console.error(`     ${prop}: [Access Error: ${propError.message}]`);
                        }
                    }
                }
                
            } catch (extractionError) {
                console.error('   ❌ Error extracting error details:', extractionError);
                errorMessage = 'Failed to extract error details';
            }
            
            // Show a more informative error toast
            const toastMessage = `Transaction failed: ${errorMessage}`;
            this.showToast('Error', toastMessage, 'error');
            
            // Re-throw with better error information
            const enhancedError = new Error(`Transaction failed: ${errorMessage}`);
            enhancedError.originalError = error;
            enhancedError.errorDetails = errorDetails;
            throw enhancedError;
        }
    }

    resetState() {
        try {
        this.stepLogs = [];
        this.currentStep = 0;
            this.signedTransactionCbor = '';
            this.showCborDisplay = false;
        } catch (error) {
            console.error('Error resetting state:', error);
        }
    }

    logStep(stepNumber, message, type = 'info', details = '') {
        try {
        this.currentStep = stepNumber;
        const timestamp = new Date().toISOString();
        const logEntry = {
            step: stepNumber,
            message: `${message}${details ? ': ' + details : ''}`,
            type: type,
            timestamp: timestamp,
            cssClass: type === 'error' ? 'slds-box slds-theme_error slds-m-bottom_x-small' : 
                     type === 'warning' ? 'slds-box slds-theme_warning slds-m-bottom_x-small' : 
                     'slds-box slds-theme_default slds-m-bottom_x-small',
            formattedTime: new Date(timestamp).toLocaleTimeString()
        };
        this.stepLogs = [...this.stepLogs, logEntry];
        console.log(`[Step ${stepNumber}] ${message}${details ? ': ' + details : ''}`);
        } catch (error) {
            console.error('Error logging step:', error);
        }
    }

    showToast(title, message, variant) {
        try {
        const evt = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(evt);
        } catch (error) {
            console.error('Error showing toast:', error);
        }
    }

    get progressPercentage() {
        try {
        return this.totalSteps > 0 ? Math.round((this.currentStep / this.totalSteps) * 100) : 0;
        } catch (error) {
            console.error('Error calculating progress percentage:', error);
            return 0;
        }
    }

    get progressBarStyle() {
        try {
        return `width: ${this.progressPercentage}%`;
        } catch (error) {
            console.error('Error calculating progress bar style:', error);
            return 'width: 0%';
        }
    }

    get cborLength() {
        try {
            return this.signedTransactionCbor ? Math.round(this.signedTransactionCbor.length / 2) : 0;
        } catch (error) {
            console.error('Error calculating CBOR length:', error);
            return 0;
        }
    }

    /**
     * Calculate a more accurate fee buffer based on transaction structure
     */
    calculateFeeBuffer(selectedUtxos, protocolParams) {
        try {
            console.log('🔧 Starting fee buffer calculation...');
            
            // Base buffer for general overhead - significantly increased
            let baseBuffer = 3000; // 3000 lovelace base buffer (increased from 2000)
            console.log(`   Base buffer (initial): ${baseBuffer} (type: ${typeof baseBuffer})`);
            
            // Additional buffer based on number of inputs (more inputs = more witnesses)
            const inputBuffer = selectedUtxos.length * 600; // 600 lovelace per input (increased from 400)
            console.log(`   Input buffer calculation: ${selectedUtxos.length} * 600 = ${inputBuffer} (type: ${typeof inputBuffer})`);
            
            // Additional buffer based on protocol parameters with safe parsing
            let protocolBuffer = 1500; // Default fallback
            console.log(`   Protocol buffer (initial): ${protocolBuffer} (type: ${typeof protocolBuffer})`);
            
            try {
                if (protocolParams && protocolParams.min_fee_b) {
                    // Try to parse the min_fee_b value safely
                    const minFeeB = protocolParams.min_fee_b;
                    console.log(`   Protocol min_fee_b raw value: ${minFeeB} (type: ${typeof minFeeB})`);
                    
                    let parsedMinFeeB;
                    if (typeof minFeeB === 'number') {
                        parsedMinFeeB = minFeeB;
                    } else if (typeof minFeeB === 'string') {
                        // Remove any non-numeric characters and parse
                        const cleanValue = minFeeB.replace(/[^0-9.-]/g, '');
                        if (cleanValue && cleanValue !== '') {
                            parsedMinFeeB = parseInt(cleanValue, 10);
                        }
                    }
                    
                    console.log(`   Parsed min_fee_b: ${parsedMinFeeB} (type: ${typeof parsedMinFeeB})`);
                    
                    if (parsedMinFeeB && !isNaN(parsedMinFeeB) && parsedMinFeeB > 0) {
                        // Calculate protocol buffer as 3% of base fee, ensuring it's an integer
                        const rawProtocolBuffer = Math.max(1500, parsedMinFeeB * 0.03);
                        console.log(`   Raw protocol buffer calculation: Math.max(1500, ${parsedMinFeeB} * 0.03) = ${rawProtocolBuffer} (type: ${typeof rawProtocolBuffer})`);
                        
                        protocolBuffer = Math.floor(rawProtocolBuffer);
                        console.log(`   Protocol buffer after Math.floor(): ${protocolBuffer} (type: ${typeof protocolBuffer})`);
                        console.log(`   Successfully parsed min_fee_b: ${parsedMinFeeB}`);
                    } else {
                        console.log(`   Failed to parse min_fee_b, using default: ${protocolBuffer}`);
                    }
                } else {
                    console.log(`   min_fee_b not available, using default: ${protocolBuffer}`);
                }
            } catch (parseError) {
                console.log(`   Error parsing min_fee_b: ${parseError.message}, using default: ${protocolBuffer}`);
            }
            
            // Calculate total buffer step by step
            console.log(`   Step-by-step total calculation:`);
            console.log(`     Step 1: baseBuffer = ${baseBuffer} (type: ${typeof baseBuffer})`);
            console.log(`     Step 2: inputBuffer = ${inputBuffer} (type: ${typeof inputBuffer})`);
            console.log(`     Step 3: protocolBuffer = ${protocolBuffer} (type: ${typeof protocolBuffer})`);
            
            const step1 = baseBuffer + inputBuffer;
            console.log(`     Step 4: baseBuffer + inputBuffer = ${baseBuffer} + ${inputBuffer} = ${step1} (type: ${typeof step1})`);
            
            const step2 = step1 + protocolBuffer;
            console.log(`     Step 5: step1 + protocolBuffer = ${step1} + ${protocolBuffer} = ${step2} (type: ${typeof step2})`);
            
            // Total buffer - ensure it's an integer
            const totalBuffer = Math.floor(step2);
            console.log(`     Step 6: Math.floor(step2) = Math.floor(${step2}) = ${totalBuffer} (type: ${typeof totalBuffer})`);
            
            console.log(`   Final fee buffer calculation:`);
            console.log(`     - Base buffer: ${baseBuffer} lovelace`);
            console.log(`     - Input buffer (${selectedUtxos.length} inputs): ${inputBuffer} lovelace`);
            console.log(`     - Protocol buffer: ${protocolBuffer} lovelace`);
            console.log(`     - Total buffer: ${totalBuffer} lovelace`);
            console.log(`   Returning totalBuffer: ${totalBuffer} (type: ${typeof totalBuffer})`);
            
            return totalBuffer;
        } catch (error) {
            console.error('Error calculating fee buffer:', error);
            return 3500; // Safe fallback (increased from 2500)
        }
    }

    /**
     * Helper to delay execution
     */
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    /**
     * Clear existing CBOR to force rebuild with new fee calculation
     */
    async clearTransactionCbor() {
        try {
            this.isLoading = true;
            console.log('🧹 Clearing existing transaction CBOR...');
            
            // Clear the CBOR field by updating with empty string
            await updateOutboundTransactionCbor({ 
                recordId: this.recordId, 
                signedTransactionCbor: '' 
            });
            
            // Clear local display
            this.signedTransactionCbor = '';
            this.showCborDisplay = false;
            this.resetState();
            
            console.log('✅ Transaction CBOR cleared successfully - status set to "Ready to Sign"');
            this.showToast('Success', 'Transaction CBOR cleared and status set to "Ready to Sign". You can now rebuild with the updated fee calculation.', 'success');
            
        } catch (error) {
            console.error('❌ Error clearing transaction CBOR:', error);
            this.showToast('Error', `Failed to clear CBOR: ${error.message}`, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Main transaction building method
     */
    async buildAndSignTransaction() {
        this.isLoading = true;
        this.resetState();

        try {
            console.log('🚀 ========================================');
            console.log('🚀 STARTING ADA TRANSACTION BUILD PROCESS');
            console.log('🚀 ========================================');
            console.log(`⏰ Timestamp: ${new Date().toISOString()}`);
            console.log(`📄 Record ID: ${this.recordId}`);
            
            // Step 0: Update transaction status to "Ready to Sign" at the beginning
            console.log('📝 Step 0: Setting transaction status to "Ready to Sign"...');
            try {
                await updateOutboundTransactionCbor({ 
                    recordId: this.recordId, 
                    signedTransactionCbor: '' // Clear any existing CBOR
                });
                console.log('✅ Step 0: Transaction status set to "Ready to Sign" and CBOR cleared');
                // Removed info toast here as requested
            } catch (statusError) {
                console.error('❌ Error setting initial status:', statusError);
                throw new Error(`Failed to set initial transaction status: ${statusError.message}`);
            }
            
            // Step 1: Validate transaction details
            const transactionDetails = this.validateTransactionDetails();
            
            // Enhanced logging for transaction details
            console.log('📋 ========================================');
            console.log('📋 TRANSACTION DETAILS VALIDATION');
            console.log('📋 ========================================');
            console.log(`🔑 Wallet ID: ${transactionDetails.walletId}`);
            console.log(`📤 Recipient Address: ${transactionDetails.toAddress}`);
            console.log(`💰 Amount: ${transactionDetails.amount} ADA (${transactionDetails.amountInLovelace} lovelace)`);
            console.log(`📊 Amount Type: ${typeof transactionDetails.amount}`);
            console.log(`✅ Amount Valid: ${!isNaN(transactionDetails.amount) && transactionDetails.amount > 0}`);
            
            // Enhanced address validation using new method
            console.log('🔍 ========================================');
            console.log('🔍 RECIPIENT ADDRESS VALIDATION');
            console.log('🔍 ========================================');
            const addressValidation = this.validateAdaAddress(transactionDetails.toAddress);
            
            if (!addressValidation.isValid) {
                console.error('❌ Address validation failed:', addressValidation.error);
                throw new Error(`Invalid recipient address: ${addressValidation.error}`);
            }
            
            console.log(`✅ Address Format: Valid`);
            console.log(`🌐 Network: ${addressValidation.network}`);
            console.log(`📝 Address Type: ${addressValidation.addressType}`);
            console.log(`📏 Address Length: ${addressValidation.address ? addressValidation.address.length : 'unknown'} characters`);
            console.log(`🔤 Address Prefix: ${addressValidation.address ? addressValidation.address.substring(0, 10) + '...' : 'unknown'}`);
            console.log(`👁️ Address Preview: ${addressValidation.address ? addressValidation.address.substring(0, 20) + '...' + addressValidation.address.substring(addressValidation.address.length - 10) : 'unknown'}`);
            
            // Enhanced amount validation using new method
            console.log('💰 ========================================');
            console.log('💰 TRANSACTION AMOUNT VALIDATION');
            console.log('💰 ========================================');
            const amountValidation = this.validateTransactionAmount(transactionDetails.amount);
            
            if (!amountValidation.isValid) {
                console.error('❌ Amount validation failed:', amountValidation.error);
                throw new Error(`Invalid transaction amount: ${amountValidation.error}`);
            }
            
            console.log(`✅ Amount Format: Valid`);
            console.log(`💵 Amount: ${amountValidation.formatted}`);
            console.log(`🔢 Numeric Amount: ${amountValidation.amount}`);
            console.log(`🪙 Lovelace Amount: ${amountValidation.amountInLovelace}`);
            console.log(`📊 Amount Type: ${typeof amountValidation.amount}`);
            
            // Log comprehensive transaction summary
            console.log('📊 ========================================');
            console.log('📊 TRANSACTION SUMMARY');
            console.log('📊 ========================================');
            console.log(`🎯 Action: Sending ADA`);
            console.log(`💸 Amount: ${amountValidation.formatted}`);
            console.log(`📤 To Address: ${addressValidation.address}`);
            console.log(`🌐 Network: ${addressValidation.network}`);
            console.log(`🔑 From Wallet: ${transactionDetails.walletId}`);
            console.log(`⏰ Timestamp: ${new Date().toISOString()}`);
            console.log(`📄 Record ID: ${this.recordId}`);
            console.log(`✅ Status: Ready to proceed with transaction building`);
            console.log('📊 ========================================');
            
            // Step 2: Ensure libraries are loaded
            console.log('📚 Step 2: Ensuring Cardano libraries are loaded...');
            if (!this.librariesLoaded || !this.cardanoLib) {
                console.log('   Libraries not loaded, attempting to load now...');
                try {
                    await this.loadLibraries();
                    console.log('   ✅ Libraries loaded successfully');
                } catch (libraryError) {
                    console.error('   ❌ Failed to load libraries:', libraryError);
                    throw new Error('Failed to load required Cardano libraries. Please refresh the page and try again.');
                }
            } else {
                console.log('   ✅ Libraries already loaded');
            }
            
            // Double-check that libraries are available
            if (!this.cardanoLib) {
                throw new Error('Cardano library is not available. Please refresh the page and try again.');
            }
            
            console.log('   ✅ Library validation passed');

            // Step 3: Fetch wallet addresses
            const { receivingAddresses, changeAddresses, addressPrivateKeys } = 
                await this.fetchWalletAddresses(transactionDetails.walletId);

            // Step 4: Fetch UTXOs
            const allAddresses = [...receivingAddresses, ...changeAddresses];
            
            // Process all addresses to ensure we find sufficient UTXOs
            console.log(`📊 Address processing summary:`);
            console.log(`   Total addresses available: ${allAddresses.length}`);
            console.log(`   Addresses to process: ${allAddresses.length} (all addresses)`);
            
            const utxoMap = await this.fetchUTXOs(allAddresses);

            // Step 5: Fetch network parameters
            const { protocolParams, currentSlot } = await this.fetchNetworkParameters();

            // Step 6: Prepare transaction parameters
            const transactionAmountLovelace = Math.round(transactionDetails.amount * 1000000);
            const requiredLovelace = transactionAmountLovelace;

            // Step 7: Collect available UTXOs (ADA-only, no multi-assets)
            const availableUtxos = [];
            for (const addressObj of allAddresses) {
                if (utxoMap.has(addressObj.address)) {
                    const utxos = utxoMap.get(addressObj.address);
                    for (const utxo of utxos) {
                        // Only include UTXOs that contain ONLY lovelace (no multi-assets)
                        const hasOnlyLovelace = utxo.amount.length === 1 && 
                                               utxo.amount[0].unit === 'lovelace';
                        
                        if (hasOnlyLovelace) {
                            availableUtxos.push({
                                utxo: utxo,
                                address: addressObj.address,
                                privateKey: addressObj.privateKey
                            });
                            console.log(`✅ Added ADA-only UTXO: ${utxo.txHash}:${utxo.outputIndex} with ${utxo.amount[0].quantity} lovelace`);
                        } else {
                            console.log(`⚠️ Skipped multi-asset UTXO: ${utxo.txHash}:${utxo.outputIndex} (${utxo.amount.length} assets)`);
                        }
                    }
                }
            }
            
            console.log(`📊 UTXO filtering summary:`);
            console.log(`   Total ADA-only UTXOs available: ${availableUtxos.length}`);
            
            if (availableUtxos.length === 0) {
                throw new Error('No ADA-only UTXOs found. All UTXOs contain multi-assets. Please use a different wallet or wait for pure ADA UTXOs.');
            }

            // Step 8: Select UTXOs with fee estimation (ADA-only)
            const { selectedUtxos, totalInputLovelace, privateKeys } = 
                this.selectUTXOs(availableUtxos, requiredLovelace, protocolParams);

            // Step 9: Select change address
            const changeAddressObj = this.selectChangeAddress(changeAddresses, utxoMap);

            // Step 10: Initialize transaction builder
            const txBuilder = this.initializeTransactionBuilder(protocolParams);

            // Step 11: Add inputs
            this.addTransactionInputs(txBuilder, selectedUtxos);

            // Step 12: Add outputs
            console.log('🔧 Step 12: About to add transaction outputs...');
            console.log('   Transaction details:', transactionDetails);
            console.log('   Change address object:', changeAddressObj);
            console.log('   Protocol params keys:', Object.keys(protocolParams));
            console.log('   Transaction type: ADA-only (no multi-assets)');
            
            // Ensure no leftover multi-asset variables cause issues
            const totalInputAssets = null; // Explicitly set to null for ADA-only transactions
            
            this.addTransactionOutputs(txBuilder, transactionDetails, changeAddressObj, protocolParams);
            console.log('✅ Step 12: Transaction outputs added successfully');

            // Step 13: Build and sign
            console.log('🔧 Step 13: About to build and sign transaction...');
            console.log('   Selected UTXOs count:', selectedUtxos.length);
            console.log('   Total input lovelace:', totalInputLovelace);
            console.log('   Current slot:', currentSlot);
            console.log('   Change address object:', changeAddressObj ? changeAddressObj.address : 'undefined');
            
            // Validate inputs before building transaction
            if (!selectedUtxos || selectedUtxos.length === 0) {
                throw new Error('No UTXOs selected for transaction');
            }
            
            if (!totalInputLovelace || totalInputLovelace <= 0) {
                throw new Error('Invalid total input lovelace');
            }
            
            if (!currentSlot || !currentSlot.current_slot) {
                throw new Error('Invalid current slot information');
            }
            
            if (!txBuilder) {
                throw new Error('Transaction builder is not initialized');
            }
            
            let transaction, txCborHex, fee, changeLovelace;
            
            try {
                const result = await this.buildAndSignTransactionInner(txBuilder, selectedUtxos, currentSlot, totalInputLovelace, changeAddressObj, protocolParams, transactionDetails);
                
                // Destructure with strict validation
                if (!result || typeof result !== 'object') {
                    throw new Error('Transaction result is not a valid object');
                }
                
                // Handle the signed transaction result
                if (result.signed === true) {
                    console.log('✅ Step 13: Transaction signed successfully with Blake2b hashing');
                    console.log('   Signed transaction validation:');
                    console.log(`     - Transaction object: ${result.transaction ? '✅ Present' : '❌ Missing'}`);
                    console.log(`     - CBOR Hex: ${result.txCborHex ? '✅ Present' : '❌ Missing'}`);
                    console.log(`     - Fee: ${result.fee ? '✅ Present' : '❌ Missing'}`);
                    console.log(`     - Change lovelace: ${result.changeLovelace ? '✅ Present' : '❌ Missing'}`);
                    console.log(`     - Transaction hash: ${result.transactionHash ? '✅ Present' : '❌ Missing'}`);
                    
                transaction = result.transaction;
                txCborHex = result.txCborHex;
                fee = result.fee;
                changeLovelace = result.changeLovelace;
                    
                    // Log the success with Blake2b
                    this.logStep(10, 'Transaction signed successfully with Blake2b', 'success', 
                        `Fee: ${parseInt(result.fee) / 1000000} ADA, CBOR: ${txCborHex.length / 2} bytes`);
                    
                } else {
                    // Handle unexpected format
                    console.error('❌ Unexpected result format from signing process:', result);
                    throw new Error('Unexpected result format from transaction signing');
                }
                
                console.log('✅ Step 13: Transaction built and signed successfully');
                console.log('   Transaction result validation:');
                console.log(`     - Transaction object: ${transaction ? '✅ Present' : '❌ Missing'}`);
                console.log(`     - CBOR Hex: ${txCborHex ? '✅ Present' : '❌ Missing'}`);
                console.log(`     - Fee: ${fee ? '✅ Present' : '❌ Missing'}`);
                console.log(`     - Change Lovelace: ${changeLovelace ? '✅ Present' : '❌ Missing'}`);
                
            } catch (buildError) {
                console.error('❌ Error in buildAndSignTransaction call:', buildError);
                throw new Error(`Failed to build transaction: ${buildError.message}`);
            }
            
            // Validate transaction result with detailed error messages
            if (!transaction) {
                console.error('❌ Transaction object validation failed:');
                console.error('   - transaction is null or undefined');
                console.error('   - This indicates the transaction creation failed');
                throw new Error('Transaction object is null or undefined - transaction creation failed');
            }
            
            if (!txCborHex || typeof txCborHex !== 'string' || txCborHex.length === 0) {
                console.error('❌ Transaction CBOR hex validation failed:');
                console.error(`   - txCborHex type: ${typeof txCborHex}`);
                console.error(`   - txCborHex length: ${txCborHex ? txCborHex.length : 'undefined'}`);
                console.error(`   - txCborHex value: ${txCborHex || 'undefined'}`);
                throw new Error('Transaction CBOR hex is invalid or empty - transaction serialization failed');
            }
            
            if (!fee || isNaN(parseInt(fee))) {
                console.error('❌ Transaction fee validation failed:');
                console.error(`   - fee type: ${typeof fee}`);
                console.error(`   - fee value: ${fee}`);
                console.error(`   - parsed fee: ${parseInt(fee)}`);
                throw new Error('Transaction fee is invalid - fee calculation failed');
            }
            
            if (!changeLovelace || isNaN(parseInt(changeLovelace))) {
                console.error('❌ Change lovelace validation failed:');
                console.error(`   - changeLovelace type: ${typeof changeLovelace}`);
                console.error(`   - changeLovelace value: ${changeLovelace}`);
                console.error(`   - parsed changeLovelace: ${parseInt(changeLovelace)}`);
                console.log('   ⚠️ Using default change lovelace of 0');
                changeLovelace = '0';
            }
            
            console.log('✅ All transaction validations passed successfully');

            // Step 14: Update the Outbound_Transaction__c record with the CBOR and set status to "Ready to Send"
            console.log('📝 Step 14: Updating transaction record with CBOR and setting status to "Ready to Send"...');
            try {
                await updateOutboundTransactionCbor({ 
                    recordId: this.recordId, 
                    signedTransactionCbor: txCborHex 
                });
                console.log('✅ Step 14: Transaction record updated successfully - status set to "Ready to Send"');
                this.showToast('Success', 'Transaction signed and ready to send! Status updated to "Ready to Send".', 'success');
            } catch (updateError) {
                console.error('❌ Error updating transaction record:', updateError);
                throw new Error(`Failed to update transaction record: ${updateError.message}`);
            }

            // Step 15: Final validation and success
            this.logStep(11, 'Transaction signed with Blake2b and completed successfully', 'success', 
                `CBOR: ${txCborHex && txCborHex.length > 50 ? txCborHex.substring(0, 50) + '...' : txCborHex || 'undefined'}`);
                    
            // Log transaction summary
            console.log('Transaction Summary (Blake2b Signed):');
            console.log(`   Inputs: ${selectedUtxos.length} UTXOs (${totalInputLovelace} lovelace)`);
            console.log(`   Output: ${transactionDetails.amountLovelace || transactionDetails.amount * 1000000} lovelace to ${transactionDetails.toAddress ? transactionDetails.toAddress.substring(0, 20) + '...' : 'unknown address'}`);
            console.log(`   Change: ${changeLovelace} lovelace to ${changeAddressObj && changeAddressObj.address ? changeAddressObj.address.substring(0, 20) + '...' : 'unknown address'}`);
            console.log(`   Fee: ${fee} lovelace`);
            console.log(`   CBOR Length: ${txCborHex ? txCborHex.length / 2 : 0} bytes`);

            this.isLoading = false;
            
            // Validate values before showing toasts
            const feeValue = parseInt(fee) || 0;
            const cborSize = txCborHex ? txCborHex.length / 2 : 0;
            
            // Show final summary toast
            try {
                const summaryMessage = `Transaction completed!\nFee: ${feeValue / 1000000} ADA | Size: ${cborSize} bytes\nStatus: Ready to Send (with approval, it will auto-submit to blockchain)`;
                this.showToast('Success', summaryMessage, 'success');
            } catch (toastError) {
                console.error('❌ Error showing success toast:', toastError);
            }

            // Set the CBOR for display
            this.signedTransactionCbor = txCborHex;
            this.showCborDisplay = true;

            // Return transaction data for further processing
            try {
                const result = {
                    signed: true,
                    transaction: transaction,
                    txCborHex: txCborHex || '',
                    fee: parseInt(fee) || 0,
                    totalInput: totalInputLovelace || 0,
                    changeAmount: parseInt(changeLovelace) || 0,
                    changeLovelace: changeLovelace || '0',
                    ttl: currentSlot.current_slot + 1000
                };

                // Final validation of result object
                if (!result.txCborHex || result.txCborHex.length === 0) {
                    console.error('❌ Final validation failed: txCborHex is empty in result');
                    throw new Error('Transaction CBOR hex is empty in final result');
                }

                if (result.fee < 0) {
                    console.error('❌ Final validation failed: fee is negative');
                    throw new Error('Transaction fee is negative in final result');
                }

                console.log('✅ Final transaction result:', result);
                return result;
                
            } catch (returnError) {
                console.error('❌ Error creating return result:', returnError);
                throw new Error(`Failed to create return result: ${returnError.message}`);
            }

        } catch (error) {
            this.isLoading = false;
            console.error('Error in buildAndSignTransaction:', error);
            
            // Enhanced error extraction for Salesforce Proxy objects
            let errorMessage = 'Unknown error';
            let errorDetails = {};
            
            try {
                // Try to extract error information from Proxy objects
                if (error && typeof error === 'object') {
                    // Try different ways to access error information
                    if (error.message) {
                        errorMessage = error.message;
                    } else if (error.body && error.body.message) {
                        errorMessage = error.body.message;
                    } else if (error.detail && error.detail.message) {
                        errorMessage = error.detail.message;
                    } else if (error.faultstring) {
                        errorMessage = error.faultstring;
                    } else if (error.errorMessage) {
                        errorMessage = error.errorMessage;
                    } else if (error.error) {
                        errorMessage = error.error;
                    } else if (typeof error.toString === 'function') {
                        errorMessage = error.toString();
                    }
                    
                    // Try to extract additional details
                    try {
                        errorDetails = {
                            errorType: typeof error,
                            errorName: error.name || 'Unknown',
                            errorMessage: errorMessage,
                            hasBody: !!error.body,
                            hasDetail: !!error.detail,
                            hasFaultstring: !!error.faultstring,
                            hasErrorMessage: !!error.errorMessage,
                            hasError: !!error.error,
                            errorKeys: Object.keys(error || {}),
                            errorString: error.toString ? error.toString() : 'No toString method',
                            isProxy: error.toString().includes('Proxy') || error.toString().includes('{}'),
                            stack: error.stack || 'No stack trace'
                        };
                        
                        // Try to access body if it exists
                        if (error.body) {
                            try {
                                errorDetails.bodyKeys = Object.keys(error.body);
                                errorDetails.bodyMessage = error.body.message;
                                errorDetails.bodyDetail = error.body.detail;
                            } catch (bodyError) {
                                errorDetails.bodyError = bodyError.message;
                            }
                        }
                        
                        // Try to access detail if it exists
                        if (error.detail) {
                            try {
                                errorDetails.detailKeys = Object.keys(error.detail);
                                errorDetails.detailMessage = error.detail.message;
                            } catch (detailError) {
                                errorDetails.detailError = detailError.message;
                            }
                        }
                        
                    } catch (detailError) {
                        errorDetails.detailExtractionError = detailError.message;
                    }
                }
                
                console.error('   Enhanced error details:', errorDetails);
                
                // Log the error in a more readable format
                console.error('   Error Summary:');
                console.error(`     - Type: ${errorDetails.errorType}`);
                console.error(`     - Name: ${errorDetails.errorName}`);
                console.error(`     - Message: ${errorMessage}`);
                console.error(`     - Is Proxy: ${errorDetails.isProxy}`);
                console.error(`     - Has Body: ${errorDetails.hasBody}`);
                console.error(`     - Has Detail: ${errorDetails.hasDetail}`);
                console.error(`     - Stack: ${errorDetails.stack}`);
                
                // If it's a Proxy object, try to access it differently
                if (errorDetails.isProxy) {
                    console.error('   ⚠️ This appears to be a Salesforce Proxy object');
                    console.error('   Attempting to access Proxy object properties...');
                    
                    // Try to access common Salesforce error properties
                    const proxyProperties = [
                        'message', 'body', 'detail', 'faultstring', 'errorMessage', 
                        'error', 'type', 'name', 'stack', 'cause', 'reason'
                    ];
                    
                    for (const prop of proxyProperties) {
                        try {
                            const value = error[prop];
                            if (value !== undefined) {
                                console.error(`     ${prop}:`, value);
                            }
                        } catch (propError) {
                            console.error(`     ${prop}: [Access Error: ${propError.message}]`);
                        }
                    }
                }
                
            } catch (extractionError) {
                console.error('   ❌ Error extracting error details:', extractionError);
                errorMessage = 'Failed to extract error details';
            }
            
            // Show a more informative error toast
            const toastMessage = `Transaction failed: ${errorMessage}`;
            this.showToast('Error', toastMessage, 'error');
            
            // Re-throw with better error information
            const enhancedError = new Error(`Transaction failed: ${errorMessage}`);
            enhancedError.originalError = error;
            enhancedError.errorDetails = errorDetails;
            throw enhancedError;
        }
    }
} 