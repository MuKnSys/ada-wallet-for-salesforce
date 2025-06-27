import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import { NavigationMixin } from 'lightning/navigation';

import cardanoLibrary from '@salesforce/resourceUrl/cardanoSerialization';
import bip39Library from '@salesforce/resourceUrl/bip39';

import checkAddressUsageOnly from '@salesforce/apex/CreateNewWalletCtrl.checkAddressUsageOnly';
import createUTXOAddressesBulk from '@salesforce/apex/CreateNewWalletCtrl.createUTXOAddressesBulk';
import getDecryptedSeedPhrase from '@salesforce/apex/CreateNewWalletCtrl.getDecryptedSeedPhrase';
import createWallet from '@salesforce/apex/CreateNewWalletCtrl.createWallet';
import getNextAccountIndex from '@salesforce/apex/CreateNewWalletCtrl.getNextAccountIndex';
import isIndexValid from '@salesforce/apex/CreateNewWalletCtrl.isIndexValid';
import checkIsAddressUsed from '@salesforce/apex/CreateNewWalletCtrl.checkIsAddressUsed';
import syncAssetsAndTransactions from '@salesforce/apex/UTXOAssetController.syncAssetsAndTransactions';

export default class CreateNewWallet extends NavigationMixin(LightningElement) {
    @track librariesLoaded = false;
    @track selectedWalletSetId = '';
    @track walletName = '';
    @track accountIndex = '0';
    @track errorMessage = '';
    @track pickerErrorMessage = '';
    @track accountIndexErrorMessage = '';
    @track isLoading = false;
    @track currentStep = '';
    @track progressMessage = '';

    get isCreateDisabled() {
        return !(
            this.selectedWalletSetId &&
            this.walletName.trim() &&
            this.accountIndex &&
            !isNaN(this.accountIndex) &&
            !this.accountIndexErrorMessage &&
            this.librariesLoaded &&
            !this.isLoading
        );
    }

    get buttonLabel() {
        return this.isLoading ? 'Creating...' : 'Create Wallet';
    }

    get progressDisplay() {
        if (this.isLoading && this.currentStep) {
            return `${this.currentStep}${this.progressMessage ? ': ' + this.progressMessage : ''}`;
        }
        return '';
    }

    renderedCallback() {
        if (!this.librariesLoaded) {            
            this.loadLibraries();
        }
    }

    async loadLibraries() {
        const scripts = [
            { name: 'cardanoSerialization', url: `${cardanoLibrary}/cardanoSerialization/bundle.js` },
            { name: 'bip39', url: bip39Library }
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

    async handleWalletSetChange(event) {
        const newWalletSetId = event.detail.recordId || '';
        
        if (newWalletSetId && !/^[a-zA-Z0-9]{15,18}$/.test(newWalletSetId)) {
            this.pickerErrorMessage = 'Invalid Wallet Set ID selected';
            this.selectedWalletSetId = '';
            this.accountIndex = '0';
            this.accountIndexErrorMessage = '';
        } else {
            this.selectedWalletSetId = newWalletSetId;
            this.pickerErrorMessage = newWalletSetId ? '' : 'Please select a Wallet Set';
            if (newWalletSetId) {
                try {
                    const nextIndex = await getNextAccountIndex({ walletSetId: newWalletSetId });
                    this.accountIndex = String(nextIndex);
                    this.accountIndexErrorMessage = '';
                } catch (error) {
                    this.errorMessage = 'Failed to fetch next account index: ' + (error.body?.message || error.message);
                    this.showToast('Error', this.errorMessage, 'error');
                    this.accountIndex = '0';
                }
            } else {
                this.accountIndex = '0';
                this.accountIndexErrorMessage = '';
            }
        }
    }

    async handleWalletNameChange(event) {
        this.walletName = event.target.value || '';
    }

    async handleAccountIndexChange(event) {
        const newIndex = event.target.value || '0';
        this.accountIndex = newIndex;
        this.accountIndexErrorMessage = '';

        if (this.selectedWalletSetId && !isNaN(newIndex)) {
            try {
                const errorMessage = await isIndexValid({ walletSetId: this.selectedWalletSetId, accountIndex: parseInt(newIndex) });
                if (errorMessage) {
                    this.accountIndexErrorMessage = errorMessage;
                    this.showToast('Error', errorMessage, 'error');
                }
            } catch (error) {
                this.accountIndexErrorMessage = 'Failed to validate account index: ' + (error.body?.message || error.message);
                this.showToast('Error', this.accountIndexErrorMessage, 'error');
            }
        }
    }

    async handleCreate() {
        this.errorMessage = '';
        this.isLoading = true;
        this.currentStep = 'Initializing';
        this.progressMessage = '';

        if (!this.librariesLoaded) {
            this.errorMessage = 'Libraries not loaded. Please try again.';
            this.showToast('Error', this.errorMessage, 'error');
            this.isLoading = false;
            return;
        }

        try {
            await this.createWallet();
            this.showToast('Success', `Wallet "${this.walletName}" created successfully`, 'success');
            this.resetForm();
        } catch (error) {
            this.errorMessage = 'Wallet creation failed: ' + (error.message || error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
            this.currentStep = '';
            this.progressMessage = '';
        }
    }

    // Helper to verify private key matches address payment key hash
    verifyKeyMatch(CardanoWasm, utxoPrivateKey, addressBech32) {
        const derivedPubKeyHash = utxoPrivateKey.to_public().to_raw_key().hash().to_hex();
        const addressObj = CardanoWasm.Address.from_bech32(addressBech32);
        const addressKeyHash =
            CardanoWasm.BaseAddress.from_address(addressObj)?.payment_cred().to_keyhash()?.to_hex() ||
            CardanoWasm.EnterpriseAddress.from_address(addressObj)?.payment_cred().to_keyhash()?.to_hex();
        return derivedPubKeyHash === addressKeyHash;
    }

    /**
     * Enhanced address generation that ensures 20 consecutive unused addresses
     * Uses a three-phase approach to avoid DML + callout issues:
     * Phase 1: Derive addresses and check usage (callouts only)
     * Phase 2: Create all UTXO records in bulk (DML only)
     * Phase 3: Sync assets and transactions for each address (callouts + DML per address)
     */
    async generateAddressesUntilUnused(accountKey, derivationPath, accountIndexNum, stakeCred, network, stakeKeyHash, walletId) {
        const targetConsecutive = 20;
        const typeLabel = derivationPath === 0 ? 'receiving' : 'change';

        this.currentStep = `Generating ${typeLabel} addresses`;
        this.progressMessage = `Finding ${targetConsecutive} consecutive unused addresses...`;

        console.log(`[CreateNewWallet] 🚀 Starting three-phase ${typeLabel} address generation`);
        console.log(`[CreateNewWallet] Target: ${targetConsecutive} consecutive unused addresses`);

        // PHASE 1: Derive addresses and check usage (CALLOUTS ONLY)
        console.log(`[CreateNewWallet] 📡 Phase 1: Deriving addresses and checking usage (callouts only)`);
        
        const addresses = [];
        let consecutiveUnused = 0;
        let index = 0;

        while (consecutiveUnused < targetConsecutive) {
            // Update progress
            this.progressMessage = `Phase 1 - Deriving address #${index}, ${consecutiveUnused}/${targetConsecutive} consecutive unused found`;

            // Derive the address
            const privateKey = accountKey
                .derive(derivationPath)
                .derive(index);
            const publicKey = privateKey.to_public();
            const keyHash = publicKey.to_raw_key().hash();
            const cred = window.cardanoSerialization.Credential.from_keyhash(keyHash);

            const baseAddress = window.cardanoSerialization.BaseAddress.new(
                network.network_id(),
                cred,
                stakeCred
            );
            const bech32Address = baseAddress.to_address().to_bech32();

            // Key verification
            const keyMatch = this.verifyKeyMatch(window.cardanoSerialization, privateKey, bech32Address);
            if (!keyMatch) {
                throw new Error(`Derived private key does not match address payment key hash for ${typeLabel} address #${index}`);
            }

            const fullPath = `m/1852'/1815'/${accountIndexNum}'/${derivationPath}/${index}`;
            const addressData = {
                index: index,
                publicKey: publicKey.to_bech32(),
                privateKey: privateKey.to_bech32(),
                address: bech32Address,
                stakingKeyHash: stakeKeyHash.to_hex(),
                path: fullPath
            };

            console.log(`[CreateNewWallet] 🔍 Phase 1 - Generated ${typeLabel} address #${index}: ${bech32Address}`);

            // Check usage via callouts only (no DML)
            try {
                this.currentStep = `Checking ${typeLabel} address #${index}`;
                this.progressMessage = 'Checking blockchain for address usage...';

                const usageResult = await checkAddressUsageOnly({ address: bech32Address });
                
                console.log(`[CreateNewWallet] 📊 Usage check result for ${typeLabel} address #${index}:`, JSON.stringify(usageResult, null, 2));

                const isUsed = usageResult.isUsed || false;
                
                if (isUsed) {
                    consecutiveUnused = 0;
                    console.log(`[CreateNewWallet] 🔴 ${typeLabel} address #${index} is USED (${bech32Address}). Resetting consecutive count to 0.`);
                    console.log(`[CreateNewWallet] 🔴   Usage details:`, usageResult);
                } else {
                    consecutiveUnused++;
                    console.log(`[CreateNewWallet] 🟢 ${typeLabel} address #${index} is UNUSED (${bech32Address}). Consecutive unused: ${consecutiveUnused}/${targetConsecutive}`);
                }

                // Store the address with usage information
                addresses.push({
                    ...addressData,
                    isUsed: isUsed,
                    usageResult: usageResult
                });

                // Update progress message with usage info
                this.progressMessage = `Address #${index} ${isUsed ? 'USED' : 'UNUSED'} - ${consecutiveUnused}/${targetConsecutive} consecutive unused`;

            } catch (usageError) {
                console.error(`[CreateNewWallet] ❌ Usage check failed for ${typeLabel} address #${index} (${bech32Address}):`, usageError);
                
                // Update progress message with error info
                this.progressMessage = `Usage check failed: ${usageError.message} - assuming unused`;
                
                // If usage check fails, assume address is unused and continue
                consecutiveUnused++;
                console.log(`[CreateNewWallet] ⚠️ Assuming ${typeLabel} address #${index} is UNUSED due to check failure. Consecutive unused: ${consecutiveUnused}/${targetConsecutive}`);
                
                addresses.push({
                    ...addressData,
                    isUsed: false,
                    usageError: usageError.message,
                    usageResult: null
                });
            }

            index++;
        }

        console.log(`[CreateNewWallet] ✅ Phase 1 complete for ${typeLabel} addresses!`);
        console.log(`[CreateNewWallet] Generated ${addresses.length} ${typeLabel} addresses with ${targetConsecutive} consecutive unused addresses`);
        console.log(`[CreateNewWallet] Usage summary:`, {
            total: addresses.length,
            used: addresses.filter(a => a.isUsed).length,
            unused: addresses.filter(a => !a.isUsed).length,
            lastConsecutiveUnused: consecutiveUnused
        });

        // PHASE 2: Create all UTXO records in bulk (DML ONLY)
        console.log(`[CreateNewWallet] 💾 Phase 2: Creating ${addresses.length} ${typeLabel} UTXO records in bulk`);
        
        this.currentStep = `Creating ${typeLabel} UTXO records`;
        this.progressMessage = `Creating ${addresses.length} ${typeLabel} addresses in Salesforce...`;

        try {
            const createResult = await createUTXOAddressesBulk({
                walletId: walletId,
                receivingAddresses: derivationPath === 0 ? addresses : [],
                changeAddresses: derivationPath === 1 ? addresses : []
            });

            console.log(`[CreateNewWallet] ✅ Phase 2 complete - Created ${typeLabel} UTXO records:`, createResult);

            // Merge the creation results with the usage data
            const addressResults = derivationPath === 0 ? 
                createResult.receivingAddresses : 
                createResult.changeAddresses;

            for (let i = 0; i < addresses.length && i < addressResults.length; i++) {
                addresses[i].utxoAddressId = addressResults[i].utxoAddressId;
                addresses[i].createResult = addressResults[i];
            }

            this.progressMessage = `Successfully created ${addresses.length} ${typeLabel} addresses`;

        } catch (createError) {
            console.error(`[CreateNewWallet] ❌ Phase 2 failed - Error creating ${typeLabel} UTXO records:`, createError);
            this.progressMessage = `Failed to create ${typeLabel} records: ${createError.message}`;
            throw new Error(`Failed to create ${typeLabel} UTXO records: ${createError.message}`);
        }

        // PHASE 3: Sync assets and transactions for all created addresses
        console.log(`[CreateNewWallet] 🔄 Phase 3: Syncing assets and transactions for ${addresses.length} ${typeLabel} addresses`);
        
        this.currentStep = `Syncing ${typeLabel} assets & transactions`;
        this.progressMessage = `Syncing blockchain data for ${addresses.length} addresses...`;

        let syncedCount = 0;
        let totalUsedAddresses = 0;

        for (let i = 0; i < addresses.length; i++) {
            const address = addresses[i];
            
            if (!address.utxoAddressId) {
                console.warn(`[CreateNewWallet] ⚠️ Skipping sync for ${typeLabel} address #${address.index} - no UTXO address ID`);
                continue;
            }

            this.progressMessage = `Syncing ${typeLabel} address #${address.index} (${i + 1}/${addresses.length})...`;
            
            try {
                console.log(`[CreateNewWallet] 🔄 Syncing ${typeLabel} address #${address.index} (ID: ${address.utxoAddressId})`);
                
                const syncResult = await syncAssetsAndTransactions({ utxoAddressId: address.utxoAddressId });
                
                console.log(`[CreateNewWallet] ✅ Sync completed for ${typeLabel} address #${address.index}:`, syncResult);
                
                // Store sync results
                address.syncResult = syncResult;
                address.syncSuccess = syncResult.success;
                
                // Determine if address is actually used based on sync results
                if (syncResult.success && syncResult.statistics) {
                    const stats = syncResult.statistics;
                    const assetsInserted = stats.assetsInserted || 0;
                    const assetsUpdated = stats.assetsUpdated || 0;
                    const transactionsInserted = stats.transactionsInserted || 0;
                    const transactionsUpdated = stats.transactionsUpdated || 0;
                    
                    const actuallyUsed = assetsInserted > 0 || assetsUpdated > 0 || transactionsInserted > 0 || transactionsUpdated > 0;
                    address.actuallyUsed = actuallyUsed;
                    
                    if (actuallyUsed) {
                        totalUsedAddresses++;
                        console.log(`[CreateNewWallet] 🎯 ${typeLabel} address #${address.index} IS ACTUALLY USED - Assets: ${assetsInserted + assetsUpdated}, Transactions: ${transactionsInserted + transactionsUpdated}`);
                    } else {
                        console.log(`[CreateNewWallet] 🎯 ${typeLabel} address #${address.index} is actually unused after sync`);
                    }
                }
                
                syncedCount++;
                
            } catch (syncError) {
                console.error(`[CreateNewWallet] ❌ Sync failed for ${typeLabel} address #${address.index}:`, syncError);
                address.syncError = syncError.message;
                address.syncSuccess = false;
                
                // Continue syncing other addresses even if one fails
                this.progressMessage = `Sync failed for address #${address.index}: ${syncError.message}`;
            }
        }

        console.log(`[CreateNewWallet] ✅ Phase 3 complete for ${typeLabel} addresses!`);
        console.log(`[CreateNewWallet] Sync summary:`, {
            total: addresses.length,
            synced: syncedCount,
            failed: addresses.length - syncedCount,
            actuallyUsed: totalUsedAddresses,
            actuallyUnused: addresses.length - totalUsedAddresses
        });

        this.progressMessage = `Synced ${syncedCount}/${addresses.length} ${typeLabel} addresses (${totalUsedAddresses} actually used)`;

        console.log(`[CreateNewWallet] 🎉 Three-phase ${typeLabel} address generation completed successfully!`);
        return addresses;
    }

    async createWallet() {
        // Validate account index before proceeding
        const accountIndexNum = parseInt(this.accountIndex, 10);
        try {
            const errorMessage = await isIndexValid({ walletSetId: this.selectedWalletSetId, accountIndex: accountIndexNum });
            if (errorMessage) {
                throw new Error(errorMessage);
            }
        } catch (error) {
            throw new Error('Failed to validate account index: ' + (error.body?.message || error.message));
        }

        this.currentStep = 'Retrieving seed phrase';
        let mnemonic;
        try {
            mnemonic = await getDecryptedSeedPhrase({ walletSetId: this.selectedWalletSetId });            
            console.log(`[CreateNewWallet] Retrieved mnemonic successfully`);
            if (!mnemonic) {
                throw new Error('Seed phrase is empty or null');
            }
            if (!window.bip39.validateMnemonic(mnemonic)) {
                throw new Error('Decrypted mnemonic is invalid');
            }
        } catch (error) {
            throw new Error('Failed to retrieve seed phrase: ' + (error.body?.message || error.message));
        }

        this.currentStep = 'Deriving cryptographic keys';
        const entropy = window.bip39.mnemonicToEntropy(mnemonic);
        const seed = Buffer.from(entropy, 'hex');

        let rootKey;
        try {
            rootKey = window.cardanoSerialization.Bip32PrivateKey.from_bip39_entropy(seed, Buffer.from(''));
            console.log(`[CreateNewWallet] Root key derived successfully`);
        } catch (error) {
            throw new Error('Failed to derive root key: ' + error.message);
        }

        const harden = (num) => 0x80000000 + num;

        if (accountIndexNum < 0) {
            throw new Error('Account Index must be non-negative');
        }
        const accountKey = rootKey
            .derive(harden(1852))
            .derive(harden(1815))
            .derive(harden(accountIndexNum));

        const paymentPrivateKey = accountKey
            .derive(0)
            .derive(0);
        const paymentPublicKey = paymentPrivateKey.to_public();

        const stakePrivateKey = accountKey
            .derive(2)
            .derive(0)
            .to_raw_key();
        const stakePublicKey = stakePrivateKey.to_public();
        const stakeKeyHash = stakePublicKey.hash();
        const stakeCred = window.cardanoSerialization.Credential.from_keyhash(stakeKeyHash);

        const network = window.cardanoSerialization.NetworkInfo.mainnet();

        this.currentStep = 'Creating wallet record';
        let recordId;
        try {
            const paymentKeyHash = paymentPublicKey.to_raw_key().hash();
            const paymentCred = window.cardanoSerialization.Credential.from_keyhash(paymentKeyHash);

            const baseAddress = window.cardanoSerialization.BaseAddress.new(
                network.network_id(),
                paymentCred,
                stakeCred
            );
            const bech32Address = baseAddress.to_address().to_bech32();

            recordId = await createWallet({
                walletSetId: this.selectedWalletSetId,
                walletName: this.walletName,
                address: bech32Address,
                accountPrivateKey: paymentPrivateKey.to_bech32(),
                accountPublicKey: paymentPublicKey.to_bech32(),
                accountIndex: accountIndexNum
            });

            if (!recordId) {
                throw new Error('Error creating wallet record');
            }
            console.log(`[CreateNewWallet] Wallet record created: ${recordId}`);
        } catch (error) {
            throw new Error('Failed to save wallet: ' + (error.body?.message || error.message));
        }

        // Generate receiving addresses with full syncing (usage check, creation, and asset/transaction sync)
        console.log(`[CreateNewWallet] 🚀 Starting receiving address generation with full sync...`);
        const receivingAddresses = await this.generateAddressesUntilUnused(
            accountKey,
            0, // derivation path for receiving addresses
            accountIndexNum,
            stakeCred,
            network,
            stakeKeyHash,
            recordId
        );

        // Generate change addresses with full syncing (usage check, creation, and asset/transaction sync)
        console.log(`[CreateNewWallet] 🚀 Starting change address generation with full sync...`);
        const changeAddresses = await this.generateAddressesUntilUnused(
            accountKey,
            1, // derivation path for change addresses
            accountIndexNum,
            stakeCred,
            network,
            stakeKeyHash,
            recordId
        );

        this.currentStep = 'Finalizing wallet creation';
        this.progressMessage = 'Preparing to navigate to wallet...';

        console.log(`[CreateNewWallet] ✅ Wallet creation completed successfully!`);
        console.log(`[CreateNewWallet] Final summary:`, {
            walletId: recordId,
            receivingAddressesGenerated: receivingAddresses.length,
            changeAddressesGenerated: changeAddresses.length,
            receivingAddressesPreCheckUsed: receivingAddresses.filter(a => a.isUsed).length,
            changeAddressesPreCheckUsed: changeAddresses.filter(a => a.isUsed).length,
            receivingAddressesActuallyUsed: receivingAddresses.filter(a => a.actuallyUsed).length,
            changeAddressesActuallyUsed: changeAddresses.filter(a => a.actuallyUsed).length,
            receivingAddressesSynced: receivingAddresses.filter(a => a.syncSuccess).length,
            changeAddressesSynced: changeAddresses.filter(a => a.syncSuccess).length
        });

        // Navigate to the wallet record page
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'Wallet__c',
                actionName: 'view'
            }
        }, true);
    }

    resetForm() {
        this.selectedWalletSetId = '';
        this.walletName = '';
        this.accountIndex = '0';
        this.errorMessage = '';
        this.pickerErrorMessage = '';
        this.accountIndexErrorMessage = '';
        this.currentStep = '';
        this.progressMessage = '';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}