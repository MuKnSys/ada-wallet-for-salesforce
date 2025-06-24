import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import { NavigationMixin } from 'lightning/navigation';

import cardanoLibrary from '@salesforce/resourceUrl/cardanoSerialization';
import bip39Library from '@salesforce/resourceUrl/bip39';

import createUTXOAddresses from '@salesforce/apex/UTXOController.createUTXOAddresses';
import getDecryptedSeedPhrase from '@salesforce/apex/CreateNewWalletCtrl.getDecryptedSeedPhrase';
import createWallet from '@salesforce/apex/CreateNewWalletCtrl.createWallet';
import getNextAccountIndex from '@salesforce/apex/CreateNewWalletCtrl.getNextAccountIndex';
import isIndexValid from '@salesforce/apex/CreateNewWalletCtrl.isIndexValid';
import checkIsAddressUsed from '@salesforce/apex/CreateNewWalletCtrl.checkIsAddressUsed';
import syncAssetsForWallet from '@salesforce/apex/UTXOController.syncAssetsForWallet';
import getAddressTotal from '@salesforce/apex/BlockfrostService.getAddressTotal';

export default class CreateNewWallet extends NavigationMixin(LightningElement) {
    @track librariesLoaded = false;
    @track selectedWalletSetId = '';
    @track walletName = '';
    @track accountIndex = '0';
    @track errorMessage = '';
    @track pickerErrorMessage = '';
    @track accountIndexErrorMessage = '';
    @track isLoading = false;

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
        }
    }

    async generateAddresses(accountKey, derivationPath, accountIndexNum, stakeCred, network, stakeKeyHash) {
        const addresses = [];
        let consecutiveUnused = 0;
        let index = 0;

        while (consecutiveUnused < 20) {
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

            // Check if address has any UTXOs (used)
            let isUsed = false;
            try {
                isUsed = await checkIsAddressUsed({ address: bech32Address });
            } catch (err) {
                // eslint-disable-next-line no-console
                console.error('UTXO usage check failed', err);
            }

            if (isUsed) {
                consecutiveUnused = 0;
                try {
                    await getAddressTotal({ address: bech32Address });
                } catch (e) {
                    // ignore totals fetch errors silently
                }
            } else {
                consecutiveUnused++;
            }

            addresses.push({
                index: index,
                publicKey: publicKey.to_bech32(),
                address: bech32Address,
                stakingKeyHash: stakeKeyHash.to_hex(),
                path: `m/1852'/1815'/${accountIndexNum}'/${derivationPath}/${index}`
            });
            index++;
        }
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

        // Generate receiving addresses
        const utxoKeysAndAddresses = await this.generateAddresses(
            accountKey,
            0, // derivation path for receiving addresses
            accountIndexNum,
            stakeCred,
            network,
            stakeKeyHash
        );

        // Generate change addresses
        const changeKeysAndAddresses = await this.generateAddresses(
            accountKey,
            1, // derivation path for change addresses
            accountIndexNum,
            stakeCred,
            network,
            stakeKeyHash
        );

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

                if (!recordId) {
                    throw new Error('Error creating wallet record');
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

                // Sync ADA assets for used addresses
                try {
                    await syncAssetsForWallet({ walletId: recordId });
                } catch (err) {
                    // eslint-disable-next-line no-console
                    console.error('ADA asset sync for wallet failed', err);
                }
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
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}