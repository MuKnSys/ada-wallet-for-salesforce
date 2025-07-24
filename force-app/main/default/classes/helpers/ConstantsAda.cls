public class ConstantsAda {    
    public static final String ADDRESS_TYPE_RECEIVING = '0';
    public static final String ADDRESS_TYPE_CHANGE = '1';
    public static final String LABEL_RECEIVING_LOWERCASE = 'receiving';
    public static final String LABEL_CHANGE_LOWERCASE = 'change';
    public static final String LABEL_RECEIVING_TITLE = 'Receiving';
    public static final String LABEL_CHANGE_TITLE = 'Change';
    
    public static final String ASSET_ADA = 'ADA';
    public static final String ASSET_LOVELACE = 'lovelace';
    public static final String DEFAULT_ASSET_ICON = 'utility:money';
    
    public static final String TRANSACTION_TYPE_INBOUND = 'inbound';
    public static final String TRANSACTION_TYPE_OUTBOUND = 'outbound';
    
    public static final Integer LOVELACE_TO_ADA_RATIO = 1000000;
    
    public static final String STATUS_NOT_APPROVED = 'Not Approved';
    public static final String STATUS_READY_TO_SIGN = 'Ready to Sign';
    public static final String STATUS_READY_TO_SEND = 'Ready to send';
    public static final String STATUS_SENT = 'Sent';
    public static final String STATUS_REJECTED = 'Rejected';
    public static final String APPROVAL_STATUS_APPROVED = 'Approved';
    public static final String APPROVAL_STATUS_NOT_APPROVED = 'Not Approved';
    
    public static final Integer MIN_TRANSACTION_HASH_LENGTH = 64;
    
    public static final String ERROR_WALLET_ID_REQUIRED = 'Wallet ID is required';
    public static final String ERROR_WALLET_NOT_FOUND = 'Wallet not found for ID: ';
    public static final String ERROR_ADDRESS_REQUIRED = 'Address is required';
    public static final String ERROR_INVALID_ADDRESS_TYPE = 'Type must be "0" (receiving) or "1" (change)';
    public static final String ERROR_ADDRESS_NULL = ' address cannot be null';
    public static final String ERROR_INVALID_ADDRESS_DATA = 'Invalid address data for index ';
    public static final String ERROR_ASSET_REQUIRED = 'Asset is required';
    public static final String ERROR_AMOUNT_REQUIRED = 'Amount is required';
    public static final String ERROR_TO_ADDRESS_REQUIRED = 'To Address is required';
    public static final String ERROR_ASSETS_REQUIRED = 'At least one asset is required';
    public static final String ERROR_INVALID_AMOUNT = 'Invalid amount format';
    public static final String ERROR_AMOUNT_MUST_BE_POSITIVE = 'Amount must be greater than 0';
    public static final String ERROR_TX_HASH_REQUIRED = 'Transaction hash is required';
    public static final String ERROR_CBOR_REQUIRED = 'CBOR hex is required';
    public static final String ERROR_WALLET_ADDRESSES_REQUIRED = 'Wallet addresses are required';
    public static final String ERROR_TX_HASHES_REQUIRED = 'Transaction hashes are required';
    public static final String ERROR_RECORD_ID_REQUIRED = 'Record ID is required';
    public static final String ERROR_SIGNED_CBOR_REQUIRED = 'Signed CBOR is required';
    public static final String ERROR_OUTBOUND_TX_NOT_FOUND = 'Outbound Transaction not found';
    public static final String ERROR_WALLET_SET_NOT_FOUND = 'Wallet Set not found';
    public static final String ERROR_SEED_PHRASE_NOT_FOUND = 'Seed phrase not found for this Wallet Set';
    public static final String ERROR_ADDRESS_LISTS_NULL = 'Address lists cannot be null';
    
    public static final Integer STATUS_OK = 200;
    public static final Integer STATUS_NOT_FOUND = 404;
    public static final Integer STATUS_BAD_REQUEST = 400;
    public static final Integer STATUS_SERVER_ERROR = 500;
} 