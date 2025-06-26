import { LightningElement, api, track, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import getWalletUTXOs from '@salesforce/apex/TransactionController.getWalletUTXOs';
import getMultipleAddressUtxosDetailed from '@salesforce/apex/BlockfrostService.getMultipleAddressUtxosDetailed';
import getEpochParameters from '@salesforce/apex/BlockfrostService.getEpochParameters';
import getCurrentSlotAndTTL from '@salesforce/apex/BlockfrostService.getCurrentSlotAndTTL';
import calculateMinAdaFromAmount from '@salesforce/apex/TransactionController.calculateMinAdaFromAmount';
import WALLET_FIELD from '@salesforce/schema/Outbound_Transaction__c.Wallet__c';
import TO_ADDRESS_FIELD from '@salesforce/schema/Outbound_Transaction__c.To_Address__c';
import AMOUNT_FIELD from '@salesforce/schema/Outbound_Transaction__c.Amount__c';
import CARDANO_SERIALIZATION from '@salesforce/resourceUrl/cardanoSerialization';
import BIP39 from '@salesforce/resourceUrl/bip39';

export default class PrepareAndSignTransaction extends LightningElement {
    @api recordId;
    @track isLoading = false;
    @track outboundTransaction;
    @track librariesLoaded = false;

    @wire(getRecord, { 
        recordId: '$recordId', 
        fields: [WALLET_FIELD, TO_ADDRESS_FIELD, AMOUNT_FIELD] 
    })
    wiredOutboundTransaction(result) {
        this.outboundTransaction = result;
        if (result.error) {
            console.error('Error loading Outbound Transaction:', result.error);
            this.showToast('Error', 'Failed to load Outbound Transaction record', 'error');
        }
    }

    renderedCallback() {
        if (!this.librariesLoaded) {            
            this.loadLibraries();
        }
    }

    async loadLibraries() {
        const scripts = [
            { name: 'cardanoSerialization', url: `${CARDANO_SERIALIZATION}/cardanoSerialization/bundle.js` },
            { name: 'bip39', url: BIP39 }
        ];

        try {
            const loadResults = await Promise.all(
                scripts.map(async script => {
                    const result = await loadScript(this, script.url)
                        .then(() => {
                            return { name: script.name, loaded: true, url: script.url };
                        })
                        .catch(error => {
                            return { name: script.name, loaded: false, url: script.url, error };
                        });
                    return result;
                })
            );

            const failed = loadResults.filter(r => !r.loaded);
            if (failed.length) {
                throw new Error('Failed to load: ' + failed.map(f => f.name).join(', '));
            }

            this.librariesLoaded = true;

        } catch (error) {
            this.errorMessage = 'Library loading failed: ' + (error.message || error);
            this.showToast('Error', this.errorMessage, 'error');
            setTimeout(() => this.loadLibraries(), 2000);
        }
    }

    get walletId() {
        return this.outboundTransaction?.data?.fields?.Wallet__c?.value || null;
    }

    get transactionDetails() {
        const data = this.outboundTransaction?.data?.fields;
        if (!data) return null;
        return {
            walletId: data.Wallet__c?.value,
            toAddress: data.To_Address__c?.value,
            amount: data.Amount__c?.value
        };
    }

    /**
     * Calculate minimum ADA required for a UTXO with multi-assets
     * @param {Object} multiAsset - Map of policy ID to asset name/amount mapping
     * @param {Object} protocolParams - Object containing min_utxo and coins_per_utxo_size parameters
     * @returns {number} Minimum ADA amount in lovelace
     */
    calculateMinAda(multiAsset, protocolParams) {
        const minUtxo = parseInt(protocolParams.min_utxo) || 4310;
        const coinsPerUtxoByte = parseInt(protocolParams.coins_per_utxo_size) || 4310;
        const baseBytes = 160; // Approximate base size of a UTXO without assets
        let additionalBytes = 0;

        if (multiAsset && Object.keys(multiAsset).length > 0) {
            const policies = Object.keys(multiAsset);
            for (let i = 0; i < policies.length; i++) {
                const policy = policies[i];
                const assets = multiAsset[policy];
                const assetNames = Object.keys(assets);
                for (let j = 0; j < assetNames.length; j++) {
                    const assetName = assetNames[j];
                    additionalBytes += 8 + assetName.length; // Policy ID (28 bytes) + asset name
                }
            }
        }

        const totalBytes = baseBytes + additionalBytes;
        return Math.ceil((totalBytes * coinsPerUtxoByte) / 8);
    }

    /**
     * Create multi-asset structure from UTXO amount array
     * @param {Array} amountArray - Array of { unit, quantity } objects from Blockfrost
     * @returns {Object} Multi-asset structure for calculateMinAda function
     */
    createMultiAssetFromAmount(amountArray) {
        const multiAsset = {};
        
        if (!amountArray || !Array.isArray(amountArray)) {
            return multiAsset;
        }

        for (const asset of amountArray) {
            if (asset.unit === 'lovelace') {
                continue; // Skip ADA/lovelace as it's handled separately
            }
            
            // Extract policy ID and asset name from unit
            // Unit format: policyId + assetName (hex encoded)
            if (asset.unit.length >= 56) { // Policy ID is 28 bytes = 56 hex chars
                const policyId = asset.unit.substring(0, 56);
                const assetName = asset.unit.substring(56);
                
                if (!multiAsset[policyId]) {
                    multiAsset[policyId] = {};
                }
                multiAsset[policyId][assetName] = parseInt(asset.quantity);
            }
        }
        
        return multiAsset;
    }

    async buildAndSignTransaction() {
        this.isLoading = true;

        try {
            // Validate transaction details
            const transactionDetails = this.transactionDetails;
            if (!transactionDetails || !transactionDetails.walletId || !transactionDetails.toAddress || !transactionDetails.amount) {
                throw new Error('Invalid transaction details: walletId, toAddress, and amount are required');
            }

            // Verify libraries are loaded before proceeding
            if (!this.librariesLoaded) {
                throw new Error('Required libraries are not loaded. Please refresh the page and try again.');
            }

            // Fetch wallet UTXO addresses 
            const utxoAddresses = await getWalletUTXOs({ walletId: transactionDetails.walletId });
            
            // Structure addresses like Node.js pattern
            const receivingAddresses = [];
            const changeAddresses = [];
            const addressPrivateKeys = new Map();

            // Process receiving addresses (type '0')
            utxoAddresses.filter(addr => addr.addressType === '0').forEach(addr => {
                receivingAddresses.push({
                    address: addr.address,
                    path: addr.path,
                    index: addr.addressIndex,
                    privateKey: addr.privateKey,
                    publicKey: addr.publicKey,
                    stakingKeyHash: addr.stakingKeyHash,
                    assets: addr.assets
                });
                // Store address to private key mapping (actual private key from Salesforce)
                addressPrivateKeys.set(addr.address, addr.privateKey);
            });

            // Process change addresses (type '1') 
            utxoAddresses.filter(addr => addr.addressType === '1').forEach(addr => {
                changeAddresses.push({
                    address: addr.address,
                    path: addr.path,
                    index: addr.addressIndex,
                    privateKey: addr.privateKey,
                    publicKey: addr.publicKey,
                    stakingKeyHash: addr.stakingKeyHash,
                    assets: addr.assets
                });
                // Store address to private key mapping (actual private key from Salesforce)
                addressPrivateKeys.set(addr.address, addr.privateKey);
            });

            // Output final arrays and objects like Node.js pattern
            console.log('Receiving Addresses:', JSON.stringify(receivingAddresses, null, 2));
            console.log('Change Addresses:', JSON.stringify(changeAddresses, null, 2));
            
            // Convert Map to object for JSON.stringify
            const addressPrivateKeysObj = {};
            addressPrivateKeys.forEach((value, key) => {
                addressPrivateKeysObj[key] = value;
            });
            console.log('Address Private Keys Map:', JSON.stringify(addressPrivateKeysObj, null, 2));

            // Fetch UTXOs for all addresses from Blockfrost (following Node.js pattern)
            const allAddresses = [...receivingAddresses, ...changeAddresses];
            const addressList = allAddresses.map(addr => addr.address);
            const utxoMap = new Map();
            
            console.log('🔍 Fetching real UTXOs from Blockfrost for addresses:', JSON.stringify(addressList, null, 2));
            
            try {
                const utxoResponse = await getMultipleAddressUtxosDetailed({ addresses: addressList });
                const utxoData = JSON.parse(utxoResponse);
                console.log('📡 Blockfrost UTXO Response:', JSON.stringify(utxoData, null, 2));
                
                // Process real UTXO data following Node.js pattern
                for (const addressObj of allAddresses) {
                    const address = addressObj.address;
                    const blockfrostUtxos = utxoData[address];
                    
                    if (blockfrostUtxos && Array.isArray(blockfrostUtxos) && blockfrostUtxos.length > 0) {
                        // Convert Blockfrost UTXO format to Node.js format
                        const utxos = blockfrostUtxos.map(utxo => ({
                            txHash: utxo.tx_hash,           // Real transaction hash from Blockfrost
                            outputIndex: utxo.output_index, // Real output index from Blockfrost
                            amount: utxo.amount             // Array of { unit, quantity } from Blockfrost
                        }));
                        utxoMap.set(address, utxos);
                        console.log(`✅ Found ${utxos.length} UTXOs for address ${address.substring(0, 20)}...`);
                    }
                    // No log for empty UTXO arrays - this is normal for unused addresses
                }
            } catch (error) {
                console.error('❌ Failed to fetch UTXOs from Blockfrost:', error);
                // Fallback to empty UTXO map
                console.log('⚠️ Using empty UTXO map due to Blockfrost error');
            }

            // Convert Map to object for JSON.stringify
            const utxoMapObj = {};
            utxoMap.forEach((value, key) => {
                utxoMapObj[key] = value;
            });
            console.log('🗺️ Final UTXO Map with real transaction data:', JSON.stringify(utxoMapObj, null, 2));

            // Helper to delay execution (respecting Blockfrost rate limits)
            const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

            // Fetch protocol parameters and current slot
            console.log('🌐 Fetching protocol parameters and current slot...');
            
            try {
                const protocolParamsResponse = await getEpochParameters();
                const protocolParams = JSON.parse(protocolParamsResponse);
                console.log('⚙️ Protocol Parameters:', JSON.stringify(protocolParams, null, 2));
                
                await delay(200); // Respect Blockfrost rate limit
                
                const currentSlotResponse = await getCurrentSlotAndTTL();
                const currentSlot = JSON.parse(currentSlotResponse);
                console.log('🕐 Current Slot and TTL:', JSON.stringify(currentSlot, null, 2));

                // Calculate minimum ADA for multi-asset UTXOs
                const minAda = this.calculateMinAda({}, protocolParams);
                console.log(`💰 Minimum ADA required: ${minAda} lovelace (${minAda / 1000000} ADA)`);
                
                // Example: Calculate min ADA for a UTXO with specific assets
                // This would be used when building actual transaction outputs
                const exampleMultiAsset = {
                    'policy123': {
                        'asset1': 100,
                        'asset2': 200
                    }
                };
                const minAdaWithAssets = this.calculateMinAda(exampleMultiAsset, protocolParams);
                console.log(`💰 Minimum ADA with assets: ${minAdaWithAssets} lovelace (${minAdaWithAssets / 1000000} ADA)`);
                
                // Calculate min ADA for each UTXO with multi-assets
                console.log('🔍 Calculating minimum ADA for each UTXO...');
                for (const [address, utxos] of utxoMap.entries()) {
                    for (const utxo of utxos) {
                        const multiAsset = this.createMultiAssetFromAmount(utxo.amount);
                        if (Object.keys(multiAsset).length > 0) {
                            const utxoMinAda = this.calculateMinAda(multiAsset, protocolParams);
                            console.log(`📦 UTXO ${utxo.txHash}:${utxo.outputIndex} requires ${utxoMinAda} lovelace minimum ADA`);
                            console.log(`   Multi-asset structure:`, multiAsset);
                            // Also calculate using server-side method for comparison
                            try {
                                const serverMinAda = await calculateMinAdaFromAmount({
                                    amountArrayJson: JSON.stringify(utxo.amount),
                                    protocolParamsJson: JSON.stringify(protocolParams)
                                });
                                console.log(`   Server-side calculation: ${serverMinAda} lovelace`);
                                if (serverMinAda !== utxoMinAda) {
                                    console.warn(`   ⚠️ Client/server calculation mismatch: ${utxoMinAda} vs ${serverMinAda}`);
                                }
                            } catch (error) {
                                console.error(`   ❌ Server-side calculation failed:`, error);
                            }
                        }
                    }
                }

                // --- UTXO selection logic ---
                // Get the actual transaction amount from the outbound transaction record
                const transactionAmount = this.transactionDetails.amount;
                const transactionAmountLovelace = Math.round(transactionAmount * 1000000); // Convert ADA to lovelace
                
                console.log(`💰 Transaction Details:`);
                console.log(`   Amount to send: ${transactionAmount} ADA`);
                console.log(`   Amount in lovelace: ${transactionAmountLovelace} lovelace`);
                
                // Calculate minimum required lovelace (send amount + reasonable buffer for fees)
                // We'll calculate actual fees when building the transaction
                const minAdaForChange = 1000000; // 1 ADA minimum for change output
                const feeBuffer = 500000; // 0.5 ADA buffer for fees (will be calculated accurately later)
                const requiredLovelace = transactionAmountLovelace + feeBuffer + minAdaForChange;
                
                console.log(`   Fee buffer: ${feeBuffer} lovelace (${feeBuffer / 1000000} ADA) - will calculate actual fees during transaction building`);
                console.log(`   Min ADA for change: ${minAdaForChange} lovelace (${minAdaForChange / 1000000} ADA)`);
                console.log(`   Total required (with buffer): ${requiredLovelace} lovelace (${requiredLovelace / 1000000} ADA)`);
                
                console.log('🔍 Selecting UTXO for transaction...');
                
                // Collect all available UTXOs and their lovelace amounts
                const availableUtxos = [];
                let totalAvailableLovelace = 0;
                
                for (const addressObj of allAddresses) {
                    if (utxoMap.has(addressObj.address)) {
                        const utxos = utxoMap.get(addressObj.address);
                        for (const utxo of utxos) {
                            const utxoLovelace = parseInt(
                                (utxo.amount.find(a => a.unit === 'lovelace') || {}).quantity || '0',
                                10
                            );
                            console.log(`   Found UTXO ${utxo.txHash}:${utxo.outputIndex} - ${utxoLovelace} lovelace (${utxoLovelace / 1000000} ADA) from ${addressObj.address}`);
                            
                            availableUtxos.push({
                                utxo: utxo,
                                address: addressObj.address,
                                lovelace: utxoLovelace,
                                privateKey: addressObj.privateKey
                            });
                            totalAvailableLovelace += utxoLovelace;
                        }
                    }
                }
                
                console.log(`📊 Total available: ${totalAvailableLovelace} lovelace (${totalAvailableLovelace / 1000000} ADA) across ${availableUtxos.length} UTXOs`);
                
                if (totalAvailableLovelace < requiredLovelace) {
                    console.error(`❌ Insufficient total funds. Available: ${totalAvailableLovelace} lovelace (${totalAvailableLovelace / 1000000} ADA), Required: ${requiredLovelace} lovelace (${requiredLovelace / 1000000} ADA)`);
                    throw new Error(`Insufficient funds. Available: ${totalAvailableLovelace / 1000000} ADA, Required: ${requiredLovelace / 1000000} ADA`);
                }
                
                // Select all UTXOs (we'll use all available ones for now)
                // In a more sophisticated implementation, you might want to optimize which UTXOs to select
                const selectedUtxos = availableUtxos;
                let totalInputLovelace = totalAvailableLovelace;
                
                console.log(`✅ Selected ${selectedUtxos.length} UTXOs with total ${totalInputLovelace} lovelace (${totalInputLovelace / 1000000} ADA):`);
                selectedUtxos.forEach((utxoInfo, index) => {
                    console.log(`   ${index + 1}. ${utxoInfo.utxo.txHash}:${utxoInfo.utxo.outputIndex} - ${utxoInfo.lovelace} lovelace (${utxoInfo.lovelace / 1000000} ADA) from ${utxoInfo.address}`);
                });
                
                // Select first unused change address
                const changeAddressObj = changeAddresses.find(addr => !utxoMap.has(addr.address));
                if (!changeAddressObj) {
                    throw new Error('No unused change address available');
                }
                console.log(`✅ Selected change address: ${changeAddressObj.address}`);
                
                // Calculate change amount (reserving space for fees)
                const changeAmount = totalInputLovelace - transactionAmountLovelace - feeBuffer;
                console.log(`💰 Change calculation (with fee buffer):`);
                console.log(`   Input: ${totalInputLovelace} lovelace (${totalInputLovelace / 1000000} ADA)`);
                console.log(`   Send: ${transactionAmountLovelace} lovelace (${transactionAmountLovelace / 1000000} ADA)`);
                console.log(`   Fee buffer: ${feeBuffer} lovelace (${feeBuffer / 1000000} ADA) - actual fees will be calculated during transaction building`);
                console.log(`   Change (estimated): ${changeAmount} lovelace (${changeAmount / 1000000} ADA) - final amount depends on actual fees`);

                // --- Transaction Builder Initialization ---
                console.log('🔧 Initializing Transaction Builder...');
                
                // Verify CardanoWasm is properly loaded
                console.log('🔍 Verifying CardanoWasm library...');
                
                // Check for required methods


                try {
                    // Instantiate TransactionBuilder
                    console.log('🔧 Step 1: Creating LinearFee...', window);
                    const linearFee = window.cardanoSerialization.LinearFee.new(
                        window.cardanoSerialization.BigNum.from_str(protocolParams.min_fee_a.toString()),
                        window.cardanoSerialization.BigNum.from_str(protocolParams.min_fee_b.toString())
                    );
                    console.log('✅ LinearFee created successfully');
                    
                    console.log('🔧 Step 2: Creating TransactionBuilderConfig...');
                    const txBuilderCfg = window.cardanoSerialization.TransactionBuilderConfigBuilder.new()
                        .fee_algo(linearFee)
                        .pool_deposit(window.cardanoSerialization.BigNum.from_str(protocolParams.pool_deposit))
                        .key_deposit(window.cardanoSerialization.BigNum.from_str(protocolParams.key_deposit))
                        .max_value_size(protocolParams.max_block_size || 90112) // Use max_block_size as fallback
                        .max_tx_size(protocolParams.max_tx_size)
                        .coins_per_utxo_byte(window.cardanoSerialization.BigNum.from_str(protocolParams.coins_per_utxo_size || protocolParams.min_utxo))
                        .build();
                    console.log('✅ TransactionBuilderConfig created successfully');
                        
                    console.log('🔧 Step 3: Creating TransactionBuilder...');
                    const txBuilder = window.cardanoSerialization.TransactionBuilder.new(txBuilderCfg);
                    console.log('✅ TransactionBuilder created successfully');
                    
                    console.log('✅ Transaction Builder initialized with network parameters:');
                    console.log(`   Min Fee A: ${protocolParams.min_fee_a}`);
                    console.log(`   Min Fee B: ${protocolParams.min_fee_b}`);
                    console.log(`   Pool Deposit: ${protocolParams.pool_deposit}`);
                    console.log(`   Key Deposit: ${protocolParams.key_deposit}`);
                    console.log(`   Max Value Size: ${protocolParams.max_block_size || 90112} (using max_block_size)`);
                    console.log(`   Max TX Size: ${protocolParams.max_tx_size}`);
                    console.log(`   Coins per UTXO Byte: ${protocolParams.coins_per_utxo_size || protocolParams.min_utxo}`);
                    console.log(`   Current Slot: ${currentSlot.current_slot}`);
                    console.log(`   TTL: ${currentSlot.ttl}`);
                    
                    // Store the transaction builder for later use
                    this.txBuilder = txBuilder;
                    this.protocolParams = protocolParams;
                    this.currentSlot = currentSlot;
                    
                    // --- Transaction Building and Signing ---
                    console.log('🔨 Building transaction...');
                    
                    // Add inputs
                    console.log('📥 Adding inputs to transaction...');
                    for (const utxoInfo of selectedUtxos) {
                        console.log('utxo is', JSON.stringify(utxoInfo))
                        const utxo = utxoInfo.utxo;
                        const address = utxoInfo.address;
                        const privKeyHex = utxoInfo.privateKey;
                        
                        console.log(`   Adding input: ${utxo.txHash}:${utxo.outputIndex} from ${address.substring(0, 20)}...`);
                        
                        // Create private key from hex
                        const privKey = window.cardanoSerialization.PrivateKey.from_extended_bytes(
                            Buffer.from(privKeyHex, 'hex')
                        );
                        
                        // Get lovelace amount
                        const lovelaceAmount = utxo.amount.find(a => a.unit === 'lovelace')?.quantity || '0';
                        const value = window.cardanoSerialization.Value.new(window.cardanoSerialization.BigNum.from_str(lovelaceAmount));
                        
                        // Add key input
                        txBuilder.add_key_input(
                            privKey.to_public().hash(),
                            window.cardanoSerialization.TransactionInput.new(
                                window.cardanoSerialization.TransactionHash.from_bytes(Buffer.from(utxo.txHash, 'hex')),
                                utxo.outputIndex
                            ),
                            value
                        );
                        
                        console.log(`   ✅ Added input: ${lovelaceAmount} lovelace`);
                    }
                    
                    // Add output to recipient
                    console.log('📤 Adding output to recipient...');
                    const outputValue = window.cardanoSerialization.Value.new(window.cardanoSerialization.BigNum.from_str(transactionAmountLovelace.toString()));
                    const minAda = this.calculateMinAda({}, protocolParams);
                    console.log(`   Minimum ADA required for output: ${minAda} lovelace`);
                    
                    if (transactionAmountLovelace < minAda) {
                        outputValue.set_coin(window.cardanoSerialization.BigNum.from_str(minAda.toString()));
                        console.log(`   ⚠️ Output amount increased to minimum ADA: ${minAda} lovelace`);
                    }
                    
                    const outputAddr = window.cardanoSerialization.Address.from_bech32(transactionDetails.toAddress);
                    txBuilder.add_output(
                        window.cardanoSerialization.TransactionOutput.new(outputAddr, outputValue)
                    );
                    console.log(`   ✅ Added output: ${transactionAmountLovelace} lovelace to ${transactionDetails.toAddress.substring(0, 20)}...`);
                    
                    // Set TTL
                    const ttl = currentSlot.current_slot + 1000;
                    txBuilder.set_ttl(ttl);
                    console.log(`   ⏰ Set TTL: ${ttl} (current slot + 1000)`);
                    
                    // Add change output
                    console.log('💰 Adding change output...');
                    const changeAddr = window.cardanoSerialization.Address.from_bech32(changeAddressObj.address);
                    const minAdaForChange = this.calculateMinAda({}, protocolParams);
                    console.log(`   Minimum ADA required for change output: ${minAdaForChange} lovelace`);
                    txBuilder.add_change_if_needed(changeAddr);
                    console.log(`   ✅ Added change output to ${changeAddressObj.address.substring(0, 20)}...`);
                    
                    // Build transaction body
                    console.log('🔨 Building transaction body...');
                    const txBody = txBuilder.build();
                    
                    // Compute transaction fee
                    const fee = txBuilder.get_fee_if_set()?.to_str() || '0';
                    console.log(`💰 Transaction fee: ${fee} lovelace (${parseInt(fee) / 1000000} ADA)`);
                    
                    // Validate transaction
                    console.log('✅ Validating transaction...');
                    let totalOutputLovelace = 0;
                    const outputs = txBody.outputs();
                    for (let i = 0; i < outputs.len(); i++) {
                        const output = outputs.get(i);
                        const outputValue = output.amount();
                        const outputLovelace = parseInt(outputValue.coin().to_str());
                        totalOutputLovelace += outputLovelace;
                    }
                    
                    let changeLovelace = '0';
                    for (let i = 0; i < outputs.len(); i++) {
                        const output = outputs.get(i);
                        if (output.address().to_bech32() === changeAddressObj.address) {
                            changeLovelace = output.amount().coin().to_str();
                        }
                    }
                    
                    const isBalanced = totalInputLovelace === totalOutputLovelace + parseInt(fee);
                    console.log(`📊 Transaction validation:`);
                    console.log(`   Input: ${totalInputLovelace} lovelace`);
                    console.log(`   Output: ${totalOutputLovelace} lovelace`);
                    console.log(`   Change: ${changeLovelace} lovelace`);
                    console.log(`   Fee: ${fee} lovelace`);
                    console.log(`   Balanced: ${isBalanced ? '✅ Yes' : '❌ No'}`);
                    
                    if (!isBalanced) {
                        throw new Error(`Transaction not balanced: Input=${totalInputLovelace}, Output=${totalOutputLovelace}, Fee=${fee}`);
                    }
                    
                    // Compute transaction hash
                    console.log('🔍 Computing transaction hash...');
                    const txBodyBytes = txBody.to_bytes();
                    
                    // Use Blake2b if available, otherwise use a simple hash
                    let txHash;
                    if (typeof Blake2b !== 'undefined') {
                        const hash = new Blake2b(32).update(txBodyBytes).digest();
                        txHash = window.cardanoSerialization.TransactionHash.from_bytes(hash);
                    } else {
                        // Fallback: use CardanoWasm's built-in hash function if available
                        console.log('   ⚠️ Blake2b not available, using fallback hash method');
                        txHash = window.cardanoSerialization.TransactionHash.from_bytes(txBodyBytes);
                    }
                    
                    console.log(`   Transaction hash: ${Buffer.from(txHash.to_bytes()).toString('hex')}`);
                    
                    // Create witnesses
                    console.log('✍️ Creating transaction witnesses...');
                    const witnesses = window.cardanoSerialization.TransactionWitnessSet.new();
                    const vkeyWitnesses = window.cardanoSerialization.Vkeywitnesses.new();
                    const signedAddresses = new Set();
                    
                    for (const utxoInfo of selectedUtxos) {
                        const address = utxoInfo.address;
                        if (!signedAddresses.has(address)) {
                            const privKeyHex = utxoInfo.privateKey;
                            const privKey = window.cardanoSerialization.PrivateKey.from_extended_bytes(
                                Buffer.from(privKeyHex, 'hex')
                            );
                            
                            const vkeyWitness = window.cardanoSerialization.make_vkey_witness(txHash, privKey);
                            vkeyWitnesses.add(vkeyWitness);
                            signedAddresses.add(address);
                            privKey.free();
                            
                            console.log(`   ✅ Signed for address: ${address.substring(0, 20)}...`);
                        }
                    }
                    
                    witnesses.set_vkeys(vkeyWitnesses);
                    console.log(`   Total witnesses: ${vkeyWitnesses.len()}`);
                    
                    // Create finalized transaction
                    console.log('🎯 Creating finalized transaction...');
                    const transaction = window.cardanoSerialization.Transaction.new(
                        txBody,
                        witnesses,
                        undefined // no metadata
                    );
                    
                    // Convert transaction to CBOR hex
                    const txCborHex = Buffer.from(transaction.to_bytes()).toString('hex');
                    console.log('🎉 Transaction built and signed successfully!');
                    console.log('📄 Transaction CBOR (hex):');
                    console.log(txCborHex);
                    
                    // Log transaction summary
                    console.log('📋 Transaction Summary:');
                    console.log(`   Inputs: ${selectedUtxos.length} UTXOs (${totalInputLovelace} lovelace)`);
                    console.log(`   Output: ${transactionAmountLovelace} lovelace to ${transactionDetails.toAddress.substring(0, 20)}...`);
                    console.log(`   Change: ${changeLovelace} lovelace to ${changeAddressObj.address.substring(0, 20)}...`);
                    console.log(`   Fee: ${fee} lovelace`);
                    console.log(`   CBOR Length: ${txCborHex.length / 2} bytes`);
                    
                } catch (cardanoError) {
                    console.error('❌ Error initializing CardanoWasm Transaction Builder:');
                    console.error('Error type:', typeof cardanoError);
                    console.error('Error name:', cardanoError.name);
                    console.error('Error message:', cardanoError.message);
                    console.error('Error stack:', cardanoError.stack);
                    console.error('Error toString():', cardanoError.toString());
                    
                    // Try to get more details about the error
                    if (cardanoError.toString) {
                        console.error('Error details:', cardanoError.toString());
                    }
                    
                    console.error('Protocol params used:', JSON.stringify(protocolParams, null, 2));
                    throw new Error(`Failed to initialize transaction builder: ${cardanoError.message || cardanoError.toString() || 'Unknown error'}`);
                }

            } catch (error) {
                console.error('❌ Failed to fetch network parameters:', error);
            }

            this.isLoading = false;
            this.showToast('Success', `Structured ${receivingAddresses.length} receiving & ${changeAddresses.length} change addresses!`, 'success');

        } catch (error) {
            this.isLoading = false;
            console.error('Error structuring addresses:', error);
            this.showToast('Error', `Failed to structure addresses: ${error.message}`, 'error');
        }
    }

    resetState() {
        this.statusMessage = '';
        this.hasStatus = false;
        this.stepLogs = [];
        this.currentStep = 0;
    }

    logStep(stepNumber, message, type = 'info', details = '') {
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
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(evt);
    }

    get progressPercentage() {
        return this.totalSteps > 0 ? Math.round((this.currentStep / this.totalSteps) * 100) : 0;
    }

    get progressBarStyle() {
        return `width: ${this.progressPercentage}%`;
    }
} 