import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';
import getUTXOAddresses from '@salesforce/apex/UTXOController.getUTXOAddresses';
import getUserPermissions from '@salesforce/apex/UTXOController.getUserPermissions';
import getNextUTXOIndex from '@salesforce/apex/UTXOController.getNextUTXOIndex';
import getWalletById from '@salesforce/apex/WalletSelector.getWalletById';
import decrypt from '@salesforce/apex/DataEncryptor.decrypt';
import cardanoLibrary from '@salesforce/resourceUrl/cardanoSerialization';
import bip39Library from '@salesforce/resourceUrl/bip39';
import addReceivingUTXOAddress from '@salesforce/apex/UTXOController.addReceivingUTXOAddress';
import addChangeUTXOAddress from '@salesforce/apex/UTXOController.addChangeUTXOAddress';
import isAddressUsed from '@salesforce/apex/BlockfrostConnector.isAddressUsed';
import getWalletSetById from '@salesforce/apex/WalletSetSelector.getWalletSetById';

export default class UtxoAddresses extends NavigationMixin(LightningElement) {
    @api recordId; // Wallet__c record ID
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

    connectedCallback() {
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Component mounted, initial activeTab: ${this.activeTab}`);
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Initial hasSeedPhrasePermission: ${this.hasSeedPhrasePermission}`);
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Record ID: ${this.recordId}`);
        this.loadLibraries();
    }

    async loadLibraries() {
        if (this.isLibraryLoaded) {
            console.log(`UtxoAddresses [${new Date().toISOString()}]: loadLibraries - already loaded, skipping`);
            return;
        }

        const scripts = [
            { name: 'cardanoSerialization', url: `${cardanoLibrary}/cardanoSerialization/bundle.js` },
            { name: 'bip39', url: bip39Library }
        ];

        console.log(`UtxoAddresses [${new Date().toISOString()}]: Scripts array:`, scripts);

        try {
            const loadResults = await Promise.all(
                scripts.map(async script => {
                    console.log(`UtxoAddresses [${new Date().toISOString()}]: Initiating load for ${script.name}`, script);
                    const result = await loadScript(this, script.url)
                        .then(() => {
                            console.log(`UtxoAddresses [${new Date().toISOString()}]: ${script.name} loaded successfully`);
                            return { name: script.name, loaded: true, url: script.url };
                        })
                        .catch(error => {
                            console.error(`UtxoAddresses [${new Date().toISOString()}]: Error loading ${script.name}`, error);
                            return { name: script.name, loaded: false, url: script.url, error };
                        });
                    return result;
                })
            );

            console.log(`UtxoAddresses [${new Date().toISOString()}]: loadResults:`, loadResults);

            const failed = loadResults.filter(r => !r.loaded);
            if (failed.length) {
                console.error(`UtxoAddresses [${new Date().toISOString()}]: Some libraries failed to load`, failed);
                throw new Error('Failed to load: ' + failed.map(f => f.name).join(', '));
            }

            console.log(`UtxoAddresses [${new Date().toISOString()}]: All libraries loaded, verifying window objects`);
            console.log(`window.cardanoSerialization:`, typeof window.cardanoSerialization, window.cardanoSerialization);
            console.log(`window.bip39:`, typeof window.bip39, window.bip39);

            if (!window.cardanoSerialization || !window.bip39) {
                throw new Error('Required libraries (cardanoSerialization or bip39) not properly initialized');
            }

            this.isLibraryLoaded = true;
        } catch (error) {
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Unexpected error in loadLibraries`, error);
            this.error = 'Library loading failed: ' + (error.message || error);
            this.showToast('Error', this.error, 'error');
            setTimeout(() => this.loadLibraries(), 2000);
        }
    }

    @wire(getUserPermissions)
    wiredPermissions({ error, data }) {
        if (data) {
            this.hasSeedPhrasePermission = data.includes('Ada_Wallet_Seed_Phrase');
            console.log(`UtxoAddresses [${new Date().toISOString()}]: User has Ada_Wallet_Seed_Phrase permission (wired): ${this.hasSeedPhrasePermission}`);
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Permissions received: ${JSON.stringify(data)}`);
            this.dummyState = !this.dummyState;
        } else if (error) {
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Error fetching permissions:`, error);
            this.hasSeedPhrasePermission = false;
            this.dummyState = !this.dummyState;
        }
    }

    @wire(getUTXOAddresses, { walletId: '$recordId' })
    wiredAddresses(result) {
        this.wiredAddressesResult = result; // Store the result for refreshing
        this.isLoading = true;
        const { error, data } = result;
        if (data) {
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Data loaded: ${data.length} records`);
            const addresses = data.map(addr => ({
                ...addr,
                recordLink: `/lightning/r/UTXO_Address__c/${addr.Id}/view`,
                cardanoScanLink: `https://cardanoscan.io/address/${addr.Address__c}`,
                truncatedAddress: this.truncateText(addr.Address__c, 40, 20, 10),
                truncatedStakingKeyHash: this.truncateText(addr.Staking_Key_Hash__c, 40, 20, 10)
            }));
            this.externalAddresses = addresses.filter(addr => addr.Type__c === '0');
            this.internalAddresses = addresses.filter(addr => addr.Type__c === '1');
            console.log(`UtxoAddresses [${new Date().toISOString()}]: All External addresses: ${this.externalAddresses.length}`);
            console.log(`UtxoAddresses [${new Date().toISOString()}]: All Internal addresses: ${this.internalAddresses.length}`);
            this.displayedExternalAddresses = this.externalAddresses.slice(0, this.displayLimit);
            this.displayedInternalAddresses = this.internalAddresses.slice(0, this.displayLimit);
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Displayed External addresses: ${this.displayedExternalAddresses.length}`);
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Displayed Internal addresses: ${this.displayedInternalAddresses.length}`);
            this.updateTabState(this.activeTab);
            this.error = undefined;
            // After initial load, check and derive addresses if needed
            this.ensureUTXOAddresses();
        } else if (error) {
            this.error = error.body?.message || 'Unknown error';
            this.externalAddresses = [];
            this.internalAddresses = [];
            this.displayedExternalAddresses = [];
            this.displayedInternalAddresses = [];
            this.currentTabCount = 0;
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Error loading addresses: ${this.error}`);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error Loading Addresses',
                    message: this.error,
                    variant: 'error'
                })
            );
        }
        this.isLoading = false;
    }

    async ensureUTXOAddresses() {
        if (!this.isLibraryLoaded) {
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Libraries not loaded, cannot ensure UTXO addresses`);
            return;
        }

        try {
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Ensuring UTXO addresses for Wallet__c ID: ${this.recordId}`);

            // Fetch wallet details to get Wallet_Set__c and Account_Index__c
            const wallet = await getWalletById({ walletId: this.recordId });
            if (!wallet || !wallet.Wallet_Set__c || wallet.Account_Index__c == null) {
                throw new Error('Invalid wallet data: Missing Wallet Set or Account Index');
            }

            // Fetch Wallet Set to get the mnemonic
            const walletSet = await getWalletSetById({ walletSetId: wallet.Wallet_Set__c });
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
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Refreshing UTXO addresses after ensuring consecutive unused`);
            await refreshApex(this.wiredAddressesResult);
        } catch (error) {
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Error in ensureUTXOAddresses:`, error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error Ensuring UTXO Addresses',
                    message: error.message || 'Unknown error',
                    variant: 'error'
                })
            );
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
    
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Checking existing ${typeLabel} addresses for 20 consecutive unused, maxIndex: ${maxIndex}`);
    
        // First, check existing addresses for consecutive unused sequence
        if (sortedAddresses.length > 0) {
            for (let i = 0; i <= maxIndex; i++) {
                const addr = sortedAddresses.find(a => parseInt(a.Index__c, 10) === i);
                if (!addr) {
                    // If the address doesn't exist at this index, treat it as unused
                    consecutiveUnused++;
                    console.log(`UtxoAddresses [${new Date().toISOString()}]: Index ${i} missing for ${typeLabel}, treating as unused, consecutiveUnused: ${consecutiveUnused}`);
                } else {
                    let isUsed;
                    try {
                        isUsed = await isAddressUsed({ address: addr.Address__c });
                    } catch (error) {
                        throw new Error(`Failed to check address usage for ${typeLabel} address at index ${i}: ${error.body?.message || error.message}`);
                    }
    
                    if (isUsed) {
                        consecutiveUnused = 0;
                        console.log(`UtxoAddresses [${new Date().toISOString()}]: Index ${i} for ${typeLabel} is used, resetting consecutiveUnused to 0`);
                    } else {
                        consecutiveUnused++;
                        console.log(`UtxoAddresses [${new Date().toISOString()}]: Index ${i} for ${typeLabel} is unused, consecutiveUnused: ${consecutiveUnused}`);
                    }
                }
    
                if (consecutiveUnused >= 20) {
                    console.log(`UtxoAddresses [${new Date().toISOString()}]: Found 20 consecutive unused ${typeLabel} addresses in existing set, stopping derivation`);
                    return;
                }
            }
        }
    
        // If we don't have 20 consecutive unused addresses, start deriving from the next index
        currentIndex = maxIndex + 1 >= 0 ? maxIndex + 1 : 0;
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Less than 20 consecutive unused ${typeLabel} addresses found, starting derivation from index ${currentIndex}`);
    
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
                isUsed = await isAddressUsed({ address: bech32Address });
            } catch (error) {
                throw new Error(`Failed to check address usage for ${typeLabel} address at index ${currentIndex}: ${error.body?.message || error.message}`);
            }
    
            if (isUsed) {
                consecutiveUnused = 0;
                console.log(`UtxoAddresses [${new Date().toISOString()}]: Derived ${typeLabel} address at index ${currentIndex} is used, resetting consecutiveUnused to 0`);
            } else {
                consecutiveUnused++;
                console.log(`UtxoAddresses [${new Date().toISOString()}]: Derived ${typeLabel} address at index ${currentIndex} is unused, consecutiveUnused: ${consecutiveUnused}`);
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
                console.log(`UtxoAddresses [${new Date().toISOString()}]: Added ${typeLabel} address at index ${currentIndex}: ${bech32Address}`);
            } catch (error) {
                console.error(`UtxoAddresses [${new Date().toISOString()}]: Failed to save ${typeLabel} address at index ${currentIndex}:`, error);
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
        console.log(`UtxoAddresses [${new Date().toISOString()}]: External tab activated`);
        this.activeTab = 'external';
        this.updateTabState('external');
        this.applyFilter();
    }

    handleInternalTabActive() {
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Internal tab activated`);
        this.activeTab = 'internal';
        this.updateTabState('internal');
        this.applyFilter();
    }

    updateTabState(tab) {
        try {
            if (tab === 'external') {
                this.currentTabLabel = 'External';
                this.currentTabCount = this.externalAddresses.length; // Use full list for count
            } else if (tab === 'internal') {
                this.currentTabLabel = 'Internal';
                this.currentTabCount = this.internalAddresses.length; // Use full list for count
            }
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Updated state - activeTab: ${this.activeTab}, label: ${this.currentTabLabel}, count: ${this.currentTabCount}`);
            this.dummyState = !this.dummyState;
        } catch (err) {
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Error in updateTabState:`, err);
        }
    }

    handleFilterChange(event) {
        this.filterText = event.target.value.toLowerCase();
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Filter text updated: ${this.filterText}`);
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

        console.log(`UtxoAddresses [${new Date().toISOString()}]: Filtered - External addresses (limited to ${this.displayLimit}): ${this.displayedExternalAddresses.length}`);
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Filtered - Internal addresses (limited to ${this.displayLimit}): ${this.displayedInternalAddresses.length}`);
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
        console.log(`UtxoAddresses [${new Date().toISOString()}]: generateAddress - Method invoked`);
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Wallet__c ID (recordId): ${this.recordId}`);
        console.log(`UtxoAddresses [${new Date().toISOString()}]: hasSeedPhrasePermission: ${this.hasSeedPhrasePermission}`);

        // Validate recordId
        if (!this.recordId || !/^[a-zA-Z0-9]{15,18}$/.test(this.recordId)) {
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Invalid or missing recordId: ${this.recordId}`);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Invalid Wallet ID. Please ensure you are on a valid Wallet record.',
                    variant: 'error'
                })
            );
            return;
        }

        // Validate library loading
        if (!this.isLibraryLoaded) {
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Cardano Serialization Library not loaded`);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Cardano Serialization Library not loaded. Please try again.',
                    variant: 'error'
                })
            );
            return;
        }

        this.isLoading = true;
        try {
            const CardanoWasm = window.cardanoSerialization;

            // Determine the type based on the active tab
            const type = this.activeTab === 'external' ? '0' : '1'; // '0' for receiving (External), '1' for change (Internal)
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Generating address with Type: ${type} (Active Tab: ${this.activeTab})`);

            // Get the next index for the specified type
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Fetching next index for Wallet__c ID: ${this.recordId}, Type: ${type}`);
            const nextIndex = await getNextUTXOIndex({ walletId: this.recordId, type: type });
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Apex call successful, nextIndex received: ${nextIndex}`);

            // Fetch Wallet__c record to get the encrypted Account_Private_Key__c
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Fetching Wallet__c record for ID: ${this.recordId}`);
            const wallet = await getWalletById({ walletId: this.recordId });
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Wallet__c record retrieved:`, JSON.stringify(wallet, null, 2));

            if (!wallet || !wallet.Account_Private_Key__c) {
                throw new Error('Wallet record or Account Private Key not found');
            }

            // Decrypt the Account_Private_Key__c
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Decrypting Account_Private_Key__c`);
            const accountPrivateKeyBech32 = await decrypt({ encryptedText: wallet.Account_Private_Key__c });
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Account Private Key decrypted (Bech32 format, masked for security)`);

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

            // Print only the new UTXO address
            console.log(`UtxoAddresses [${new Date().toISOString()}]: New UTXO Address for Index ${nextIndex} (Type: ${type}): ${bech32Address}`);

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
            console.log(`UtxoAddresses [${new Date().toISOString()}]: Refreshing UTXO addresses after generating new address`);
            await refreshApex(this.wiredAddressesResult);

            // Show a toast notification with the new address
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'New UTXO Address Generated',
                    message: `New ${type === '0' ? 'receiving' : 'change'} address for index ${nextIndex}: ${bech32Address}`,
                    variant: 'success'
                })
            );
        } catch (error) {
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Error in generateAddress:`, error);
            console.error(`UtxoAddresses [${new Date().toISOString()}]: Error details:`, JSON.stringify(error, null, 2));
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error Generating Address',
                    message: error.message || 'Unknown error',
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
            console.log(`UtxoAddresses [${new Date().toISOString()}]: generateAddress - Completed, isLoading: ${this.isLoading}`);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    renderedCallback() {
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Rendered, hasSeedPhrasePermission: ${this.hasSeedPhrasePermission}`);
        console.log(`UtxoAddresses [${new Date().toISOString()}]: Current tab state - activeTab: ${this.activeTab}, label: ${this.currentTabLabel}, count: ${this.currentTabCount}`);
    }
}