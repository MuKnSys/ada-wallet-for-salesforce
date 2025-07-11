import CreateNewWallet_AccountIndexLabel from '@salesforce/label/c.CreateNewWallet_AccountIndexLabel';
import CreateNewWallet_AccountIndexRequired from '@salesforce/label/c.CreateNewWallet_AccountIndexRequired';
import CreateNewWallet_AccountIndexMustBeNumber from '@salesforce/label/c.CreateNewWallet_AccountIndexMustBeNumber';
import CreateNewWallet_AccountIndexNonNegative from '@salesforce/label/c.CreateNewWallet_AccountIndexNonNegative';
import CreateNewWallet_ButtonLabel from '@salesforce/label/c.CreateNewWallet_ButtonLabel';
import CreateNewWallet_ButtonLabelCreating from '@salesforce/label/c.CreateNewWallet_ButtonLabelCreating';
import CreateNewWallet_CardTitle from '@salesforce/label/c.CreateNewWallet_CardTitle';
import CreateNewWallet_EnterWordPlaceholder from '@salesforce/label/c.CreateNewWallet_EnterWordPlaceholder';
import CreateNewWallet_ErrorAccountIndexValidation from '@salesforce/label/c.CreateNewWallet_ErrorAccountIndexValidation';
import CreateNewWallet_ErrorFetchNextIndex from '@salesforce/label/c.CreateNewWallet_ErrorFetchNextIndex';
import CreateNewWallet_ErrorInvalidBip32Key from '@salesforce/label/c.CreateNewWallet_ErrorInvalidBip32Key';
import CreateNewWallet_ErrorInvalidMnemonic from '@salesforce/label/c.CreateNewWallet_ErrorInvalidMnemonic';
import CreateNewWallet_ErrorLibrariesNotLoaded from '@salesforce/label/c.CreateNewWallet_ErrorLibrariesNotLoaded';
import CreateNewWallet_ErrorRawKeyExtraction from '@salesforce/label/c.CreateNewWallet_ErrorRawKeyExtraction';
import CreateNewWallet_ErrorRawKeyInvalid from '@salesforce/label/c.CreateNewWallet_ErrorRawKeyInvalid';
import CreateNewWallet_ErrorSeedPhraseEmpty from '@salesforce/label/c.CreateNewWallet_ErrorSeedPhraseEmpty';
import CreateNewWallet_ErrorSeedPhraseIncorrect from '@salesforce/label/c.CreateNewWallet_ErrorSeedPhraseIncorrect';
import CreateNewWallet_ErrorUnknown from '@salesforce/label/c.CreateNewWallet_ErrorUnknown';
import CreateNewWallet_ErrorWalletCreation from '@salesforce/label/c.CreateNewWallet_ErrorWalletCreation';
import CreateNewWallet_ErrorWalletRecordCreation from '@salesforce/label/c.CreateNewWallet_ErrorWalletRecordCreation';
import CreateNewWallet_InvalidWalletSetId from '@salesforce/label/c.CreateNewWallet_InvalidWalletSetId';
import CreateNewWallet_LibraryLoadingFailed from '@salesforce/label/c.CreateNewWallet_LibraryLoadingFailed';
import CreateNewWallet_ProgressDerivingKeys from '@salesforce/label/c.CreateNewWallet_ProgressDerivingKeys';
import CreateNewWallet_ProgressFinalizing from '@salesforce/label/c.CreateNewWallet_ProgressFinalizing';
import CreateNewWallet_ProgressInitializing from '@salesforce/label/c.CreateNewWallet_ProgressInitializing';
import CreateNewWallet_ProgressPreparingNavigation from '@salesforce/label/c.CreateNewWallet_ProgressPreparingNavigation';
import CreateNewWallet_ProgressVerifyingSeedPhrase from '@salesforce/label/c.CreateNewWallet_ProgressVerifyingSeedPhrase';
import CreateNewWallet_ProgressCheckingServer from '@salesforce/label/c.CreateNewWallet_ProgressCheckingServer';
import CreateNewWallet_ProgressCreatingWallet from '@salesforce/label/c.CreateNewWallet_ProgressCreatingWallet';
import CreateNewWallet_SeedPhraseLengthLabel from '@salesforce/label/c.CreateNewWallet_SeedPhraseLengthLabel';
import CreateNewWallet_SeedPhraseVerificationDescription from '@salesforce/label/c.CreateNewWallet_SeedPhraseVerificationDescription';
import CreateNewWallet_SeedPhraseVerificationHeader from '@salesforce/label/c.CreateNewWallet_SeedPhraseVerificationHeader';
import CreateNewWallet_SelectWalletSetPlaceholder from '@salesforce/label/c.CreateNewWallet_SelectWalletSetPlaceholder';
import CreateNewWallet_SuccessWalletCreated from '@salesforce/label/c.CreateNewWallet_SuccessWalletCreated';
import CreateNewWallet_ValidationPleaseSelectWalletSet from '@salesforce/label/c.CreateNewWallet_ValidationPleaseSelectWalletSet';
import CreateNewWallet_WalletNameLabel from '@salesforce/label/c.CreateNewWallet_WalletNameLabel';
import CreateNewWallet_WalletNameRequired from '@salesforce/label/c.CreateNewWallet_WalletNameRequired';
import CreateNewWallet_WalletNameTooLong from '@salesforce/label/c.CreateNewWallet_WalletNameTooLong';
import CreateNewWallet_WalletSetLabel from '@salesforce/label/c.CreateNewWallet_WalletSetLabel';
import CreateNewWallet_WordCount15 from '@salesforce/label/c.CreateNewWallet_WordCount15';
import CreateNewWallet_WordCount24 from '@salesforce/label/c.CreateNewWallet_WordCount24';

export const labels = {
    ERROR: {
        AccountIndexValidation: CreateNewWallet_ErrorAccountIndexValidation,
        FetchNextIndex: CreateNewWallet_ErrorFetchNextIndex,
        InvalidBip32Key: CreateNewWallet_ErrorInvalidBip32Key,
        InvalidMnemonic: CreateNewWallet_ErrorInvalidMnemonic,
        LibraryLoading: CreateNewWallet_LibraryLoadingFailed,
        LibrariesNotLoaded: CreateNewWallet_ErrorLibrariesNotLoaded,
        RawKeyExtraction: CreateNewWallet_ErrorRawKeyExtraction,
        RawKeyInvalid: CreateNewWallet_ErrorRawKeyInvalid,
        SeedPhraseEmpty: CreateNewWallet_ErrorSeedPhraseEmpty,
        SeedPhraseIncorrect: CreateNewWallet_ErrorSeedPhraseIncorrect,
        Unknown: CreateNewWallet_ErrorUnknown,
        WalletCreation: CreateNewWallet_ErrorWalletCreation,
        WalletRecordCreation: CreateNewWallet_ErrorWalletRecordCreation
    },
    PROGRESS: {
        DerivingKeys: CreateNewWallet_ProgressDerivingKeys,
        Finalizing: CreateNewWallet_ProgressFinalizing,
        Initializing: CreateNewWallet_ProgressInitializing,
        PreparingNavigation: CreateNewWallet_ProgressPreparingNavigation,
        VerifyingSeedPhrase: CreateNewWallet_ProgressVerifyingSeedPhrase,
        CheckingServer: CreateNewWallet_ProgressCheckingServer,
        CreatingWallet: CreateNewWallet_ProgressCreatingWallet
    },
    SUCCESS: {
        WalletCreated: CreateNewWallet_SuccessWalletCreated
    },
    UI: {
        AccountIndexLabel: CreateNewWallet_AccountIndexLabel,
        AccountIndexRequired: CreateNewWallet_AccountIndexRequired,
        AccountIndexMustBeNumber: CreateNewWallet_AccountIndexMustBeNumber,
        AccountIndexNonNegative: CreateNewWallet_AccountIndexNonNegative,
        ButtonLabel: CreateNewWallet_ButtonLabel,
        ButtonLabelCreating: CreateNewWallet_ButtonLabelCreating,
        CardTitle: CreateNewWallet_CardTitle,
        EnterWordPlaceholder: CreateNewWallet_EnterWordPlaceholder,
        SeedPhraseLengthLabel: CreateNewWallet_SeedPhraseLengthLabel,
        SeedPhraseVerificationDescription: CreateNewWallet_SeedPhraseVerificationDescription,
        SeedPhraseVerificationHeader: CreateNewWallet_SeedPhraseVerificationHeader,
        SelectWalletSetPlaceholder: CreateNewWallet_SelectWalletSetPlaceholder,
        WalletNameLabel: CreateNewWallet_WalletNameLabel,
        WalletNameRequired: CreateNewWallet_WalletNameRequired,
        WalletNameTooLong: CreateNewWallet_WalletNameTooLong,
        WalletSetLabel: CreateNewWallet_WalletSetLabel
    },
    VALIDATION: {
        PleaseSelectWalletSet: CreateNewWallet_ValidationPleaseSelectWalletSet,
        InvalidWalletSetId: CreateNewWallet_InvalidWalletSetId
    },
    WORD_COUNT: {
        Option15: CreateNewWallet_WordCount15,
        Option24: CreateNewWallet_WordCount24
    }
}; 