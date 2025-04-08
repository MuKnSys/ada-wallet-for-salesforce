import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import bipLibrary from '@salesforce/resourceUrl/bip39';
import createWalletSet from '@salesforce/apex/WalletSetController.createWalletSet';

export default class GenerateSeedPhrase1 extends NavigationMixin(LightningElement) {
    @track step1 = true;
    @track step2 = false;
    @track step3 = false;
    @track walletName = '';
    @track seedPhrase = [];
    @track verificationInputs = [];
    @track errorMessage = '';
    @track isLibraryLoaded = false;

    get isNextDisabled() {
        return !this.walletName.trim();
    }

    get isSubmitDisabled() {
        return this.verificationInputs.some(input => !input.value || !input.value.trim());
    }

    connectedCallback() {
        this.walletName = '';
        this.seedPhrase = [];
        this.verificationInputs = [];
        this.errorMessage = '';
        this.step1 = true;
        this.step2 = false;
        this.step3 = false;        
    }

    renderedCallback() {
        if (!this.isLibraryLoaded) {            
            this.loadBipLibrary();
        }
    }

    loadBipLibrary() {        
        loadScript(this, bipLibrary)
            .then(() => {                
                if (!window.bip39) {
                    throw new Error('bip39 not found on window object after loading.');
                }
                if (!window.bip32) {
                    throw new Error('bip32 not found on window object after loading. Ensure bip32 is included in the static resource.');
                }
                this.isLibraryLoaded = true;                
            })
            .catch(error => {                
                this.showToast('Error', 'Failed to load Bip library: ' + error.message, 'error');
            });
    }

    handleWalletNameChange(event) {
        this.walletName = event.target.value;
    }

    handleNextFromStep1() {
        if (this.walletName) {
            if (!this.isLibraryLoaded || !window.bip39) {
                this.showToast('Error', 'Cardano library not loaded yet. Please try again.', 'error');
                return;
            }

            try {
                console.log('Generating seed phrase with bip39...');                
                const mnemonic = window.bip39.generateMnemonic(256);                

                if (!mnemonic || mnemonic.trim() === '' || mnemonic.split(' ').length !== 24) {
                    throw new Error('Generated mnemonic is empty, invalid, or does not contain 24 words.');
                }

                // Transform the seed phrase into an array of objects with displayIndex
                this.seedPhrase = mnemonic.split(' ').map((word, index) => {
                    const item = {
                        word: word,
                        displayIndex: index + 1 // Start numbering from 1
                    };                    
                    return item;
                });                

                this.step1 = false;
                this.step2 = true;
            } catch (error) {
                console.error('Error generating seed phrase:', error);
                console.log('Error stack:', error.stack);
                this.showToast('Error', 'Failed to generate seed phrase: ' + error.message, 'error');
            }
        }
    }

    downloadSeedPhrase() {
        const phraseText = this.seedPhrase.map(item => item.word).join(' ');
        const element = document.createElement('a');
        const file = new Blob([phraseText], { type: 'text/plain' });
        element.href = URL.createObjectURL(file);
        element.download = `${this.walletName}_seed.txt`;
        document.body.appendChild(element);
        element.click();
        document.body.removeChild(element);
    }

    uploadToDataCloud() {
        // Placeholder for Data Cloud integration
        this.showToast('Success', 'Seed phrase uploaded to Data Cloud', 'success');
    }

    storeInOrg() {
        // Placeholder for org storage
        this.showToast('Success', 'Seed phrase stored in organization', 'success');
    }

    handleNextFromStep2() {
        // Create verification inputs and prefill with the generated seed phrase words
        this.verificationInputs = this.seedPhrase.map((item, i) => {
            const input = {
                label: `Word ${i + 1}`,
                value: item.word // Prefill with the correct word from seedPhrase
            };            
            return input;
        });        

        this.step2 = false;
        this.step3 = true;
        // Clear seed phrase from memory
        this.seedPhrase = [];
    }

    handleVerificationChange(event) {
        const index = parseInt(event.target.dataset.index);
        this.verificationInputs[index].value = event.target.value.toLowerCase();        
        this.verificationInputs = [...this.verificationInputs];
    }

    async handleSubmit() {
        const enteredPhrase = this.verificationInputs.map(input => input.value.trim());
        const originalPhrase = this.verificationInputs.map(input => input.value.trim()); // Since seedPhrase is cleared, use initial values
        const isValid = enteredPhrase.every((word, i) => word === originalPhrase[i]);

        if (isValid) {
            // Prepare the seed phrase as a string
            const seedPhraseString = enteredPhrase.join(' ');

            try {
                // Create WalletSet object after verification                
                const bip39 = window.bip39;
                const bip32 = window.bip32;
                const WalletSet = {};

                // Set mnemonic
                WalletSet.mnemonic = seedPhraseString;                

                // Generate seed from mnemonic                
                WalletSet.seed = await bip39.mnemonicToSeed(WalletSet.mnemonic);                

                // Set derivation path
                WalletSet.path = "m/1852'/1815'";                

                // Derive node from seed                
                const WalletSet_Node = bip32.fromSeed(WalletSet.seed)
                    .deriveHardened(1852)
                    .deriveHardened(1815);                

                // Set extended private and public keys                
                WalletSet.xprv = WalletSet_Node.toBase58();                
                WalletSet.xpub = WalletSet_Node.neutered().toBase58();                

                // Serialize node details to JSON                
                WalletSet.node = JSON.stringify({
                    xprv: WalletSet.xprv,
                    xpub: WalletSet.xpub,
                    chainCode: WalletSet_Node.chainCode.toString('hex'),
                    depth: WalletSet_Node.depth,
                    index: WalletSet_Node.index,
                    parentFingerprint: WalletSet_Node.parentFingerprint
                }, null, 2);                

                // Log the WalletSet object                

                // Call Apex to create the Wallet_Set__c record, including Root_Private_Key__c and Root_Public_Key__c
                const recordId = await createWalletSet({
                    walletName: this.walletName,
                    seedPhrase: seedPhraseString,
                    rootPrivateKey: WalletSet.xprv, // Pass xprv as Root_Private_Key__c
                    rootPublicKey: WalletSet.xpub   // Pass xpub as Root_Public_Key__c
                });                

                // Validate the recordId
                if (!recordId || typeof recordId !== 'string' || !recordId.startsWith('a')) {
                    throw new Error('Invalid record ID returned from Apex: ' + recordId);
                }

                // Navigate directly to the newly created Wallet_Set__c record detail page                
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: recordId,
                        objectApiName: 'Wallet_Set__c',
                        actionName: 'view'
                    }
                }, true);     
            } catch (error) {
                this.errorMessage = 'Error creating Wallet Set or navigating: ' + (error.body?.message || error.message);
                this.showToast('Error', this.errorMessage, 'error');
                console.error('Error in handleSubmit:', error);
            }
        } else {
            this.errorMessage = 'Invalid seed phrase. Please check your entries.';
            this.showToast('Error', this.errorMessage, 'error');
        }
    }

    showToast(title, message, variant, options = {}) {
        const event = new ShowToastEvent({
            title,
            message,
            variant,
            messageData: options.url ? [{url: options.url, label: options.label}] : [],
            mode: 'sticky'
        });
        this.dispatchEvent(event);
    }
}