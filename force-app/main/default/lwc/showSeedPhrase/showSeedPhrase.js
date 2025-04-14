import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { TOAST_VARIANT, TOAST_MODE } from 'c/constants';
import getSeedPhrase from '@salesforce/apex/ShowSeedPhraseCtrl.getSeedPhrase';

export default class ShowSeedPhrase extends LightningElement {
    _recordId;
    @track seedPhrase = '';
    @track cardanoPrivateKey = '';

    @api
    get recordId() {
        return this._recordId;
    }
    
    set recordId(value) {            
        this._recordId = value;
    }
    
    showSeedPhrase() {
        getSeedPhrase({ walletSetId: this.recordId })
            .then(result => {
                this.seedPhrase = result;
            })
            .catch(error => {
                const erroMessage = error.body ? error.body.message : error.message;
                this.showToast(erroMessage);
            });
    }
    
    clearSeedPhrase() {
        this.seedPhrase = '';
    }

    showToast(title, message, type = TOAST_VARIANT.ERROR, mode = TOAST_MODE.ERROR) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: type,
                mode: mode
            })
        );
    }
}
