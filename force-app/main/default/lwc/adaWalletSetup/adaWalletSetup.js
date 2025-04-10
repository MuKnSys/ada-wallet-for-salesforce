import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import { labels } from './labels';
import { TOAST_VARIANT, TOAST_MODE, STEPS } from 'c/constants';

import getSetup from '@salesforce/apex/AdaWalletsSetupCtrl.getSetup';
import generatePrivateKey from '@salesforce/apex/AdaWalletsSetupCtrl.generatePrivateKey';
import enableLogging from '@salesforce/apex/AdaWalletsSetupCtrl.enableLogging';
import disableLogging from '@salesforce/apex/AdaWalletsSetupCtrl.disableLogging';

export default class AdaWalletSetup extends LightningElement {
    isLoading = true;
    labels = labels;
    steps = STEPS;

    @track
    setupData = {};

    get privateKeyCompleted() {
        return !this.isBlank(this.setupData, 'privateKey');
    }

    isBlank(object, value) {
        return !(value in object && object[value] !== undefined && object[value] !== null && object[value] !== '');
    }

    async loadSetup() {
        const result = await getSetup();
        this.processSetupData(result);
    }

    processSetupData(value) {
        Object.assign(this.setupData, value);
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await this.loadSetup();
        } catch (error) {
            const erroMessage = error.body ? error.body.message : error.message;
            this.showToast(erroMessage);
        } finally {
            this.isLoading = false;
        }
    }

    async handlePrivateKey() {
        this.isLoading = true;
        try {
            const result = await generatePrivateKey();
            this.processSetupData(result);

            this.showToast(this.labels.CORE.Success, this.labels.CORE.Success_Info, TOAST_VARIANT.SUCCESS, TOAST_MODE.SUCCESS);
        } catch (error) {
            const erroMessage = error.body ? error.body.message : error.message;
            this.showToast(erroMessage);
        } finally {
            this.isLoading = false;
        }
    }

    async handleEnableLogging() {
        this.isLoading = true;
        try {
            await enableLogging();
            this.showToast(
                this.labels.LOGGING.SetupSuccess,
                this.labels.LOGGING.EnableSuccess,
                TOAST_VARIANT.SUCCESS,
                TOAST_MODE.SUCCESS
            );
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            showToast(this, 'Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDisableLogging() {
        this.isLoading = true;
        try {
            await disableLogging();
            this.showToast(
                this.labels.LOGGING.SetupSuccess,
                this.labels.LOGGING.DisableSuccess,
                TOAST_VARIANT.SUCCESS,
                TOAST_MODE.SUCCESS
            );
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            showToast(this, 'Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    async connectedCallback() {
        try {
            await this.loadSetup();
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            this.showToast(errorMessage);
        } finally {
            this.isLoading = false;
        }
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
