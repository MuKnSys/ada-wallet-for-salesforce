import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
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
import checkIsAddressUsed from '@salesforce/apex/UTXOController.checkIsAddressUsed';
import getWalletSetWithSeedPhrase from '@salesforce/apex/UTXOController.getWalletSetWithSeedPhrase';

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
    @track hasSeedPhrasePermission = false;
    @track dummyState = false; // For forcing re-render
    @track filterText = '';
    @track isLibraryLoaded = false;
    displayLimit = 5; // Limit to 5 addresses per tab
    wiredAddressesResult; // To store the wired result for refresh

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
            label: 'Staking Key Hash',
            fieldName: 'truncatedStakingKeyHash',
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
            this.showToast('Error', this.error, 'error');
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
                truncatedAddress: this.truncateText(addr.Address__c, 40, 20, 10),
                truncatedStakingKeyHash: this.truncateText(addr.Staking_Key_Hash__c, 40, 20, 10)
            }));
            this.externalAddresses = addresses.filter(addr => addr.Type__c === '0');
            this.internalAddresses = addresses.filter(addr => addr.Type__c === '1');
            this.displayedExternalAddresses = this.externalAddresses.slice(0, this.displayLimit);
            this.displayedInternalAddresses = this.internalAddresses.slice(0, this.displayLimit);
            this.updateTabState(this.activeTab);
            this.error = undefined;
            this.ensureUTXOAddresses();
        } else if (error) {
            this.error = error.body?.message || 'Unknown error';
            this.externalAddresses = [];
            this.internalAddresses = [];
            this.displayedExternalAddresses = [];
            this.displayedInternalAddresses = [];
            this.currentTabCount = 0;
            this.showToast('Error Loading Addresses', this.error, 'error');
        }
        this.isLoading = false;
    }

    async ensureUTXOAddresses() {
        if (!this.isLibraryLoaded) {
            return;
        }

        try {
            // Fetch wallet details to get Wallet_Set__c and Account_Index__c
            const wallet = await getWallet({ walletId: this.recordId });
            if (!wallet || !wallet.Wallet_Set__c || wallet.Account_Index__c == null) {
                throw new Error('Invalid wallet data: Missing Wallet Set or Account Index');
            }

            // Fetch Wallet Set to get the mnemonic
            const walletSet = await getWalletSetWithSeedPhrase({ walletSetId: wallet.Wallet_Set__c });
            const mnemonic = await decrypt({ encryptedText: walletSet.Seed_Phrase__c });

            if (!mnemonic) {
                throw new Error('Seed phrase is empty or null');
            }

            if (!window.bip39.validateMnemonic(mnemonic)) {
                throw new Error('Decrypted mnemonic is invalid');
            }

            // Derive keys
            const entropy = window.bip39.mnemonicToEntropy(mnemonic);
            const seed = Buffer.from(entropy, 'hex');
            const rootKey = window.cardanoSerialization.Bip32PrivateKey.from_bip39_entropy(seed, Buffer.from(''));
            const harden = (num) => 0x80000000 + num;
            const accountIndexNum = parseInt(wallet.Account_Index__c, 10);
            if (accountIndexNum < 0) {
                throw new Error('Account Index must be non-negative');
            }
            const accountKey = rootKey
                .derive(harden(1852))
                .derive(harden(1815))
                .derive(harden(accountIndexNum));

            const network = window.cardanoSerialization.NetworkInfo.mainnet();

            // Ensure 20 consecutive unused receiving addresses (Type__c = '0')
            await this.ensureConsecutiveUnusedAddresses(accountKey, network, '0', this.externalAddresses);

            // Ensure 20 consecutive unused change addresses (Type__c = '1')
            await this.ensureConsecutiveUnusedAddresses(accountKey, network, '1', this.internalAddresses);

            // Refresh the UTXO addresses after derivation
            await refreshApex(this.wiredAddressesResult);
        } catch (error) {
            this.showToast('Error Ensuring UTXO Addresses', error.message || 'Unknown error', 'error');
        }
    }

    async ensureConsecutiveUnusedAddresses(accountKey, network, type, existingAddresses) {
        const chainType = type === '0' ? 0 : 1; // 0 for receiving (external), 1 for change (internal)
        const typeLabel = type === '0' ? 'receiving' : 'change';
    
        // Sort existing addresses by index to check for consecutive unused
        const sortedAddresses = [...existingAddresses].sort((a, b) => parseInt(a.Index__c, 10) - parseInt(b.Index__c, 10));
        let consecutiveUnused = 0;
        let currentIndex = 0;
        let maxIndex = sortedAddresses.length > 0 ? parseInt(sortedAddresses[sortedAddresses.length - 1].Index__c, 10) : -1;

        // First, check existing addresses for consecutive unused sequence
        if (sortedAddresses.length > 0) {
            for (let i = 0; i <= maxIndex; i++) {
                const addr = sortedAddresses.find(a => parseInt(a.Index__c, 10) === i);
                if (!addr) {
                    // If the address doesn't exist at this index, treat it as unused
                    consecutiveUnused++;
                } else {
                    let isUsed;
                    try {
                        isUsed = await checkIsAddressUsed({ address: addr.Address__c });
                    } catch (error) {
                        throw new Error(`Failed to check address usage for ${typeLabel} address at index ${i}: ${error.body?.message || error.message}`);
                    }
    
                    if (isUsed) {
                        consecutiveUnused = 0;
                    } else {
                        consecutiveUnused++;
                    }
                }
    
                if (consecutiveUnused >= 20) {
                    return;
                }
            }
        }
    
        // If we don't have 20 consecutive unused addresses, start deriving from the next index
        currentIndex = maxIndex + 1 >= 0 ? maxIndex + 1 : 0;
        while (consecutiveUnused < 20) {
            // Derive the address for the current index
            const utxoPrivateKey = accountKey
                .derive(chainType)
                .derive(currentIndex);
            const utxoPublicKey = utxoPrivateKey.to_public();
            const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
            const utxoCred = window.cardanoSerialization.Credential.from_keyhash(utxoKeyHash);
    
            const stakePrivateKey = accountKey
                .derive(2)
                .derive(0)
                .to_raw_key();
            const stakePublicKey = stakePrivateKey.to_public();
            const stakeKeyHash = stakePublicKey.hash();
            const stakeCred = window.cardanoSerialization.Credential.from_keyhash(stakeKeyHash);
    
            const baseAddress = window.cardanoSerialization.BaseAddress.new(
                network.network_id(),
                utxoCred,
                stakeCred
            );
            const bech32Address = baseAddress.to_address().to_bech32();
    
            // Check if the address is used
            let isUsed;
            try {
                isUsed = await checkIsAddressUsed({ address: bech32Address });
            } catch (error) {
                throw new Error(`Failed to check address usage for ${typeLabel} address at index ${currentIndex}: ${error.body?.message || error.message}`);
            }
    
            if (isUsed) {
                consecutiveUnused = 0;
            } else {
                consecutiveUnused++;
            }
    
            // Save the new address
            const newAddress = {
                index: currentIndex,
                publicKey: utxoPublicKey.to_bech32(),
                address: bech32Address,
                stakingKeyHash: stakeKeyHash.to_hex(),
                path: `m/1852'/1815'/${accountKey.Account_Index__c}'/${chainType}/${currentIndex}`
            };
    
            try {
                if (type === '0') {
                    await addReceivingUTXOAddress({
                        walletId: this.recordId,
                        receivingAddress: newAddress
                    });
                } else {
                    await addChangeUTXOAddress({
                        walletId: this.recordId,
                        changeAddress: newAddress
                    });
                }
            } catch (error) {
                throw new Error(`Failed to save ${typeLabel} address: ${error.body?.message || error.message}`);
            }
    
            currentIndex++;
        }
    }

    truncateText(text, maxLength, firstChars, lastChars) {
        if (!text || text.length <= maxLength) {
            return text;
        }
        const firstPart = text.substring(0, firstChars);
        const lastPart = text.substring(text.length - lastChars);
        return `${firstPart}...${lastPart}`;
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
            this.currentTabCount = this.externalAddresses.length; // Use full list for count
        } else if (tab === 'internal') {
            this.currentTabLabel = 'Internal';
            this.currentTabCount = this.internalAddresses.length; // Use full list for count
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

    handleViewAll(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'force__dynamicRelatedListViewAll'
            },
            state: {
                'force__flexipageId': 'Wallet_Record_Page1',
                'force__cmpId': 'lst_dynamicRelatedList',
                'force__recordId': this.recordId
            }
        });
    }

    async generateAddress() {
        this.isLoading = true;
        try {
            const CardanoWasm = window.cardanoSerialization;

            // Determine the type based on the active tab
            const type = this.activeTab === 'external' ? '0' : '1'; // '0' for receiving (External), '1' for change (Internal)
            
            // Get the next index for the specified type
            const nextIndex = await getNextUTXOIndex({ walletId: this.recordId, type: type });

            // Fetch Wallet__c record to get the encrypted Account_Private_Key__c
            const wallet = await getWallet({ walletId: this.recordId });

            if (!wallet || !wallet.Account_Private_Key__c) {
                throw new Error('Wallet record or Account Private Key not found');
            }

            // Decrypt the Account_Private_Key__c
            const accountPrivateKeyBech32 = await decrypt({ encryptedText: wallet.Account_Private_Key__c });
            
            // Convert the Bech32 private key to a Bip32PrivateKey
            const accountPrivateKey = CardanoWasm.Bip32PrivateKey.from_bech32(accountPrivateKeyBech32);

            // Derive the new UTXO address for the next index
            const network = CardanoWasm.NetworkInfo.mainnet();
            const chainType = type === '0' ? 0 : 1; // 0 for external (receiving), 1 for internal (change)

            // Derive payment key (m/.../{chainType}/{nextIndex})
            const utxoPrivateKey = accountPrivateKey
                .derive(chainType) // External (0) or Internal (1) chain
                .derive(nextIndex); // Index
            const utxoPublicKey = utxoPrivateKey.to_public();
            const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
            const utxoCred = CardanoWasm.Credential.from_keyhash(utxoKeyHash);

            // Derive stake key (m/.../2/{nextIndex})
            const stakePrivateKey = accountPrivateKey
                .derive(2) // Stake chain
                .derive(nextIndex) // Index
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

            // Save the new address to the database based on the type
            const newAddress = {
                index: nextIndex,
                publicKey: utxoPublicKey.to_bech32(),
                address: bech32Address,
                stakingKeyHash: stakeKeyHash.to_hex(),
                path: `m/1852'/1815'/${wallet.Account_Index__c}'/${chainType}/${nextIndex}`
            };

            if (type === '0') {
                await addReceivingUTXOAddress({
                    walletId: this.recordId,
                    receivingAddress: newAddress
                });
            } else {
                await addChangeUTXOAddress({
                    walletId: this.recordId,
                    changeAddress: newAddress
                });
            }

            // Refresh the UTXO addresses to update the counts and lists
            await refreshApex(this.wiredAddressesResult);

            // Show a toast notification with the new address
            this.showToast(
                'New UTXO Address Generated',
                `New ${type === '0' ? 'receiving' : 'change'} address for index ${nextIndex}: ${bech32Address}`,
                'success'
            );
        } catch (error) {
            this.showToast('Error Generating Address', error.message || 'Unknown error', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}