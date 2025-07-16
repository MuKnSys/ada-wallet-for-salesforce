/**
 * Controller for UTXO address management and operations
 * Provides methods for address creation, synchronization, and permissions
 */
public with sharing class UTXOController {
    
    // Error messages
    private static final String ERROR_SEED_PHRASE_FAILED = 'Failed to get seed phrase: ';
    private static final String ERROR_RETRIEVING_WALLET = 'Error retrieving wallet: ';
    private static final String ERROR_RETRIEVING_ADDRESSES = 'Error retrieving UTXO addresses: ';
    private static final String ERROR_RETRIEVING_PERMISSIONS = 'Error retrieving user permissions: ';
    private static final String ERROR_RETRIEVING_INDEX = 'Error retrieving next UTXO index: ';
    private static final String ERROR_ADDING_RECEIVING = 'Error adding receiving UTXO address: ';
    private static final String ERROR_ADDING_CHANGE = 'Error adding change UTXO address: ';
    private static final String ERROR_SYNCING_ASSETS = 'Error syncing assets and transactions: ';
    private static final String ERROR_SETTING_USED = 'Error setting addresses as used: ';
    
    // Inner classes for data structures
    public class UTXOAddress {
        @AuraEnabled public Integer index { get; set; }
        @AuraEnabled public String publicKey { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String paymentKeyHash { get; set; }
        @AuraEnabled public String path { get; set; }
        @AuraEnabled public String stakePath { get; set; }
        @AuraEnabled public String privateKey { get; set; }
    }

    /**
     * Get encrypted seed phrase for a wallet set
     * @param walletSetId The wallet set ID
     * @return The encrypted seed phrase
     */
    @AuraEnabled(cacheable=true)
    public static String getEncryptedSeedPhrase(Id walletSetId) {
        try {            
            return EncryptedDataService.getEncryptedSeedPhrase(walletSetId);
        } catch (Exception e) {            
            throw new AuraHandledException(ERROR_SEED_PHRASE_FAILED + e.getMessage());
        }
    }

    /**
     * Get wallet by ID
     * @param walletId The wallet ID
     * @return The wallet record
     */
    @AuraEnabled
    public static Wallet__c getWallet(String walletId) {
        try {
            return WalletSelector.getWalletById(walletId);
        } catch (Exception e) {
            throw new AuraHandledException(ERROR_RETRIEVING_WALLET + e.getMessage());
        }
    }

    /**
     * Get UTXO addresses for a wallet
     * @param walletId The wallet ID
     * @return List of UTXO addresses
     */
    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getUTXOAddresses(String walletId) {
        try {
            return UTXOAddressSelector.getAddressesByWalletId(walletId);
        } catch (Exception e) {
            throw new AuraHandledException(ERROR_RETRIEVING_ADDRESSES + e.getMessage());
        }
    }

    /**
     * Get user permissions
     * @return List of permission set names assigned to the user
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getUserPermissions() {
        try {
            return retrieveUserPermissionSets();
        } catch (Exception e) {
            throw new AuraHandledException(ERROR_RETRIEVING_PERMISSIONS + e.getMessage());
        }
    }

    /**
     * Get next available UTXO index for a wallet and type
     * @param walletId The wallet ID
     * @param type The address type ('0' for receiving, '1' for change)
     * @return The next available index
     */
    @AuraEnabled(cacheable=true)
    public static Integer getNextUTXOIndex(String walletId, String type) {
        try {
            validateAddressType(type);

            List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getLastUTXOAddressByType(walletId, type);

            if (utxoAddresses.isEmpty()) {
                return 0;
            }

            return (Integer)utxoAddresses[0].Index__c + 1;
        } catch (Exception e) {
            throw new AuraHandledException(ERROR_RETRIEVING_INDEX + e.getMessage());
        }
    }

    /**
     * Add a receiving UTXO address
     * @param walletId The wallet ID
     * @param receivingAddress The receiving address data
     * @return The created UTXO address ID
     */
    @AuraEnabled
    public static String addReceivingUTXOAddress(String walletId, UTXOAddress receivingAddress) {
        try {
            validateAddress(receivingAddress, Constants.LABEL_RECEIVING_LOWERCASE);
            return createUTXOAddress(walletId, receivingAddress, Constants.ADDRESS_TYPE_RECEIVING);
        } catch (Exception e) {
            throw new AuraHandledException(ERROR_ADDING_RECEIVING + e.getMessage());
        }
    }

    /**
     * Add a change UTXO address
     * @param walletId The wallet ID
     * @param changeAddress The change address data
     * @return The created UTXO address ID
     */
    @AuraEnabled
    public static String addChangeUTXOAddress(String walletId, UTXOAddress changeAddress) {
        try {
            validateAddress(changeAddress, Constants.LABEL_CHANGE_LOWERCASE);
            return createUTXOAddress(walletId, changeAddress, Constants.ADDRESS_TYPE_CHANGE);
        } catch (Exception e) {
            throw new AuraHandledException(ERROR_ADDING_CHANGE + e.getMessage());
        }
    }
    
    /**
     * Sync assets and transactions for a UTXO address
     * @param utxoAddressId The UTXO address ID
     * @return Map with sync results
     */
    @AuraEnabled
    public static Map<String, Object> syncAssetsAndTransactions(Id utxoAddressId) {
        try {
            return UTXOHelper.syncAssetsAndTransactions(utxoAddressId);
        } catch (Exception e) {
            throw new AuraHandledException(ERROR_SYNCING_ASSETS + e.getMessage());
        }
    }

    /**
     * Set addresses as used
     * @param utxoAddressIds List of UTXO address IDs to mark as used
     */
    @AuraEnabled
    public static void setAddressesUsed(List<Id> utxoAddressIds) {
        try {
            UTXOHelper.setAddressesUsed(utxoAddressIds);
        } catch (Exception e) {
            throw new AuraHandledException(ERROR_SETTING_USED + e.getMessage());
        }
    }
    
    // =============================================================================
    // PRIVATE HELPER METHODS
    // =============================================================================
    
    /**
     * Validate address type is valid
     */
    private static void validateAddressType(String type) {
        if (String.isBlank(type) || !(type == Constants.ADDRESS_TYPE_RECEIVING || type == Constants.ADDRESS_TYPE_CHANGE)) {
            throw new AuraHandledException(Constants.ERROR_INVALID_ADDRESS_TYPE);
        }
    }
    
    /**
     * Validate address data is complete
     */
    private static void validateAddress(UTXOAddress address, String addressType) {
        if (address == null) {
            throw new AuraHandledException(addressType + Constants.ERROR_ADDRESS_NULL);
        }
        if (address.index == null || String.isBlank(address.address) || 
            String.isBlank(address.publicKey) || String.isBlank(address.paymentKeyHash) || 
            String.isBlank(address.path)) {
            throw new AuraHandledException(Constants.ERROR_INVALID_ADDRESS_DATA + address.index);
        }
    }
    
    /**
     * Retrieve user permission sets
     */
    private static List<String> retrieveUserPermissionSets() {
        List<String> assignedPermissionSets = new List<String>();
        for (PermissionSetAssignment psa : [
            SELECT PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
        ]) {
            assignedPermissionSets.add(psa.PermissionSet.Name);
        }
        return assignedPermissionSets;
    }
    
    /**
     * Create UTXO address record
     */
    private static String createUTXOAddress(String walletId, UTXOAddress address, String type) {
        UTXO_Address__c utxoRecord = new UTXO_Address__c(
            Wallet__c = walletId,
            Address__c = address.address,
            Index__c = address.index,
            Public_Key__c = address.publicKey,
            Payment_Key_Hash__c = address.paymentKeyHash,
            Path__c = address.path,
            Private_Key__c = String.isNotBlank(address.privateKey) ? address.privateKey : null,
            Type__c = type
        );

        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<UTXO_Address__c>{utxoRecord});
        insert decision.getRecords();
        
        return decision.getRecords()[0].Id;
    }
}