// showWalletKeys.js
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { TOAST_VARIANT, TOAST_MODE } from 'c/constants';
import getWalletKeys from '@salesforce/apex/ShowWalletKeysCtrl.getWalletKeys';

export default class ShowWalletKeys extends LightningElement {
    _recordId;
    @track privateKey = '';
    @track publicKey  = '';

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
    }

    showWalletKeys() {
        getWalletKeys({ walletId: this.recordId })
            .then(result => {
                this.privateKey = result.privateKey;
                this.publicKey  = result.publicKey;
            })
            .catch(error => {
                const msg = error.body?.message || error.message;
                this.showToast('Error loading keys', msg, TOAST_VARIANT.ERROR, TOAST_MODE.DISMISSIBLE);
            });
    }

    clearWalletKeys() {
        this.privateKey = '';
        this.publicKey  = '';
    }

    showToast(title, message, variant = TOAST_VARIANT.ERROR, mode = TOAST_MODE.DISMISSIBLE) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant, mode })
        );
    }
}
