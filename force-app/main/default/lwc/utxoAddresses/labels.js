import UTXO_ADDRESSES_TITLE from '@salesforce/label/c.UTXOAddresses_Title';
import UTXO_ADDRESSES_SUBTITLE from '@salesforce/label/c.UTXOAddresses_Subtitle';
import UTXO_ADDRESSES_UNUSED from '@salesforce/label/c.UTXOAddresses_Unused';
import UTXO_ADDRESSES_GENERATE_NEW_ADDRESS from '@salesforce/label/c.UTXOAddresses_GenerateNewAddress';
import UTXO_ADDRESSES_REFRESH_UTXOS from '@salesforce/label/c.UTXOAddresses_RefreshUTXOs';
import UTXO_ADDRESSES_FILTER_LABEL from '@salesforce/label/c.UTXOAddresses_FilterLabel';
import UTXO_ADDRESSES_FILTER_PLACEHOLDER from '@salesforce/label/c.UTXOAddresses_FilterPlaceholder';
import UTXO_ADDRESSES_LOADING from '@salesforce/label/c.UTXOAddresses_Loading';
import UTXO_ADDRESSES_ERROR_TITLE from '@salesforce/label/c.UTXOAddresses_ErrorTitle';
import UTXO_ADDRESSES_TAB_EXTERNAL from '@salesforce/label/c.UTXOAddresses_TabExternal';
import UTXO_ADDRESSES_TAB_INTERNAL from '@salesforce/label/c.UTXOAddresses_TabInternal';
import UTXO_ADDRESSES_VIEW_ALL from '@salesforce/label/c.UTXOAddresses_ViewAll';
import UTXO_ADDRESSES_VIEW_LESS from '@salesforce/label/c.UTXOAddresses_ViewLess';
import UTXO_ADDRESSES_COLUMN_NAME from '@salesforce/label/c.UTXOAddresses_ColumnName';
import UTXO_ADDRESSES_COLUMN_PATH from '@salesforce/label/c.UTXOAddresses_ColumnPath';
import UTXO_ADDRESSES_COLUMN_ADDRESS from '@salesforce/label/c.UTXOAddresses_ColumnAddress';
import UTXO_ADDRESSES_COLUMN_PAYMENT_KEY_HASH from '@salesforce/label/c.UTXOAddresses_ColumnPaymentKeyHash';
import UTXO_ADDRESSES_CARDANOSCAN_TOOLTIP from '@salesforce/label/c.UTXOAddresses_CardanoScanTooltip';
import UTXO_ADDRESSES_LIBRARY_LOAD_FAILED from '@salesforce/label/c.UTXOAddresses_LibraryLoadFailed';
import UTXO_ADDRESSES_LIBRARY_LOAD_ERROR from '@salesforce/label/c.UTXOAddresses_LibraryLoadError';
import UTXO_ADDRESSES_LIBRARY_INIT_ERROR from '@salesforce/label/c.UTXOAddresses_LibraryInitError';
import UTXO_ADDRESSES_UNKNOWN_ERROR from '@salesforce/label/c.UTXOAddresses_UnknownError';
import UTXO_ADDRESSES_LOAD_ERROR_TITLE from '@salesforce/label/c.UTXOAddresses_LoadErrorTitle';
import UTXO_ADDRESSES_WALLET_NOT_FOUND from '@salesforce/label/c.UTXOAddresses_WalletNotFound';
import UTXO_ADDRESSES_LIBRARY_NOT_LOADED from '@salesforce/label/c.UTXOAddresses_LibraryNotLoaded';
import UTXO_ADDRESSES_KEY_MISMATCH from '@salesforce/label/c.UTXOAddresses_KeyMismatch';
import UTXO_ADDRESSES_GENERATE_SUCCESS from '@salesforce/label/c.UTXOAddresses_GenerateSuccess';
import UTXO_ADDRESSES_GENERATE_ERROR from '@salesforce/label/c.UTXOAddresses_GenerateError';
import UTXO_ADDRESSES_REFRESH_SUCCESS from '@salesforce/label/c.UTXOAddresses_RefreshSuccess';
import UTXO_ADDRESSES_REFRESH_ERROR from '@salesforce/label/c.UTXOAddresses_RefreshError';

// Organize labels into categories
export const labels = {
    UI: {
        TITLE: UTXO_ADDRESSES_TITLE,
        SUBTITLE: UTXO_ADDRESSES_SUBTITLE,
        UNUSED: UTXO_ADDRESSES_UNUSED,
        GENERATE_NEW_ADDRESS: UTXO_ADDRESSES_GENERATE_NEW_ADDRESS,
        REFRESH_UTXOS: UTXO_ADDRESSES_REFRESH_UTXOS,
        FILTER_LABEL: UTXO_ADDRESSES_FILTER_LABEL,
        FILTER_PLACEHOLDER: UTXO_ADDRESSES_FILTER_PLACEHOLDER,
        LOADING: UTXO_ADDRESSES_LOADING,
        ERROR_TITLE: UTXO_ADDRESSES_ERROR_TITLE,
        TAB_EXTERNAL: UTXO_ADDRESSES_TAB_EXTERNAL,
        TAB_INTERNAL: UTXO_ADDRESSES_TAB_INTERNAL,
        VIEW_ALL: UTXO_ADDRESSES_VIEW_ALL,
        VIEW_LESS: UTXO_ADDRESSES_VIEW_LESS
    },
    COLUMNS: {
        NAME: UTXO_ADDRESSES_COLUMN_NAME,
        PATH: UTXO_ADDRESSES_COLUMN_PATH,
        ADDRESS: UTXO_ADDRESSES_COLUMN_ADDRESS,
        PAYMENT_KEY_HASH: UTXO_ADDRESSES_COLUMN_PAYMENT_KEY_HASH,
        CARDANOSCAN_TOOLTIP: UTXO_ADDRESSES_CARDANOSCAN_TOOLTIP
    },
    ERROR: {
        LIBRARY_LOAD_FAILED: UTXO_ADDRESSES_LIBRARY_LOAD_FAILED,
        LIBRARY_LOAD_ERROR: UTXO_ADDRESSES_LIBRARY_LOAD_ERROR,
        LIBRARY_INIT_ERROR: UTXO_ADDRESSES_LIBRARY_INIT_ERROR,
        UNKNOWN_ERROR: UTXO_ADDRESSES_UNKNOWN_ERROR,
        LOAD_ERROR_TITLE: UTXO_ADDRESSES_LOAD_ERROR_TITLE,
        WALLET_NOT_FOUND: UTXO_ADDRESSES_WALLET_NOT_FOUND,
        LIBRARY_NOT_LOADED: UTXO_ADDRESSES_LIBRARY_NOT_LOADED,
        KEY_MISMATCH: UTXO_ADDRESSES_KEY_MISMATCH,
        GENERATE_ERROR: UTXO_ADDRESSES_GENERATE_ERROR,
        REFRESH_ERROR: UTXO_ADDRESSES_REFRESH_ERROR
    },
    SUCCESS: {
        GENERATE_SUCCESS: UTXO_ADDRESSES_GENERATE_SUCCESS,
        REFRESH_SUCCESS: UTXO_ADDRESSES_REFRESH_SUCCESS
    }
}; 