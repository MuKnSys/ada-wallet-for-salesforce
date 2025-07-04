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
import syncAssetsAndTransactions from '@salesforce/apex/UTXOAssetController.syncAssetsAndTransactions';

export default class CreateNewWallet extends NavigationMixin(LightningElement) {
    // Configuration constants
    TARGET_CONSECUTIVE_ADDRESSES = 20;
    ADDRESS_TYPES = {
        RECEIVING: 0,
        CHANGE: 1
    };
    DERIVATION_PATHS = {
        RECEIVING: 0,
        CHANGE: 1
    };

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
        const validation = this.validateWalletSetId(newWalletSetId);
        
        if (!validation.isValid) {
            this.pickerErrorMessage = validation.error;
            this.selectedWalletSetId = '';
            this.accountIndex = '0';
            this.accountIndexErrorMessage = '';
            return;
        }
        
        this.selectedWalletSetId = newWalletSetId;
        this.pickerErrorMessage = '';
        
        if (newWalletSetId) {
            try {
                const nextIndex = await getNextAccountIndex({ walletSetId: newWalletSetId });
                this.accountIndex = String(nextIndex);
                this.accountIndexErrorMessage = '';
            } catch (error) {
                this.handleError(error, 'Failed to fetch next account index');
                this.accountIndex = '0';
            }
        } else {
            this.accountIndex = '0';
            this.accountIndexErrorMessage = '';
        }
    }

    async handleWalletNameChange(event) {
        this.walletName = event.target.value || '';
    }

    async handleAccountIndexChange(event) {
        const newIndex = event.target.value || '0';
        this.accountIndex = newIndex;
        
        // Client-side validation first
        const validation = this.validateAccountIndex(newIndex);
        if (!validation.isValid) {
            this.accountIndexErrorMessage = validation.error;
            return;
        }
        
        this.accountIndexErrorMessage = '';

        if (this.selectedWalletSetId) {
            try {
                const errorMessage = await isIndexValid({ walletSetId: this.selectedWalletSetId, accountIndex: parseInt(newIndex) });
                if (errorMessage) {
                    this.accountIndexErrorMessage = errorMessage;
                    this.showToast('Error', errorMessage, 'error');
                }
            } catch (error) {
                this.handleError(error, 'Failed to validate account index');
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
        const targetConsecutive = this.TARGET_CONSECUTIVE_ADDRESSES;
        const typeLabel = derivationPath === this.DERIVATION_PATHS.RECEIVING ? 'receiving' : 'change';

        this.updateProgress(`Generating ${typeLabel} addresses`, `Finding ${targetConsecutive} consecutive unused addresses...`);

        // Phase 1: Generate and check addresses
        const addresses = await this.generateAndCheckAddresses(
            accountKey, derivationPath, accountIndexNum, stakeCred, network, stakeKeyHash, typeLabel, targetConsecutive
        );

        // Phase 2: Create UTXO records
        await this.createUTXORecords(addresses, typeLabel, walletId);

        // Phase 3: Sync assets and transactions
        await this.syncAddresses(addresses, typeLabel);

        return addresses;
    }

    async generateAndCheckAddresses(accountKey, derivationPath, accountIndexNum, stakeCred, network, stakeKeyHash, typeLabel, targetConsecutive) {
        const addresses = [];
        let consecutiveUnused = 0;
        let index = 0;

        while (consecutiveUnused < targetConsecutive) {
            this.updateProgress(`Checking ${typeLabel} address #${index}`, 
                `Phase 1 - ${consecutiveUnused}/${targetConsecutive} consecutive unused found`);

            const addressData = await this.deriveAndVerifyAddress(
                accountKey, derivationPath, accountIndexNum, stakeCred, network, stakeKeyHash, index, typeLabel
            );

            const usageResult = await this.checkAddressUsage(addressData.address, index, typeLabel);
            
            if (usageResult.isUsed) {
                consecutiveUnused = 0;
            } else {
                consecutiveUnused++;
            }

            addresses.push({
                ...addressData,
                isUsed: usageResult.isUsed,
                usageResult: usageResult.result,
                usageError: usageResult.error
            });

            this.updateProgress(`Address #${index} ${usageResult.isUsed ? 'USED' : 'UNUSED'}`, 
                `${consecutiveUnused}/${targetConsecutive} consecutive unused`);
            
            index++;
        }

        return addresses;
    }

    async deriveAndVerifyAddress(accountKey, derivationPath, accountIndexNum, stakeCred, network, stakeKeyHash, index, typeLabel) {
        const privateKey = accountKey.derive(derivationPath).derive(index);
        const publicKey = privateKey.to_public();
        const keyHash = publicKey.to_raw_key().hash();
        const cred = window.cardanoSerialization.Credential.from_keyhash(keyHash);

        const baseAddress = window.cardanoSerialization.BaseAddress.new(
            network.network_id(),
            cred,
            stakeCred
        );
        const bech32Address = baseAddress.to_address().to_bech32();

        // Verify key match
        const keyMatch = this.verifyKeyMatch(window.cardanoSerialization, privateKey, bech32Address);
        if (!keyMatch) {
            throw new Error(`Derived private key does not match address payment key hash for ${typeLabel} address #${index}`);
        }

        const fullPath = `m/1852'/1815'/${accountIndexNum}'/${derivationPath}/${index}`;
        
        return {
            index: index,
            publicKey: publicKey.to_bech32(),
            privateKey: privateKey.to_bech32(),
            address: bech32Address,
            stakingKeyHash: stakeKeyHash.to_hex(),
            path: fullPath
        };
    }

    async checkAddressUsage(address, index, typeLabel) {
        try {
            this.updateProgress(`Checking ${typeLabel} address #${index}`, 'Checking blockchain for address usage...');
            
            const usageResult = await checkAddressUsageOnly({ address });
            const isUsed = usageResult.isUsed || false;
            
            return { isUsed, result: usageResult, error: null };
        } catch (error) {
            this.updateProgress(`Usage check failed for ${typeLabel} address #${index}`, 
                `Assuming unused due to error: ${error.message}`);
            
            return { isUsed: false, result: null, error: error.message };
        }
    }

    async createUTXORecords(addresses, typeLabel, walletId) {
        this.updateProgress(`Creating ${typeLabel} UTXO records`, 
            `Creating ${addresses.length} ${typeLabel} addresses in Salesforce...`);

        try {
            const createResult = await createUTXOAddressesBulk({
                walletId: walletId,
                receivingAddresses: typeLabel === 'receiving' ? addresses : [],
                changeAddresses: typeLabel === 'change' ? addresses : []
            });

            const addressResults = typeLabel === 'receiving' ? 
                createResult.receivingAddresses : 
                createResult.changeAddresses;

            // Merge creation results with address data
            for (let i = 0; i < addresses.length && i < addressResults.length; i++) {
                addresses[i].utxoAddressId = addressResults[i].utxoAddressId;
                addresses[i].createResult = addressResults[i];
            }

            this.updateProgress(`Successfully created ${addresses.length} ${typeLabel} addresses`);
        } catch (error) {
            throw new Error(`Failed to create ${typeLabel} UTXO records: ${error.message}`);
        }
    }

    async syncAddresses(addresses, typeLabel) {
        this.updateProgress(`Syncing ${typeLabel} assets & transactions`, 
            `Syncing blockchain data for ${addresses.length} addresses...`);

        let syncedCount = 0;
        let totalUsedAddresses = 0;

        for (let i = 0; i < addresses.length; i++) {
            const address = addresses[i];
            
            if (!address.utxoAddressId) continue;

            this.updateProgress(`Syncing ${typeLabel} address #${address.index}`, 
                `${i + 1}/${addresses.length}...`);
            
            try {
                const syncResult = await syncAssetsAndTransactions({ utxoAddressId: address.utxoAddressId });
                
                address.syncResult = syncResult;
                address.syncSuccess = syncResult.success;
                
                if (syncResult.success && syncResult.statistics) {
                    const stats = syncResult.statistics;
                    const actuallyUsed = this.isAddressActuallyUsed(stats);
                    address.actuallyUsed = actuallyUsed;
                    
                    if (actuallyUsed) totalUsedAddresses++;
                }
                
                syncedCount++;
            } catch (error) {
                address.syncError = error.message;
                address.syncSuccess = false;
                
                this.updateProgress(`Sync failed for ${typeLabel} address #${address.index}`, 
                    error.message);
            }
        }

        this.updateProgress(`Synced ${syncedCount}/${addresses.length} ${typeLabel} addresses`, 
            `${totalUsedAddresses} actually used`);
    }

    isAddressActuallyUsed(stats) {
        const assetsInserted = stats.assetsInserted || 0;
        const assetsUpdated = stats.assetsUpdated || 0;
        const transactionsInserted = stats.transactionsInserted || 0;
        const transactionsUpdated = stats.transactionsUpdated || 0;
        
        return assetsInserted > 0 || assetsUpdated > 0 || transactionsInserted > 0 || transactionsUpdated > 0;
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
        } catch (error) {
            throw new Error('Failed to save wallet: ' + (error.body?.message || error.message));
        }

        // Generate receiving addresses with full syncing (usage check, creation, and asset/transaction sync)
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

    // Validation helper methods
    validateWalletSetId(walletSetId) {
        if (!walletSetId) return { isValid: false, error: 'Please select a Wallet Set' };
        if (!/^[a-zA-Z0-9]{15,18}$/.test(walletSetId)) {
            return { isValid: false, error: 'Invalid Wallet Set ID selected' };
        }
        return { isValid: true, error: '' };
    }

    validateWalletName(walletName) {
        if (!walletName || !walletName.trim()) {
            return { isValid: false, error: 'Wallet Name is required' };
        }
        if (walletName.length > 255) {
            return { isValid: false, error: 'Wallet Name must be 255 characters or less' };
        }
        return { isValid: true, error: '' };
    }

    validateAccountIndex(accountIndex) {
        if (!accountIndex || isNaN(accountIndex)) {
            return { isValid: false, error: 'Account Index must be a number' };
        }
        if (parseInt(accountIndex) < 0) {
            return { isValid: false, error: 'Account Index must be non-negative' };
        }
        return { isValid: true, error: '' };
    }

    // Error handling helper
    handleError(error, context = '') {
        const message = error.body?.message || error.message || 'Unknown error';
        const fullMessage = context ? `${context}: ${message}` : message;
        this.errorMessage = fullMessage;
        this.showToast('Error', fullMessage, 'error');
        return fullMessage;
    }

    // Progress update helper
    updateProgress(step, message = '') {
        this.currentStep = step;
        this.progressMessage = message;
    }
}