import GetUTXOAddressAssets_SyncButton from '@salesforce/label/c.GetUTXOAddressAssets_SyncButton';
import GetUTXOAddressAssets_LoadingText from '@salesforce/label/c.GetUTXOAddressAssets_LoadingText';
import GetUTXOAddressAssets_SuccessMessage from '@salesforce/label/c.GetUTXOAddressAssets_SuccessMessage';
import GetUTXOAddressAssets_ErrorPrefix from '@salesforce/label/c.GetUTXOAddressAssets_ErrorPrefix';
import GetUTXOAddressAssets_DefaultError from '@salesforce/label/c.GetUTXOAddressAssets_DefaultError';
import GetUTXOAddressAssets_UnknownError from '@salesforce/label/c.GetUTXOAddressAssets_UnknownError';
import GetUTXOAddressAssets_CardTitle from '@salesforce/label/c.GetUTXOAddressAssets_CardTitle';

export const labels = {
    SYNC: {
        Button: GetUTXOAddressAssets_SyncButton,
        LoadingText: GetUTXOAddressAssets_LoadingText,
        SuccessMessage: GetUTXOAddressAssets_SuccessMessage
    },
    ERROR: {
        Prefix: GetUTXOAddressAssets_ErrorPrefix,
        Default: GetUTXOAddressAssets_DefaultError,
        Unknown: GetUTXOAddressAssets_UnknownError
    },
    UI: {
        CardTitle: GetUTXOAddressAssets_CardTitle
    }
}; 