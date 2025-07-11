import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';

import bipLibrary from '@salesforce/resourceUrl/bip39';
import createWalletSet from '@salesforce/apex/WalletSetCtrl.createWalletSet';

import { labels } from './labels';

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
    @track wordCountOptions = [];
    @track bip39WordList = [];
    @track suggestions = [];
    @track activeInputIndex = -1;
    @track activeVerificationInputIndex = -1;

    labels = labels;

    get isNextDisabled() {
        return !this.walletName.trim();
    }

    get isSubmitDisabled() {
        return this.verificationInputs.some(input => !input.value || !input.value.trim());
    }

    get isImportDisabled() {
        return this.importInputs.some(input => !input.value || !input.value.trim());
    }

    get showSuggestions() {
        return this.suggestions.length > 0 && this.activeInputIndex >= 0;
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
        this.bip39WordList = [];
        this.suggestions = [];
        this.activeInputIndex = -1;
        this.activeVerificationInputIndex = -1;
        
        // Initialize word count options
        this.wordCountOptions = [
            { label: this.labels.WORD_COUNT.Option15, value: '15' },
            { label: this.labels.WORD_COUNT.Option24, value: '24' }
        ];
        
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
                
                // Store BIP39 word list for autocomplete
                this.bip39WordList = window.bip39.wordlists.english;
                
            })
            .catch(error => {                
                this.showToast('Error', this.labels.ERROR.BipLibrary + ' ' + error.message, 'error');
            });
    }

    handleCreateNew() {
        this.isCreatingNew = true;
        this.step0 = false;
        this.step1 = true;
    }

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
                if (!this.isLibraryLoaded || !window.bip39) {
                    this.showToast('Error', this.labels.ERROR.Library, 'error');
                    return;
                }

                try {
                    const mnemonic = window.bip39.generateMnemonic(256);

                    if (!mnemonic || mnemonic.trim() === '' || mnemonic.split(' ').length !== 24) {
                        throw new Error('Generated mnemonic is empty, invalid, or does not contain 24 words.');
                    }

                    this.seedPhrase = mnemonic.split(' ').map((word, index) => {
                        const item = {
                            word: word,
                            displayIndex: index + 1
                        };
                        return item;
                    });

                    this.originalSeedPhrase = mnemonic.split(' ');

                    this.step1 = false;
                    this.step2 = true;
                } catch (error) {
                    this.showToast('Error', this.labels.ERROR.Generate + ' ' + error.message, 'error');
                }
            } else {
                this.step1 = false;
                this.step3Import = true;
                this.initializeImportInputs();
            }
        }
    }

    handleWordCountChange(event) {
        this.selectedWordCount = event.detail.value;
        this.initializeImportInputs();
    }

    initializeImportInputs() {
        const wordCount = parseInt(this.selectedWordCount);
        this.importInputs = Array.from({ length: wordCount }, (_, i) => ({
            label: `${this.labels.UI.WordLabel} ${i + 1}`,
            value: ''
        }));
        this.suggestions = [];
        this.activeInputIndex = -1;
    }

    handleImportInputChange(event) {
        const index = parseInt(event.target.dataset.index);
        const value = event.target.value.toLowerCase().trim();
        
        this.importInputs[index].value = value;
        this.importInputs = [...this.importInputs];
        this.activeInputIndex = index;
        
        // Generate suggestions based on input
        if (value.length > 0 && this.bip39WordList.length > 0) {
            this.suggestions = this.bip39WordList.filter(word => 
                word.toLowerCase().startsWith(value)
            ).slice(0, 5); // Limit to 5 suggestions
            this.importInputs.forEach((input, i) => input.showSuggestions = (i === index));
        } else {
            this.suggestions = [];
            this.importInputs.forEach(input => input.showSuggestions = false);
        }
    }

    // Method to handle suggestion selection
    handleSuggestionClick(event) {
        const selectedWord = event.currentTarget.dataset.word;
        const index = this.activeInputIndex;
        
        if (index >= 0 && index < this.importInputs.length) {
            this.importInputs[index].value = selectedWord;
            this.importInputs = [...this.importInputs];
            this.suggestions = [];
            this.importInputs.forEach(input => input.showSuggestions = false);
            this.activeInputIndex = -1;
            
            // Focus on next input if available
            if (index < this.importInputs.length - 1) {
                this.focusNextInput(index + 1);
            }
        }
    }

    // Method to focus on next input
    focusNextInput(index) {
        setTimeout(() => {
            const nextInput = this.template.querySelector(`[data-index="${index}"]`);
            if (nextInput) {
                nextInput.focus();
            }
        }, 100);
    }

    // Method to handle input focus
    handleInputFocus(event) {
        const index = parseInt(event.target.dataset.index);
        this.activeInputIndex = index;
        
        // Show suggestions if there's a value
        const value = this.importInputs[index].value.toLowerCase().trim();
        if (value.length > 0 && this.bip39WordList.length > 0) {
            this.suggestions = this.bip39WordList.filter(word => 
                word.toLowerCase().startsWith(value)
            ).slice(0, 5);
            this.importInputs.forEach((input, i) => input.showSuggestions = (i === index));
        } else {
            this.suggestions = [];
            this.importInputs.forEach(input => input.showSuggestions = false);
        }
    }

    // Method to handle input blur
    handleInputBlur() {
        // Delay hiding suggestions to allow for clicks
        setTimeout(() => {
            this.suggestions = [];
            this.importInputs.forEach(input => input.showSuggestions = false);
            this.activeInputIndex = -1;
        }, 200);
    }

    async handleImportSubmit() {
        try {
            const enteredWords = this.importInputs
                .map(input => input.value.trim())
                .filter(word => word !== '');

            const expectedLength = parseInt(this.selectedWordCount);
            if (enteredWords.length !== expectedLength) {
                this.errorMessage = `${this.labels.ERROR.WordCount} ${expectedLength} words.`;
                this.showToast('Error', this.errorMessage, 'error');
                return;
            }

            await this.processImport(enteredWords);
        } catch (error) {
            this.errorMessage = this.labels.ERROR.Import + ' ' + (error.body?.message || error.message);
            this.showToast('Error', this.errorMessage, 'error');
        }
    }

    async processImport(enteredWords) {
        const seedPhraseString = enteredWords.join(' ');
        if (!window.bip39.validateMnemonic(seedPhraseString)) {
            this.showToast('Error', this.labels.ERROR.Invalid, 'error');
            return;
        }
        
        this.isLoading = true;

        try {
            const recordId = await createWalletSet({
                walletName: this.walletName,
                seedPhrase: seedPhraseString
            });            

            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    objectApiName: 'Wallet_Set__c',
                    actionName: 'view'
                }
            }, true);
            this.showToast('Success', this.labels.SUCCESS.Import, 'success');

        } catch (error) {
            this.errorMessage = this.labels.ERROR.Import + ' ' + (error.body?.message || error.message || 'Unknown error');
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
                label: `${this.labels.UI.WordLabel} ${i + 1}`,
                value: ''
            };
        });

        this.step2 = false;
        this.step3 = true;
        this.seedPhrase = [];
    }

    handleVerificationChange(event) {
        const index = parseInt(event.target.dataset.index);
        const value = event.target.value.toLowerCase().trim();
        this.verificationInputs[index].value = value;
        this.verificationInputs = [...this.verificationInputs];
        this.activeVerificationInputIndex = index;
        // Generate suggestions based on input
        if (value.length > 0 && this.bip39WordList.length > 0) {
            this.suggestions = this.bip39WordList.filter(word => 
                word.toLowerCase().startsWith(value)
            ).slice(0, 5);
            this.verificationInputs.forEach((input, i) => input.showSuggestions = (i === index));
        } else {
            this.suggestions = [];
            this.verificationInputs.forEach(input => input.showSuggestions = false);
        }
    }

    handleVerificationSuggestionClick(event) {
        const selectedWord = event.currentTarget.dataset.word;
        const index = this.activeVerificationInputIndex;
        if (index >= 0 && index < this.verificationInputs.length) {
            this.verificationInputs[index].value = selectedWord;
            this.verificationInputs = [...this.verificationInputs];
            this.suggestions = [];
            this.verificationInputs.forEach(input => input.showSuggestions = false);
            this.activeVerificationInputIndex = -1;
            if (index < this.verificationInputs.length - 1) {
                this.focusNextVerificationInput(index + 1);
            }
        }
    }

    focusNextVerificationInput(index) {
        setTimeout(() => {
            const nextInput = this.template.querySelector(`[data-verif-index="${index}"]`);
            if (nextInput) {
                nextInput.focus();
            }
        }, 100);
    }

    handleVerificationInputFocus(event) {
        const index = parseInt(event.target.dataset.verifIndex);
        this.activeVerificationInputIndex = index;
        const value = this.verificationInputs[index].value.toLowerCase().trim();
        if (value.length > 0 && this.bip39WordList.length > 0) {
            this.suggestions = this.bip39WordList.filter(word => 
                word.toLowerCase().startsWith(value)
            ).slice(0, 5);
            this.verificationInputs.forEach((input, i) => input.showSuggestions = (i === index));
        } else {
            this.suggestions = [];
            this.verificationInputs.forEach(input => input.showSuggestions = false);
        }
    }

    handleVerificationInputBlur() {
        setTimeout(() => {
            this.suggestions = [];
            this.verificationInputs.forEach(input => input.showSuggestions = false);
            this.activeVerificationInputIndex = -1;
        }, 200);
    }

    async handleSubmit() {
        const enteredPhrase = this.verificationInputs.map(input => input.value.trim());
        const originalPhrase = this.originalSeedPhrase;
        const isValid = enteredPhrase.every((word, i) => word === originalPhrase[i]);

        if (isValid) {
            const seedPhraseString = enteredPhrase.join(' ');

            try {
                this.isLoading = true;
                const WalletSet = {};

                WalletSet.mnemonic = seedPhraseString;

                const recordId = await createWalletSet({
                    walletName: this.walletName,
                    seedPhrase: seedPhraseString
                });

                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: recordId,
                        objectApiName: 'Wallet_Set__c',
                        actionName: 'view'
                    }
                }, true);
                this.showToast('Success', this.labels.SUCCESS.Create, 'success');
            } catch (error) {
                this.errorMessage = this.labels.ERROR.Create + ' ' + (error.body?.message || error.message);
                this.showToast('Error', this.errorMessage, 'error');
            } finally {
                this.isLoading = false;
            }
        } else {
            this.errorMessage = this.labels.ERROR.Verification;
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