import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import { NavigationMixin } from 'lightning/navigation';

import cardanoLibrary from '@salesforce/resourceUrl/cardanoSerialization';
import bip39Library from '@salesforce/resourceUrl/bip39';

import getWalletSetWithSeedPhrase from '@salesforce/apex/CreateNewWalletCtrl.getWalletSetWithSeedPhrase';
import createUTXOAddresses from '@salesforce/apex/UTXOController.createUTXOAddresses';
import decrypt from '@salesforce/apex/DataEncryptor.decrypt';
import createWallet from '@salesforce/apex/CreateNewWalletCtrl.createWallet';
import checkIsAddressUsed from '@salesforce/apex/CreateNewWalletCtrl.checkIsAddressUsed';
import getNextAccountIndex from '@salesforce/apex/CreateNewWalletCtrl.getNextAccountIndex';
import isIndexValid from '@salesforce/apex/CreateNewWalletCtrl.isIndexValid';

export default class CreateNewWallet extends NavigationMixin(LightningElement) {
    @track isLibraryLoaded = false;
    @track selectedWalletSetId = '';
    @track walletName = '';
    @track accountIndex = '0';
    @track errorMessage = '';
    @track pickerErrorMessage = '';
    @track accountIndexErrorMessage = '';
    @track isCreateDisabled = true;
    @track isLoading = false;

    get buttonLabel() {
        return this.isLoading ? 'Creating...' : 'Create Wallet';
    }

    constructor() {
        super();
    }

    connectedCallback() {
        this.loadLibraries();
    }

    async loadLibraries() {
        if (this.isLibraryLoaded) {
            return;
        }

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

            this.isLibraryLoaded = true;
            this.updateCreateButtonState();

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
        
        this.updateCreateButtonState();
    }

    async handleWalletNameChange(event) {
        this.walletName = event.target.value || '';
        this.updateCreateButtonState();
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

        this.updateCreateButtonState();
    }

    updateCreateButtonState() {
        this.isCreateDisabled = !(
            this.selectedWalletSetId &&
            this.walletName.trim() &&
            this.accountIndex &&
            !isNaN(this.accountIndex) &&
            !this.accountIndexErrorMessage &&
            this.isLibraryLoaded &&
            !this.isLoading
        );
    }

    get defaultFilter() {
        return {
            criteria: []
        };
    }

    async handleCreate() {
        this.errorMessage = '';
        this.isLoading = true;
        this.updateCreateButtonState();

        await new Promise(resolve => setTimeout(resolve, 0));

        if (!this.isLibraryLoaded) {
            this.errorMessage = 'Libraries not loaded. Please try again.';
            this.showToast('Error', this.errorMessage, 'error');
            this.isLoading = false;
            this.updateCreateButtonState();
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
            this.updateCreateButtonState();
        }
    }

    async createWallet() {
        if (!this.selectedWalletSetId || !this.walletName || isNaN(this.accountIndex)) {
            throw new Error('Missing required inputs: Wallet Set ID, Wallet Name, or valid Account Index');
        }

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

        let mnemonic;
        try {
            const walletSet = await getWalletSetWithSeedPhrase({ walletSetId: this.selectedWalletSetId });
            mnemonic = await decrypt({ encryptedText: walletSet.Seed_Phrase__c });

            if (!mnemonic) {
                throw new Error('Seed phrase is empty or null');
            }

            if (!window.bip39.validateMnemonic(mnemonic)) {
                throw new Error('Decrypted mnemonic is invalid');
            }
        } catch (error) {
            throw new Error('Failed to retrieve seed phrase: ' + (error.body?.message || error.message));
        }

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

        const utxoKeysAndAddresses = [];
        const changeKeysAndAddresses = [];
        const network = window.cardanoSerialization.NetworkInfo.mainnet();

        // Derive receiving addresses until 20 consecutive unused addresses
        let consecutiveUnused = 0;
        let index = 0;
        while (consecutiveUnused < 20) {
            const utxoPrivateKey = accountKey
                .derive(0)
                .derive(index);
            const utxoPublicKey = utxoPrivateKey.to_public();
            const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
            const utxoCred = window.cardanoSerialization.Credential.from_keyhash(utxoKeyHash);

            const baseAddress = window.cardanoSerialization.BaseAddress.new(
                network.network_id(),
                utxoCred,
                stakeCred
            );
            const bech32Address = baseAddress.to_address().to_bech32();

            let isUsed;
            try {
                isUsed = await checkIsAddressUsed({ address: bech32Address });
            } catch (error) {
                throw new Error('Failed to check address usage for receiving address at index ' + index + ': ' + (error.body?.message || error.message));
            }

            if (isUsed) {
                consecutiveUnused = 0;
            } else {
                consecutiveUnused++;
            }

            utxoKeysAndAddresses.push({
                index: index,
                publicKey: utxoPublicKey.to_bech32(),
                address: bech32Address,
                stakingKeyHash: stakeKeyHash.to_hex(),
                path: `m/1852'/1815'/${accountIndexNum}'/0/${index}`
            });

            index++;
        }

        // Derive change addresses until 20 consecutive unused addresses
        consecutiveUnused = 0;
        index = 0;
        while (consecutiveUnused < 20) {
            const changePrivateKey = accountKey
                .derive(1)
                .derive(index);
            const changePublicKey = changePrivateKey.to_public();
            const changeKeyHash = changePublicKey.to_raw_key().hash();
            const changeCred = window.cardanoSerialization.Credential.from_keyhash(changeKeyHash);

            const baseAddress = window.cardanoSerialization.BaseAddress.new(
                network.network_id(),
                changeCred,
                stakeCred
            );
            const changeBech32Address = baseAddress.to_address().to_bech32();

            let isUsed;
            try {
                isUsed = await checkIsAddressUsed({ address: changeBech32Address });
            } catch (error) {
                throw new Error('Failed to check address usage for change address at index ' + index + ': ' + (error.body?.message || error.message));
            }

            if (isUsed) {
                consecutiveUnused = 0;
            } else {
                consecutiveUnused++;
            }

            changeKeysAndAddresses.push({
                index: index,
                publicKey: changePublicKey.to_bech32(),
                address: changeBech32Address,
                stakingKeyHash: stakeKeyHash.to_hex(),
                path: `m/1852'/1815'/${accountIndexNum}'/1/${index}`
            });

            index++;
        }

        try {
            const paymentKeyHash = paymentPublicKey.to_raw_key().hash();
            const paymentCred = window.cardanoSerialization.Credential.from_keyhash(paymentKeyHash);

            const baseAddress = window.cardanoSerialization.BaseAddress.new(
                network.network_id(),
                paymentCred,
                stakeCred
            );
            const bech32Address = baseAddress.to_address().to_bech32();

            let recordId;
            try {
                recordId = await createWallet({
                    walletSetId: this.selectedWalletSetId,
                    walletName: this.walletName,
                    address: bech32Address,
                    accountPrivateKey: paymentPrivateKey.to_bech32(),
                    accountPublicKey: paymentPublicKey.to_bech32(),
                    accountIndex: accountIndexNum
                });

                if (!recordId || typeof recordId !== 'string' || !/^[a-zA-Z0-9]{15,18}$/.test(recordId)) {
                    throw new Error('Invalid record ID returned from Apex: ' + recordId);
                }
            } catch (error) {
                throw new Error('Failed to save wallet: ' + (error.body?.message || error.message));
            }

            const receivingAddresses = utxoKeysAndAddresses.map(addr => ({
                index: addr.index,
                publicKey: addr.publicKey,
                address: addr.address,
                stakingKeyHash: addr.stakingKeyHash,
                path: addr.path
            }));
            const changeAddresses = changeKeysAndAddresses.map(addr => ({
                index: addr.index,
                publicKey: addr.publicKey,
                address: addr.address,
                stakingKeyHash: addr.stakingKeyHash,
                path: addr.path
            }));

            try {
                await createUTXOAddresses({
                    walletId: recordId,
                    receivingAddresses: receivingAddresses,
                    changeAddresses: changeAddresses
                });
            } catch (error) {
                throw new Error('Failed to save UTxO addresses: ' + (error.body?.message || error.message));
            }

            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    objectApiName: 'Wallet__c',
                    actionName: 'view'
                }
            }, true);
        } catch (error) {
            throw new Error('Failed to create address: ' + error.message);
        }
    }

    resetForm() {
        this.selectedWalletSetId = '';
        this.walletName = '';
        this.accountIndex = '0';
        this.errorMessage = '';
        this.pickerErrorMessage = '';
        this.accountIndexErrorMessage = '';
        this.isCreateDisabled = true;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}