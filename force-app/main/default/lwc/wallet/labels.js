import Wallet_AddToken from '@salesforce/label/c.Wallet_AddToken';
import Wallet_AddressCopiedToClipboard from '@salesforce/label/c.Wallet_AddressCopiedToClipboard';
import Wallet_AmountADA from '@salesforce/label/c.Wallet_AmountADA';
import Wallet_AmountRequired from '@salesforce/label/c.Wallet_AmountRequired';
import Wallet_AllTokensAlreadyAdded from '@salesforce/label/c.Wallet_AllTokensAlreadyAdded';
import Wallet_Assets from '@salesforce/label/c.Wallet_Assets';
import Wallet_Available from '@salesforce/label/c.Wallet_Available';
import Wallet_Back from '@salesforce/label/c.Wallet_Back';
import Wallet_Balance from '@salesforce/label/c.Wallet_Balance';
import Wallet_Cancel from '@salesforce/label/c.Wallet_Cancel';
import Wallet_CannotGenerateQRCode from '@salesforce/label/c.Wallet_CannotGenerateQRCode';
import Wallet_CannotOpenReceiveModal from '@salesforce/label/c.Wallet_CannotOpenReceiveModal';
import Wallet_Close from '@salesforce/label/c.Wallet_Close';
import Wallet_CopyAddress from '@salesforce/label/c.Wallet_CopyAddress';
import Wallet_CreateTransaction from '@salesforce/label/c.Wallet_CreateTransaction';
import Wallet_Currency from '@salesforce/label/c.Wallet_Currency';
import Wallet_DownloadQRCode from '@salesforce/label/c.Wallet_DownloadQRCode';
import Wallet_EnterAmountInADA from '@salesforce/label/c.Wallet_EnterAmountInADA';
import Wallet_EnterCardanoAddress from '@salesforce/label/c.Wallet_EnterCardanoAddress';
import Wallet_EnterMemo from '@salesforce/label/c.Wallet_EnterMemo';
import Wallet_ExceedsAvailable from '@salesforce/label/c.Wallet_ExceedsAvailable';
import Wallet_FailedToCopyAddressToClipboard from '@salesforce/label/c.Wallet_FailedToCopyAddressToClipboard';
import Wallet_FailedToGenerateQRCode from '@salesforce/label/c.Wallet_FailedToGenerateQRCode';
import Wallet_FailedToLoadQRCodeLibrary from '@salesforce/label/c.Wallet_FailedToLoadQRCodeLibrary';
import Wallet_Hash from '@salesforce/label/c.Wallet_Hash';
import Wallet_HowMuchWouldYouLikeToSend from '@salesforce/label/c.Wallet_HowMuchWouldYouLikeToSend';
import Wallet_Inbound from '@salesforce/label/c.Wallet_Inbound';
import Wallet_InboundTransactions from '@salesforce/label/c.Wallet_InboundTransactions';
import Wallet_InsufficientBalance from '@salesforce/label/c.Wallet_InsufficientBalance';
import Wallet_LoadingPaymentAddress from '@salesforce/label/c.Wallet_LoadingPaymentAddress';
import Wallet_LoadingWalletData from '@salesforce/label/c.Wallet_LoadingWalletData';
import Wallet_MemoOptional from '@salesforce/label/c.Wallet_MemoOptional';
import Wallet_MethodNotYetImplemented from '@salesforce/label/c.Wallet_MethodNotYetImplemented';
import Wallet_MultiAssetTransactionCreatedSuccessfully from '@salesforce/label/c.Wallet_MultiAssetTransactionCreatedSuccessfully';
import Wallet_Next from '@salesforce/label/c.Wallet_Next';
import Wallet_NoAssetsAvailable from '@salesforce/label/c.Wallet_NoAssetsAvailable';
import Wallet_NoInboundTransactions from '@salesforce/label/c.Wallet_NoInboundTransactions';
import Wallet_NoOutboundTransactions from '@salesforce/label/c.Wallet_NoOutboundTransactions';
import Wallet_NoUnusedAddressAvailable from '@salesforce/label/c.Wallet_NoUnusedAddressAvailable';
import Wallet_NoValidAssetsToSend from '@salesforce/label/c.Wallet_NoValidAssetsToSend';
import Wallet_NotAvailable from '@salesforce/label/c.Wallet_NotAvailable';
import Wallet_Outbound from '@salesforce/label/c.Wallet_Outbound';
import Wallet_OutboundTransactions from '@salesforce/label/c.Wallet_OutboundTransactions';
import Wallet_PaymentAddress from '@salesforce/label/c.Wallet_PaymentAddress';
import Wallet_PleaseEnterValidAmountGreaterThanZero from '@salesforce/label/c.Wallet_PleaseEnterValidAmountGreaterThanZero';
import Wallet_PleaseEnterValidCardanoAddress from '@salesforce/label/c.Wallet_PleaseEnterValidCardanoAddress';
import Wallet_QRCodeDownloadNotImplemented from '@salesforce/label/c.Wallet_QRCodeDownloadNotImplemented';
import Wallet_Receive from '@salesforce/label/c.Wallet_Receive';
import Wallet_ReceiveADA from '@salesforce/label/c.Wallet_ReceiveADA';
import Wallet_RecipientAddress from '@salesforce/label/c.Wallet_RecipientAddress';
import Wallet_RecipientAddressRequired from '@salesforce/label/c.Wallet_RecipientAddressRequired';
import Wallet_Remove from '@salesforce/label/c.Wallet_Remove';
import Wallet_SendMax from '@salesforce/label/c.Wallet_SendMax';
import Wallet_SendTransaction from '@salesforce/label/c.Wallet_SendTransaction';
import Wallet_Step1Recipient from '@salesforce/label/c.Wallet_Step1Recipient';
import Wallet_Step2Amount from '@salesforce/label/c.Wallet_Step2Amount';
import Wallet_Status from '@salesforce/label/c.Wallet_Status';
import Wallet_Title from '@salesforce/label/c.Wallet_Title';
import Wallet_Token from '@salesforce/label/c.Wallet_Token';
import Wallet_Tokens from '@salesforce/label/c.Wallet_Tokens';
import Wallet_To from '@salesforce/label/c.Wallet_To';
import Wallet_TransactionCreatedSuccessfully from '@salesforce/label/c.Wallet_TransactionCreatedSuccessfully';
import Wallet_Transactions from '@salesforce/label/c.Wallet_Transactions';
import Wallet_UnableToGenerateQR from '@salesforce/label/c.Wallet_UnableToGenerateQR';
import Wallet_UnknownError from '@salesforce/label/c.Wallet_UnknownError';
import Wallet_ValidCardanoAddress from '@salesforce/label/c.Wallet_ValidCardanoAddress';
import Wallet_ViewAll from '@salesforce/label/c.Wallet_ViewAll';
import Wallet_WhoWouldYouLikeToSendTo from '@salesforce/label/c.Wallet_WhoWouldYouLikeToSendTo';
import Wallet_YourPaymentAddress from '@salesforce/label/c.Wallet_YourPaymentAddress';

export const labels = {
    UI: {
        TITLE: Wallet_Title,
        BALANCE: Wallet_Balance,
        CURRENCY: Wallet_Currency,
        NOT_AVAILABLE: Wallet_NotAvailable,
        PAYMENT_ADDRESS: Wallet_PaymentAddress,
        CREATE_TRANSACTION: Wallet_CreateTransaction,
        RECEIVE: Wallet_Receive,
        ASSETS: Wallet_Assets,
        TRANSACTIONS: Wallet_Transactions,
        NO_ASSETS_AVAILABLE: Wallet_NoAssetsAvailable,
        INBOUND: Wallet_Inbound,
        OUTBOUND: Wallet_Outbound,
        INBOUND_TRANSACTIONS: Wallet_InboundTransactions,
        OUTBOUND_TRANSACTIONS: Wallet_OutboundTransactions,
        HASH: Wallet_Hash,
        STATUS: Wallet_Status,
        VIEW_ALL: Wallet_ViewAll,
        NO_INBOUND_TRANSACTIONS: Wallet_NoInboundTransactions,
        NO_OUTBOUND_TRANSACTIONS: Wallet_NoOutboundTransactions,
        CLOSE: Wallet_Close,
        RECEIVE_ADA: Wallet_ReceiveADA,
        YOUR_PAYMENT_ADDRESS: Wallet_YourPaymentAddress,
        UNABLE_TO_GENERATE_QR: Wallet_UnableToGenerateQR,
        COPY_ADDRESS: Wallet_CopyAddress,
        DOWNLOAD_QR_CODE: Wallet_DownloadQRCode,
        SEND_TRANSACTION: Wallet_SendTransaction,
        STEP1_RECIPIENT: Wallet_Step1Recipient,
        STEP2_AMOUNT: Wallet_Step2Amount,
        WHO_WOULD_YOU_LIKE_TO_SEND_TO: Wallet_WhoWouldYouLikeToSendTo,
        RECIPIENT_ADDRESS: Wallet_RecipientAddress,
        ENTER_CARDANO_ADDRESS: Wallet_EnterCardanoAddress,
        MEMO_OPTIONAL: Wallet_MemoOptional,
        ENTER_MEMO: Wallet_EnterMemo,
        VALID_CARDANO_ADDRESS: Wallet_ValidCardanoAddress,
        HOW_MUCH_WOULD_YOU_LIKE_TO_SEND: Wallet_HowMuchWouldYouLikeToSend,
        TO: Wallet_To,
        AMOUNT_ADA: Wallet_AmountADA,
        ENTER_AMOUNT_IN_ADA: Wallet_EnterAmountInADA,
        TOKENS: Wallet_Tokens,
        TOKEN: Wallet_Token,
        SEND_MAX: Wallet_SendMax,
        AVAILABLE: Wallet_Available,
        ADD_TOKEN: Wallet_AddToken,
        REMOVE: Wallet_Remove,
        CANCEL: Wallet_Cancel,
        NEXT: Wallet_Next,
        BACK: Wallet_Back,
        LOADING_WALLET_DATA: Wallet_LoadingWalletData,
        LOADING_PAYMENT_ADDRESS: Wallet_LoadingPaymentAddress,
        NO_UNUSED_ADDRESS_AVAILABLE: Wallet_NoUnusedAddressAvailable
    },
    ERROR: {
        UNKNOWN_ERROR: Wallet_UnknownError,
        METHOD_NOT_YET_IMPLEMENTED: Wallet_MethodNotYetImplemented,
        FAILED_TO_LOAD_QR_CODE_LIBRARY: Wallet_FailedToLoadQRCodeLibrary,
        CANNOT_GENERATE_QR_CODE: Wallet_CannotGenerateQRCode,
        FAILED_TO_GENERATE_QR_CODE: Wallet_FailedToGenerateQRCode,
        CANNOT_OPEN_RECEIVE_MODAL: Wallet_CannotOpenReceiveModal,
        FAILED_TO_COPY_ADDRESS_TO_CLIPBOARD: Wallet_FailedToCopyAddressToClipboard,
        NO_VALID_ASSETS_TO_SEND: Wallet_NoValidAssetsToSend,
        RECIPIENT_ADDRESS_REQUIRED: Wallet_RecipientAddressRequired,
        PLEASE_ENTER_VALID_CARDANO_ADDRESS: Wallet_PleaseEnterValidCardanoAddress,
        AMOUNT_REQUIRED: Wallet_AmountRequired,
        PLEASE_ENTER_VALID_AMOUNT_GREATER_THAN_ZERO: Wallet_PleaseEnterValidAmountGreaterThanZero,
        INSUFFICIENT_BALANCE: Wallet_InsufficientBalance,
        EXCEEDS_AVAILABLE: Wallet_ExceedsAvailable
    },
    SUCCESS: {
        ADDRESS_COPIED_TO_CLIPBOARD: Wallet_AddressCopiedToClipboard,
        MULTI_ASSET_TRANSACTION_CREATED_SUCCESSFULLY: Wallet_MultiAssetTransactionCreatedSuccessfully,
        TRANSACTION_CREATED_SUCCESSFULLY: Wallet_TransactionCreatedSuccessfully
    },
    INFO: {
        QR_CODE_DOWNLOAD_NOT_IMPLEMENTED: Wallet_QRCodeDownloadNotImplemented,
        ALL_TOKENS_ALREADY_ADDED: Wallet_AllTokensAlreadyAdded
    }
}; 