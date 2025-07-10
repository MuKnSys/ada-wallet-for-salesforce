import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';

import bipLibrary from '@salesforce/resourceUrl/bip39';

import createWalletSet from '@salesforce/apex/WalletSetCtrl.createWalletSet';

export default class GenerateSeedPhrase extends NavigationMixin(LightningElement) {
    @track step0 = true;
    @track step1 = false;
    @track step2 = false;
    @track step3Import = false;
    @track step3 = false;
    @track walletName = '';
    @track seedPhrase = [];
    @track importInputs = [];
    @track verificationInputs = [];
    @track errorMessage = '';
    @track isLibraryLoaded = false;
    @track isLoading = false;
    @track originalSeedPhrase = [];
    @track isCreatingNew = false;
    @track selectedWordCount = '24';
    @track wordCountOptions = [
        { label: '15 Words', value: '15' },
        { label: '24 Words', value: '24' }
    ];

    get isNextDisabled() {
        return !this.walletName.trim();
    }

    get isSubmitDisabled() {
        return this.verificationInputs.some(input => !input.value || !input.value.trim());
    }

    get isImportDisabled() {
        return this.importInputs.some(input => !input.value || !input.value.trim());
    }

    connectedCallback() {
        this.walletName = '';
        this.seedPhrase = [];
        this.importInputs = [];
        this.verificationInputs = [];
        this.originalSeedPhrase = [];
        this.errorMessage = '';
        this.step0 = true;
        this.step1 = false;
        this.step2 = false;
        this.step3Import = false;
        this.step3 = false;
        this.isCreatingNew = false;
        this.selectedWordCount = '24';
        this.initializeImportInputs();
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

                this.isLibraryLoaded = true;                
            })
            .catch(error => {                
                this.showToast('Error', 'Failed to load Bip library: ' + error.message, 'error');
            });
    }

    // New method to handle "Create New Wallet Set" option
    handleCreateNew() {
        this.isCreatingNew = true;
        this.step0 = false;
        this.step1 = true;
    }

    // New method to handle "Import Existing Wallet Set" option
    handleImportExisting() {
        this.isCreatingNew = false;
        this.step0 = false;
        this.step1 = true;
    }



    handleWalletNameChange(event) {
        this.walletName = event.target.value;
    }

    handleNextFromStep1() {
        if (this.walletName) {
            if (this.isCreatingNew) {
                // Create new wallet flow
                if (!this.isLibraryLoaded || !window.bip39) {
                    this.showToast('Error', 'Cardano library not loaded yet. Please try again.', 'error');
                    return;
                }

                try {
                    // Generate a new 24-word mnemonic using bip39
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

                    // Store original seed phrase words for verification
                    this.originalSeedPhrase = mnemonic.split(' ');

                    this.step1 = false;
                    this.step2 = true;
                } catch (error) {
                    this.showToast('Error', 'Failed to generate seed phrase: ' + error.message, 'error');
                }
            } else {
                // Import existing wallet set flow
                this.step1 = false;
                this.step3Import = true;
                this.initializeImportInputs();
            }
        }
    }

    // Method to handle word count change
    handleWordCountChange(event) {
        this.selectedWordCount = event.detail.value;
        this.initializeImportInputs();
    }

    // Method to initialize import inputs based on selected word count
    initializeImportInputs() {
        const wordCount = parseInt(this.selectedWordCount);
        this.importInputs = Array.from({ length: wordCount }, (_, i) => ({
            label: `Word ${i + 1}`,
            value: ''
        }));
    }

    // Method to handle import input changes
    handleImportInputChange(event) {
        const index = parseInt(event.target.dataset.index);
        this.importInputs[index].value = event.target.value.toLowerCase().trim();
        this.importInputs = [...this.importInputs];
    }

    // Method to handle import submit
    async handleImportSubmit() {
        try {
            const enteredWords = this.importInputs
                .map(input => input.value.trim())
                .filter(word => word !== '');

            const expectedLength = parseInt(this.selectedWordCount);
            if (enteredWords.length !== expectedLength) {
                this.errorMessage = `Seed phrase must contain exactly ${expectedLength} words.`;
                this.showToast('Error', this.errorMessage, 'error');
                return;
            }

            await this.processImport(enteredWords);
        } catch (error) {
            this.errorMessage = 'Error importing Wallet Set: ' + (error.body?.message || error.message);
            this.showToast('Error', this.errorMessage, 'error');
        }
    }

    // Common method to process import
    async processImport(enteredWords) {
        const seedPhraseString = enteredWords.join(' ');
        if (!window.bip39.validateMnemonic(seedPhraseString)) {
            this.showToast('Error', 'Seed phrase is invalid', 'error');
            return;
        }
        
        this.isLoading = true;

        try {
            // Call Apex to create the Wallet_Set__c record
            const recordId = await createWalletSet({
                walletName: this.walletName,
                seedPhrase: seedPhraseString
            });            

            // Navigate directly to the newly created Wallet_Set__c record detail page                
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    objectApiName: 'Wallet_Set__c',
                    actionName: 'view'
                }
            }, true);
            this.showToast('Success', `Wallet Set imported successfully`, 'success');

        } catch (error) {
            this.errorMessage = 'Error importing Wallet Set: ' + (error.body?.message || error.message || 'Unknown error');
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
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

    handleNextFromStep2() {
        this.verificationInputs = this.seedPhrase.map((item, i) => {
            return {
                label: `Word ${i + 1}`,
                value: '' // Do not autofill; user must enter manually
            };
        });

        this.step2 = false;
        this.step3 = true;
        // Clear seed phrase from memory but keep originalSeedPhrase for verification
        this.seedPhrase = [];
    }

    handleVerificationChange(event) {
        const index = parseInt(event.target.dataset.index);
        this.verificationInputs[index].value = event.target.value.toLowerCase();        
        this.verificationInputs = [...this.verificationInputs];
    }

    async handleSubmit() {
        const enteredPhrase = this.verificationInputs.map(input => input.value.trim());
        const originalPhrase = this.originalSeedPhrase; // Use stored original phrase
        const isValid = enteredPhrase.every((word, i) => word === originalPhrase[i]);

        if (isValid) {
            // Prepare the seed phrase as a string
            const seedPhraseString = enteredPhrase.join(' ');

            try {
                this.isLoading = true;
                // Create WalletSet object after verification
                const WalletSet = {};

                // Set mnemonic
                WalletSet.mnemonic = seedPhraseString;

                // Call Apex to create the Wallet_Set__c record
                const recordId = await createWalletSet({
                    walletName: this.walletName,
                    seedPhrase: seedPhraseString
                });

                // Navigate directly to the newly created Wallet_Set__c record detail page                
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: recordId,
                        objectApiName: 'Wallet_Set__c',
                        actionName: 'view'
                    }
                }, true);
                this.showToast('Success', `Wallet Set created successfully`, 'success');
            } catch (error) {
                this.errorMessage = 'Error creating Wallet Set or navigating: ' + (error.body?.message || error.message);
                this.showToast('Error', this.errorMessage, 'error');
            } finally {
                this.isLoading = false;
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