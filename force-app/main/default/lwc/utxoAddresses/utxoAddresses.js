import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';

import cardanoLibrary from '@salesforce/resourceUrl/cardanoSerialization';
import bip39Library from '@salesforce/resourceUrl/bip39';

import getWallet from '@salesforce/apex/UTXOController.getWallet';
import decrypt from '@salesforce/apex/DataEncryptor.decrypt';
import getUTXOAddresses from '@salesforce/apex/UTXOController.getUTXOAddresses';
import getUserPermissions from '@salesforce/apex/UTXOController.getUserPermissions';
import getNextUTXOIndex from '@salesforce/apex/UTXOController.getNextUTXOIndex';
import addReceivingUTXOAddress from '@salesforce/apex/UTXOController.addReceivingUTXOAddress';
import addChangeUTXOAddress from '@salesforce/apex/UTXOController.addChangeUTXOAddress';
import syncAssetsAndTransactions from '@salesforce/apex/UTXOAssetController.syncAssetsAndTransactions';
import setAddressesUsed from '@salesforce/apex/UTXOAssetController.setAddressesUsed';
import { isAddressActuallyUsed, truncateText, showToast } from 'c/utils';

export default class UtxoAddresses extends NavigationMixin(LightningElement) {
    @api recordId;
    @track externalAddresses = [];
    @track internalAddresses = [];
    @track displayedExternalAddresses = [];
    @track displayedInternalAddresses = [];
    @track error;
    @track isLoading = false;
    @track activeTab = 'external';
    @track currentTabLabel = 'External';
    @track currentTabCount = 0;
    @track currentUnusedCount = 0;
    @track hasSeedPhrasePermission = false;
    @track dummyState = false; // For forcing re-render
    @track filterText = '';
    @track isLibraryLoaded = false;
    displayLimit = 5; // Limit to 5 addresses per tab
    wiredAddressesResult; // To store the wired result for refresh
    viewLess = true;

    // Datatable columns
    columns = [
        {
            label: 'UTXO Address Name',
            fieldName: 'recordLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'Name' },
                target: '_self'
            },
            sortable: true,
            cellAttributes: { class: 'slds-text-link' }
        },
        { label: 'Path', fieldName: 'Path__c', type: 'text' },
        {
            label: 'Address',
            fieldName: 'cardanoScanLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'truncatedAddress' },
                target: '_blank',
                tooltip: 'Go to CardanoScan explorer'
            },
            cellAttributes: { class: 'slds-text-link address-link' }
        },
        {
            label: 'Payment Key Hash',
            fieldName: 'truncatedPaymentKeyHash',
            type: 'text'
        }
    ];
    
    get hasExternalAddresses() {
        return this.externalAddresses?.length > 0;
    }

    get hasInternalAddresses() {
        return this.internalAddresses?.length > 0;
    }

    renderedCallback() {
        if (!this.isLibraryLoaded) {            
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
            if (!window.cardanoSerialization || !window.bip39) {
                throw new Error('Required libraries (cardanoSerialization or bip39) not properly initialized');
            }
            this.isLibraryLoaded = true;
        } catch (error) {
            this.error = 'Library loading failed: ' + (error.message || error);
            showToast(this, 'Error', this.error, 'error');
            setTimeout(() => this.loadLibraries(), 2000);
        }
    }

    @wire(getUserPermissions)
    wiredPermissions({ error, data }) {
        if (data) {
            this.hasSeedPhrasePermission = data.includes('Ada_Wallet_Seed_Phrase');
            this.dummyState = !this.dummyState;
        } else if (error) {
            this.hasSeedPhrasePermission = false;
            this.dummyState = !this.dummyState;
        }
    }

    @wire(getUTXOAddresses, { walletId: '$recordId' })
    wiredAddresses(result) {
        this.wiredAddressesResult = result;
        this.isLoading = true;
        const { error, data } = result;
        if (data) {
            const addresses = data.map(addr => ({
                ...addr,
                recordLink: `/lightning/r/UTXO_Address__c/${addr.Id}/view`,
                cardanoScanLink: `https://cardanoscan.io/address/${addr.Address__c}`,
                truncatedAddress: truncateText(addr.Address__c, 40, 20, 10),
                truncatedPaymentKeyHash: truncateText(addr.Payment_Key_Hash__c, 40, 20, 10),
                truncatedStakingKeyHash: truncateText(addr.Staking_Key_Hash__c, 40, 20, 10)
            }));
            this.externalAddresses = addresses.filter(addr => addr.Type__c === '0');
            this.internalAddresses = addresses.filter(addr => addr.Type__c === '1');
            this.displayedExternalAddresses = this.externalAddresses.slice(0, this.displayLimit);
            this.displayedInternalAddresses = this.internalAddresses.slice(0, this.displayLimit);
            this.updateTabState(this.activeTab);
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || 'Unknown error';
            this.externalAddresses = [];
            this.internalAddresses = [];
            this.displayedExternalAddresses = [];
            this.displayedInternalAddresses = [];
            this.currentTabCount = 0;
            this.currentUnusedCount = 0;
            showToast(this, 'Error Loading Addresses', this.error, 'error');
        }
        this.isLoading = false;
    }

    handleExternalTabActive() {
        this.activeTab = 'external';
        this.updateTabState('external');
        this.applyFilter();
    }

    handleInternalTabActive() {
        this.activeTab = 'internal';
        this.updateTabState('internal');
        this.applyFilter();
    }

    updateTabState(tab) {
        if (tab === 'external') {
            this.currentTabLabel = 'External';
            this.currentTabCount = this.externalAddresses.length;
            this.currentUnusedCount = this.externalAddresses.filter(addr => !addr.Is_Used__c).length;
        } else if (tab === 'internal') {
            this.currentTabLabel = 'Internal';
            this.currentTabCount = this.internalAddresses.length;
            this.currentUnusedCount = this.internalAddresses.filter(addr => !addr.Is_Used__c).length;
        }
        this.dummyState = !this.dummyState;
    }

    handleFilterChange(event) {
        this.filterText = event.target.value.toLowerCase();
        this.applyFilter();
    }

    applyFilter() {
        const filter = this.filterText.toLowerCase();
        let filteredExternal = this.externalAddresses;
        let filteredInternal = this.internalAddresses;

        if (filter) {
            filteredExternal = this.externalAddresses.filter(addr =>
                addr.Name.toLowerCase().includes(filter) ||
                addr.Path__c.toLowerCase().includes(filter) ||
                addr.Address__c.toLowerCase().includes(filter)
            );
            filteredInternal = this.internalAddresses.filter(addr =>
                addr.Name.toLowerCase().includes(filter) ||
                addr.Path__c.toLowerCase().includes(filter) ||
                addr.Address__c.toLowerCase().includes(filter)
            );
        }

        // Apply the display limit after filtering
        this.displayedExternalAddresses = filteredExternal.slice(0, this.displayLimit);
        this.displayedInternalAddresses = filteredInternal.slice(0, this.displayLimit);
        
        this.updateTabState(this.activeTab);
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'edit') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.Id,
                    objectApiName: 'UTXO_Address__c',
                    actionName: 'edit'
                }
            });
        }
    }

    handleViewAll() {
        this.displayLimit = 1000;
        this.applyFilter();
        this.viewLess = false;
    }

    handleViewLess() {
        this.displayLimit = 5;
        this.applyFilter();
        this.viewLess = true;
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

    async generateAddress() {
        this.isLoading = true;
        try {
            if (!this.isLibraryLoaded) {
                throw new Error('Cardano libraries not loaded yet. Please wait and try again.');
            }

            const type = this.activeTab === 'external' ? '0' : '1'; // '0' for receiving, '1' for change
            const typeLabel = type === '0' ? 'receiving' : 'change';
            
            // Get the next index for the specified type
            const nextIndex = await getNextUTXOIndex({ walletId: this.recordId, type: type });

            // Fetch wallet data
            const wallet = await getWallet({ walletId: this.recordId });
            if (!wallet || !wallet.Account_Private_Key__c) {
                throw new Error('Wallet record or Account Private Key not found');
            }

            // Setup cryptographic components
            const accountPrivateKeyBech32 = await decrypt({ encryptedText: wallet.Account_Private_Key__c });
            const CardanoWasm = window.cardanoSerialization;
            const accountPrivateKey = CardanoWasm.Bip32PrivateKey.from_bech32(accountPrivateKeyBech32);
            const network = CardanoWasm.NetworkInfo.mainnet();
            const accountIndexNum = wallet.Account_Index__c;
            const chainType = type === '0' ? 0 : 1; // 0 for external (receiving), 1 for internal (change)

            // Derive payment key
            const utxoPrivateKey = accountPrivateKey
                .derive(chainType)
                .derive(nextIndex);
            const utxoPublicKey = utxoPrivateKey.to_public();
            const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
            const utxoCred = CardanoWasm.Credential.from_keyhash(utxoKeyHash);

            // Derive stake key  
            const stakePrivateKey = accountPrivateKey
                .derive(2)
                .derive(0)
                .to_raw_key();
            const stakePublicKey = stakePrivateKey.to_public();
            const stakeKeyHash = stakePublicKey.hash();
            const stakeCred = CardanoWasm.Credential.from_keyhash(stakeKeyHash);

            // Create base address
            const baseAddress = CardanoWasm.BaseAddress.new(
                network.network_id(),
                utxoCred,
                stakeCred
            );
            const bech32Address = baseAddress.to_address().to_bech32();

            // Key verification
            const keyMatch = this.verifyKeyMatch(CardanoWasm, utxoPrivateKey, bech32Address);
            if (!keyMatch) {
                throw new Error(`Derived private key does not match address payment key hash for ${typeLabel} address #${nextIndex}`);
            }

            const fullPath = `m/1852'/1815'/${accountIndexNum}'/${chainType}/${nextIndex}`;

            // Create address data (using xpub/xpriv like create new wallet LWC)
            const newAddress = {
                index: nextIndex,
                publicKey: utxoPrivateKey.to_public().to_bech32(), // xpub
                privateKey: utxoPrivateKey.to_bech32(),            // xprv
                address: bech32Address,
                paymentKeyHash: utxoPublicKey.to_raw_key().hash().to_hex(), // Use payment key hash, not stake key hash
                path: fullPath
            };

            // Save to database
            let newAddressId;
            if (type === '0') {
                newAddressId = await addReceivingUTXOAddress({
                    walletId: this.recordId,
                    receivingAddress: newAddress
                });
            } else {
                newAddressId = await addChangeUTXOAddress({
                    walletId: this.recordId,
                    changeAddress: newAddress
                });
            }
            // Refresh data and notify other components
            await refreshApex(this.wiredAddressesResult);

            showToast(this, 'Success', `New ${typeLabel.charAt(0).toUpperCase() + typeLabel.slice(1)} Address Generated`, 'success');

        } catch (error) {
            showToast(this, 'Error', `Failed to generate address: ${error.message}`, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRefreshAddressCounts() {
        this.isLoading = true;

        try {
            if (!this.isLibraryLoaded) {
                throw new Error('Cardano libraries not loaded yet. Please wait and try again.');
            }
            await this.syncExistingAddresses();

            // Refresh data
            await refreshApex(this.wiredAddressesResult);
            const message = 'UTXO refresh completed.';
                
            showToast(this, 'Success', message, 'success');

        } catch (err) {
            const msg = err.body?.message || err.message || 'Unknown error';
            showToast(this, 'Error', `UTXO refresh failed: ${msg}`, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Sync assets and transactions for all existing UTXO addresses
     */
    async syncExistingAddresses() {
        const allAddresses = [...this.externalAddresses, ...this.internalAddresses];
        
        let syncedCount = 0;
        let errorCount = 0;
        
        for (const address of allAddresses) {
            try {
                const syncResult = await syncAssetsAndTransactions({ utxoAddressId: address.Id });
                
                if (syncResult.success) {
                    syncedCount++;
                } else {
                    errorCount++;
                }

                if (syncResult.success && syncResult.statistics) {
                    const stats = syncResult.statistics;
                    address.isUsed = isAddressActuallyUsed(stats);
                }
            } catch (syncError) {
                errorCount++;
            }
        }
        
        const usedAddressesIds = [];
        for (const address of allAddresses) {
            if (address.isUsed) {
                usedAddressesIds.push(address.utxoAddressId);
            }
        }        

        await setAddressesUsed({ utxoAddressIds: usedAddressesIds });
        
        return { syncedCount, errorCount };
    }

    /**
     * Ensure 20 consecutive unused addresses exist, derive new ones if needed
     */
    async ensureConsecutiveUnusedAddresses(existingAddresses, derivationPath, accountPrivateKey, stakeCred, network, accountIndexNum, typeLabel) {
        const targetConsecutive = 20;
        
        // Sort existing addresses by index
        const sortedAddresses = existingAddresses
            .slice()
            .sort((a, b) => (a.Index__c ?? 0) - (b.Index__c ?? 0));
        
        // Find current consecutive unused count from the end
        let consecutiveUnused = 0;
        let lastUsedIndex = -1;
        
        // Check existing addresses from highest index down to find consecutive unused
        for (let i = sortedAddresses.length - 1; i >= 0; i--) {
            const address = sortedAddresses[i];
            
            try {
                const usageResult = await checkAddressUsageOnly({ address: address.Address__c });
                const isUsed = usageResult.isUsed || false;
                
                if (isUsed) {
                    lastUsedIndex = address.Index__c;
                    break; // Stop when we find a used address
                } else {
                    consecutiveUnused++;
                }
            } catch (error) {
                // Assume unused if check fails
                consecutiveUnused++;
            }
        }
        
        // If we already have enough consecutive unused, return empty array
        if (consecutiveUnused >= targetConsecutive) {
            return [];
        }
        
        // Calculate how many more we need and starting index
        const neededCount = targetConsecutive - consecutiveUnused;
        const nextIndex = sortedAddresses.length > 0 ? 
            Math.max(...sortedAddresses.map(a => a.Index__c ?? 0)) + 1 : 0;
        
        // Derive new addresses
        const newAddresses = [];
        const CardanoWasm = window.cardanoSerialization;
        
        for (let i = 0; i < neededCount; i++) {
            const currentIndex = nextIndex + i;
            
            try {
                // Derive payment key
                const utxoPrivateKey = accountPrivateKey
                    .derive(derivationPath)
                    .derive(currentIndex);
                const utxoPublicKey = utxoPrivateKey.to_public();
                const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
                const utxoCred = CardanoWasm.Credential.from_keyhash(utxoKeyHash);

                // Create base address
                const baseAddress = CardanoWasm.BaseAddress.new(
                    network.network_id(),
                    utxoCred,
                    stakeCred
                );
                const bech32Address = baseAddress.to_address().to_bech32();

                // Key verification
                const keyMatch = this.verifyKeyMatch(CardanoWasm, utxoPrivateKey, bech32Address);
                if (!keyMatch) {
                    throw new Error(`Derived private key does not match address payment key hash for ${typeLabel} address #${currentIndex}`);
                }

                const fullPath = `m/1852'/1815'/${accountIndexNum}'/${derivationPath}/${currentIndex}`;
                
                const addressData = {
                    index: currentIndex,
                    publicKey: utxoPrivateKey.to_public().to_bech32(), // xpub
                    privateKey: utxoPrivateKey.to_bech32(),            // xprv
                    address: bech32Address,
                    paymentKeyHash: utxoPublicKey.to_raw_key().hash().to_hex(), // Use payment key hash, not stake key hash
                    path: fullPath
                };
                
                newAddresses.push(addressData);
                
            } catch (error) {
                throw error;
            }
        }
        
        return newAddresses;
    }
}