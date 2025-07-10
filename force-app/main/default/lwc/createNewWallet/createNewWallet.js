import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import { NavigationMixin } from 'lightning/navigation';

import cardanoLibrary from '@salesforce/resourceUrl/cardanoSerialization';
import bip39Library from '@salesforce/resourceUrl/bip39';

import checkAddressUsageOnly from '@salesforce/apex/CreateNewWalletCtrl.checkAddressUsageOnly';
import createUTXOAddressesBulk from '@salesforce/apex/CreateNewWalletCtrl.createUTXOAddressesBulk';
import getEncryptedSeedPhrase from '@salesforce/apex/CreateNewWalletCtrl.getEncryptedSeedPhrase';
import createWallet from '@salesforce/apex/CreateNewWalletCtrl.createWallet';
import getNextAccountIndex from '@salesforce/apex/CreateNewWalletCtrl.getNextAccountIndex';
import isIndexValid from '@salesforce/apex/CreateNewWalletCtrl.isIndexValid';
import verifySeedPhrase from '@salesforce/apex/CreateNewWalletCtrl.verifySeedPhrase';
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

    // Helper: Get Ed25519 raw private key (hex) from Bip32PrivateKey
    getRawEd25519PrivateKeyHex(bip32priv) {
        try {
            // Check if this is a valid BIP32 private key that can be converted to raw Ed25519
            if (!bip32priv || typeof bip32priv.to_raw_key !== 'function') {
                throw new Error('Invalid BIP32 private key provided');
            }
            
            // Get the raw key that was used to generate the address
            const rawKey = bip32priv.to_raw_key();
            if (!rawKey || typeof rawKey.as_bytes !== 'function') {
                throw new Error('Failed to extract raw key from BIP32 private key');
            }
            
            const keyBytes = rawKey.as_bytes();
            if (!keyBytes || keyBytes.length < 32) {
                throw new Error('Raw key bytes are invalid or too short');
            }
            
            // Only use the first 32 bytes (the actual private key)
            const privateKeyBytes = keyBytes.slice(0, 32);
            return Buffer.from(privateKeyBytes).toString('hex');
        } catch (error) {
            throw new Error(`Failed to extract Ed25519 private key: ${error.message}`);
        }
    }

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
    @track showSeedPhraseVerification = false;
    @track seedPhraseInputs = [];
    @track seedPhraseErrorMessage = '';
    @track originalSeedPhrase = [];

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
            this.showSeedPhraseVerification = false;
            this.seedPhraseInputs = [];
            this.originalSeedPhrase = [];
            this.seedPhraseErrorMessage = '';
            return;
        }
        
        this.selectedWalletSetId = newWalletSetId;
        this.pickerErrorMessage = '';
        
        if (newWalletSetId) {
            try {
                const nextIndex = await getNextAccountIndex({ walletSetId: newWalletSetId });
                this.accountIndex = String(nextIndex);
                this.accountIndexErrorMessage = '';
                
                // Initialize seed phrase verification
                await this.initializeSeedPhraseVerification();
            } catch (error) {
                this.handleError(error, 'Failed to fetch next account index');
                this.accountIndex = '0';
            }
        } else {
            this.accountIndex = '0';
            this.accountIndexErrorMessage = '';
            this.showSeedPhraseVerification = false;
            this.seedPhraseInputs = [];
            this.originalSeedPhrase = [];
            this.seedPhraseErrorMessage = '';
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

        // If seed phrase verification is required, validate it on server first
        if (this.showSeedPhraseVerification) {
            const enteredPhrase = this.seedPhraseInputs.map(input => input.value.trim()).join(' ');
            
            if (!enteredPhrase || enteredPhrase.split(' ').length !== 24) {
                this.seedPhraseErrorMessage = 'Please enter all 24 words correctly.';
                this.showToast('Error', this.seedPhraseErrorMessage, 'error');
                this.isLoading = false;
                return;
            }

            try {
                this.currentStep = 'Verifying seed phrase';
                this.progressMessage = 'Checking seed phrase on server...';
                
                const isValid = await verifySeedPhrase({ 
                    walletSetId: this.selectedWalletSetId, 
                    userSeedPhrase: enteredPhrase 
                });
                
                if (!isValid) {
                    this.seedPhraseErrorMessage = 'Seed phrase is incorrect. Please check your entries.';
                    this.showToast('Error', this.seedPhraseErrorMessage, 'error');
                    this.isLoading = false;
                    return;
                }
            } catch (error) {
                this.seedPhraseErrorMessage = 'Error verifying seed phrase: ' + (error.body?.message || error.message);
                this.showToast('Error', this.seedPhraseErrorMessage, 'error');
                this.isLoading = false;
                return;
            }
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

    // Seed phrase verification methods
    async initializeSeedPhraseVerification() {
        if (!this.selectedWalletSetId) return;

        try {
            // Create empty input fields for 24 words (no prefilling)
            this.seedPhraseInputs = Array.from({ length: 24 }, (_, index) => {
                return {
                    label: `Word ${index + 1}`,
                    value: '' // Empty input field - user must enter seed phrase
                };
            });

            this.showSeedPhraseVerification = true;
            this.seedPhraseErrorMessage = '';
            this.originalSeedPhrase = []; // No original seed phrase stored
        } catch (error) {
            this.errorMessage = 'Failed to initialize seed phrase verification: ' + (error.message || error);
            this.showToast('Error', this.errorMessage, 'error');
        }
    }

    handleSeedPhraseChange(event) {
        const index = parseInt(event.target.dataset.index);
        this.seedPhraseInputs[index].value = event.target.value.toLowerCase().trim();
        this.seedPhraseInputs = [...this.seedPhraseInputs];
        this.seedPhraseErrorMessage = '';
    }

    isSeedPhraseValid() {
        if (!this.showSeedPhraseVerification) {
            return true;
        }

        // Basic client-side validation: check if all fields are filled
        const enteredPhrase = this.seedPhraseInputs.map(input => input.value.trim());
        return enteredPhrase.every(word => word.length > 0) && enteredPhrase.length === 24;
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
    async generateAddressesUntilUnused(accountKey, derivationPath, accountIndexNum, stakeCred, network, paymentKeyHash, walletId) {
        const targetConsecutive = this.TARGET_CONSECUTIVE_ADDRESSES;
        const typeLabel = derivationPath === this.DERIVATION_PATHS.RECEIVING ? 'receiving' : 'change';

        this.updateProgress(`Generating ${typeLabel} addresses`, `Finding ${targetConsecutive} consecutive unused addresses...`);

        // Phase 1: Generate and check addresses
        const addresses = await this.generateAndCheckAddresses(
            accountKey, derivationPath, accountIndexNum, stakeCred, network, paymentKeyHash, typeLabel, targetConsecutive
        );

        // Phase 2: Create UTXO records
        await this.createUTXORecords(addresses, typeLabel, walletId);

        // Phase 3: Sync assets and transactions
        await this.syncAddresses(addresses, typeLabel);

        return addresses;
    }

    async generateAndCheckAddresses(accountKey, derivationPath, accountIndexNum, stakeCred, network, paymentKeyHash, typeLabel, targetConsecutive) {
        const addresses = [];
        let consecutiveUnused = 0;
        let index = 0;

        while (consecutiveUnused < targetConsecutive) {
            this.updateProgress(`Checking ${typeLabel} address #${index}`, 
                `Phase 1 - ${consecutiveUnused}/${targetConsecutive} consecutive unused found`);

            const addressData = await this.deriveAndVerifyAddress(
                accountKey, derivationPath, accountIndexNum, stakeCred, network, paymentKeyHash, index, typeLabel
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

    async deriveAndVerifyAddress(accountKey, derivationPath, accountIndexNum, stakeCred, network, paymentKeyHash, index, typeLabel) {
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
            publicKey: privateKey.to_public().to_bech32(), // xpub
            privateKey: privateKey.to_bech32(),            // xprv
            address: bech32Address,
            paymentKeyHash: publicKey.to_raw_key().hash().to_hex(),
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

        // Use the seed phrase entered by user (already verified on server)
        let mnemonic;
        if (this.showSeedPhraseVerification) {
            // Use the verified seed phrase from user input
            const enteredPhrase = this.seedPhraseInputs.map(input => input.value.trim());
            mnemonic = enteredPhrase.join(' ');
        } else {
            // Fallback to getting from database (for backward compatibility)
            this.currentStep = 'Retrieving seed phrase';
            mnemonic = await getEncryptedSeedPhrase({ walletSetId: this.selectedWalletSetId });
        }
        
        if (!mnemonic) {
            throw new Error('Seed phrase is empty or null');
        }
        if (!window.bip39.validateMnemonic(mnemonic)) {
            throw new Error('Decrypted mnemonic is invalid');
        }

        this.currentStep = 'Deriving cryptographic keys';
        const entropy = window.bip39.mnemonicToEntropy(mnemonic);
        const seed = Buffer.from(entropy, 'hex');
        const rootKey = window.cardanoSerialization.Bip32PrivateKey.from_bip39_entropy(seed, Buffer.from(''));

        const harden = (num) => 0x80000000 + num;

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
        const paymentKeyHash = paymentPublicKey.to_raw_key().hash();
        const paymentCred = window.cardanoSerialization.Credential.from_keyhash(paymentKeyHash);

        const baseAddress = window.cardanoSerialization.BaseAddress.new(
            network.network_id(),
            paymentCred,
            stakeCred
        );
        const bech32Address = baseAddress.to_address().to_bech32();

        const recordId = await createWallet({
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

        // Generate receiving addresses with full syncing (usage check, creation, and asset/transaction sync)
        const receivingAddresses = await this.generateAddressesUntilUnused(
            accountKey,
            this.DERIVATION_PATHS.RECEIVING, // derivation path for receiving addresses
            accountIndexNum,
            stakeCred,
            network,
            paymentKeyHash,
            recordId
        );

        // Generate change addresses with full syncing (usage check, creation, and asset/transaction sync)
        const changeAddresses = await this.generateAddressesUntilUnused(
            accountKey,
            this.DERIVATION_PATHS.CHANGE, // derivation path for change addresses
            accountIndexNum,
            stakeCred,
            network,
            paymentKeyHash,
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
        this.showSeedPhraseVerification = false;
        this.seedPhraseInputs = [];
        this.originalSeedPhrase = [];
        this.seedPhraseErrorMessage = '';
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