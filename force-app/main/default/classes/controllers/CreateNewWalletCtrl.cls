/**
 * Controller for creating new wallets and managing wallet operations
 * Provides methods for wallet creation, address management, and seed phrase verification
 */
public with sharing class CreateNewWalletCtrl {
    // Error messages
    private static final String ERROR_ADDRESS_LISTS_NULL = 'Address lists cannot be null';
    
    /**
     * Create a new wallet with encrypted keys
     * @param walletSetId The wallet set ID
     * @param walletName The wallet name
     * @param address The wallet address
     * @param accountPrivateKey The encrypted private key
     * @param accountPublicKey The encrypted public key
     * @param accountIndex The account index
     * @param stakeAddress The stake address
     * @return The created wallet ID
     */
    @AuraEnabled
    public static Id createWallet(String walletSetId, String walletName, String address, String accountPrivateKey, String accountPublicKey, Integer accountIndex, String stakeAddress) {
        try {
            if (!Schema.sObjectType.Wallet__c.isCreateable() ||
                !Schema.sObjectType.Wallet__c.fields.Wallet_Set__c.isCreateable() ||
                !Schema.sObjectType.Wallet__c.fields.Name.isCreateable() ||
                !Schema.sObjectType.Wallet__c.fields.Account_Private_Key__c.isCreateable() ||
                !Schema.sObjectType.Wallet__c.fields.Account_Public_Key__c.isCreateable() ||
                !Schema.sObjectType.Wallet__c.fields.Account_Index__c.isCreateable() ||
                !Schema.sObjectType.Wallet__c.fields.Stake_Address__c.isCreateable()) {
                throw new AuraHandledException('Insufficient permissions to create wallet');
            }

            Wallet__c newWallet = createWalletRecord(walletSetId, walletName, address, accountPrivateKey, accountPublicKey, accountIndex, stakeAddress);
            insert newWallet;

            logWalletCreation(newWallet, walletSetId, accountIndex);
            return newWallet.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Wallet: ' + e.getMessage());
        } finally {
            LoggerAda.commitLogs();
        }
    }

    /**
     * Inner class for UTXO Address data from LWC
     */
    public class UTXOAddressData {
        @AuraEnabled public Integer index { get; set; }
        @AuraEnabled public String publicKey { get; set; }
        @AuraEnabled public String privateKey { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String paymentKeyHash { get; set; }
        @AuraEnabled public String path { get; set; }
    }

    /**
     * Get wallet by ID
     * @param walletId The wallet ID
     * @return The wallet record
     */
    @AuraEnabled(cacheable=true)
    public static Wallet__c getWalletById(String walletId) {
        try {
            validateWalletId(walletId);
            Wallet__c wallet = WalletSelector.getWalletById(walletId);
            
                    if (wallet == null) {
            throw new AuraHandledException(ConstantsAda.ERROR_WALLET_NOT_FOUND + walletId);
        }
            
            return wallet;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet: ' + e.getMessage());
        } finally {
            LoggerAda.commitLogs();
        }
    }

    /**
     * Get the next available account index for a wallet set
     * @param walletSetId The wallet set ID
     * @return The next available account index
     */
    @AuraEnabled
    public static Integer getNextAccountIndex(String walletSetId) {
        try {
            List<Wallet__c> wallets = walletSelector.getWalletsByWalletSetId(walletSetId);
            return findNextAvailableIndex(wallets);
        } catch (Exception e) {            
            throw new AuraHandledException('Error getting next account index: ' + e.getMessage());
        } finally {
            LoggerAda.commitLogs();
        }
    }

    /**
     * Validate if an account index is available for a wallet set
     * @param walletSetId The wallet set ID
     * @param accountIndex The account index to validate
     * @return Error message if index is taken, null if available
     */
    @AuraEnabled
    public static String isIndexValid(String walletSetId, Integer accountIndex) {
        try {
            List<Wallet__c> wallets = WalletSelector.getWalletByWalletSetAndAccountIndex(walletSetId, accountIndex);

            if (!wallets.isEmpty()) {
                return 'Account ' + accountIndex + ' already exists for this Wallet Set. Try a different wallet set or Account Index.';
            }
            return null;
        } catch (Exception e) {            
            throw new AuraHandledException('Error validating account index: ' + e.getMessage());
        }
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
            throw new AuraHandledException('Failed to get seed phrase: ' + e.getMessage());
        }
    }

    /**
     * Check if address has any transactions by calling Blockfrost directly
     * @param address The address to check
     * @return Map with usage information
     */
    @AuraEnabled
    public static Map<String, Object> checkAddressUsageOnly(String address) {
        try {
            Boolean isUsed = BlockfrostService.isAddressUsed(address);
            
            Map<String, Object> result = createAddressUsageResult(address, isUsed);
            
            if (isUsed) {
                enrichAddressUsageResult(result);
            }
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to check address usage: ' + e.getMessage());
        }
    }

    /**
     * Bulk create UTXO addresses without syncing
     * @param walletId The wallet ID
     * @param receivingAddresses List of receiving addresses
     * @param changeAddresses List of change addresses
     * @return Map with creation results
     */
    @AuraEnabled
    public static Map<String, Object> createUTXOAddressesBulk(String walletId, List<UTXOAddressData> receivingAddresses, List<UTXOAddressData> changeAddresses) {
        try {
            validateAddressLists(receivingAddresses, changeAddresses);

            List<UTXO_Address__c> allAddresses = new List<UTXO_Address__c>();
            List<Map<String, Object>> receivingResults = new List<Map<String, Object>>();
            List<Map<String, Object>> changeResults = new List<Map<String, Object>>();

            processAddresses(receivingAddresses, ConstantsAda.ADDRESS_TYPE_RECEIVING, ConstantsAda.LABEL_RECEIVING_TITLE, walletId, allAddresses, receivingResults);
            processAddresses(changeAddresses, ConstantsAda.ADDRESS_TYPE_CHANGE, ConstantsAda.LABEL_CHANGE_TITLE, walletId, allAddresses, changeResults);

            insertAddressesAndUpdateResults(allAddresses, receivingResults, changeResults, receivingAddresses.size());

            return createBulkCreationResult(walletId, receivingResults, changeResults, receivingAddresses.size(), changeAddresses.size());
        } catch (Exception e) {
            throw new AuraHandledException('Error creating UTXO addresses in bulk: ' + e.getMessage());
        }
    }

    /**
     * Verify user-entered seed phrase against the encrypted seed phrase
     * @param walletSetId The wallet set ID
     * @param userSeedPhrase The user-entered seed phrase
     * @return True if verification succeeds
     */
    @AuraEnabled
    public static Boolean verifySeedPhrase(String walletSetId, String userSeedPhrase) {
        try {
            Wallet_Set__c walletSet = WalletSetSelector.getWalletSetWithSeedPhrase(walletSetId);
            
                    if (walletSet == null) {
            throw new AuraHandledException(ConstantsAda.ERROR_WALLET_SET_NOT_FOUND);
        }

            if (String.isBlank(walletSet.Seed_Phrase__c)) {
                throw new AuraHandledException(ConstantsAda.ERROR_SEED_PHRASE_NOT_FOUND);
            }

            return DataEncryptor.verifyHmac(userSeedPhrase, walletSet.Seed_Phrase__c);
        } catch (Exception e) {
            return false;
        }
    }
    
    // =============================================================================
    // PRIVATE HELPER METHODS
    // =============================================================================
    
    /**
     * Validate wallet ID is not blank
     */
    private static void validateWalletId(String walletId) {
        if (String.isBlank(walletId)) {
            throw new AuraHandledException(ConstantsAda.ERROR_WALLET_ID_REQUIRED);
        }
    }
    
    /**
     * Validate address lists are not null
     */
    private static void validateAddressLists(List<UTXOAddressData> receivingAddresses, List<UTXOAddressData> changeAddresses) {
        if (receivingAddresses == null || changeAddresses == null) {
            throw new AuraHandledException(ERROR_ADDRESS_LISTS_NULL);
        }
    }
    
    /**
     * Create wallet record with encrypted keys
     */
    private static Wallet__c createWalletRecord(String walletSetId, String walletName, String address, String accountPrivateKey, String accountPublicKey, Integer accountIndex, String stakeAddress) {
        return new Wallet__c(
            Wallet_Set__c = walletSetId,
            Name = walletName,
            Account_Private_Key__c = DataEncryptor.encrypt(accountPrivateKey),
            Account_Public_Key__c = DataEncryptor.encrypt(accountPublicKey),
            Account_Index__c = accountIndex,
            Stake_Address__c = stakeAddress
        );
    }
    
    /**
     * Log wallet creation event
     */
    private static void logWalletCreation(Wallet__c wallet, String walletSetId, Integer accountIndex) {
        LoggerAda.logInfo('Wallet created: ' + wallet.Name + ' for Wallet Set: ' + walletSetId + ' with Account Index: ' + accountIndex + ' by User: ' + UserInfo.getName());
    }
    
    /**
     * Find next available account index
     */
    private static Integer findNextAvailableIndex(List<Wallet__c> wallets) {
        Set<Integer> usedIndices = new Set<Integer>();
        for (Wallet__c wallet : wallets) {
            if (wallet.Account_Index__c != null) {
                usedIndices.add(wallet.Account_Index__c.intValue());
            }
        }

        Integer nextIndex = 0;
        while (usedIndices.contains(nextIndex)) {
            nextIndex++;
        }

        return nextIndex;
    }
    
    /**
     * Create initial address usage result
     */
    private static Map<String, Object> createAddressUsageResult(String address, Boolean isUsed) {
        return new Map<String, Object>{
            'address' => address,
            'isUsed' => isUsed,
            'hasAssets' => false,
            'hasTransactions' => false,
            'checkMethod' => 'blockfrost_direct'
        };
    }
    
    /**
     * Enrich address usage result with detailed information
     */
    private static void enrichAddressUsageResult(Map<String, Object> result) {
        try {
            String address = (String) result.get('address');
            
            String utxosJson = BlockfrostService.getAddressUtxos(address);
            List<Object> utxoList = (List<Object>) JSON.deserializeUntyped(utxosJson);
            result.put('hasAssets', !utxoList.isEmpty());
            
            String transactionsJson = BlockfrostService.getAddressTransactions(address);
            List<Object> transactionList = (List<Object>) JSON.deserializeUntyped(transactionsJson);
            result.put('hasTransactions', !transactionList.isEmpty());
        } catch (Exception e) {
            // Keep default values if enrichment fails
        }
    }
    
    /**
     * Process addresses of a specific type
     */
    private static void processAddresses(List<UTXOAddressData> addresses, String type, String typeLabel, String walletId, 
                                        List<UTXO_Address__c> allAddresses, List<Map<String, Object>> results) {
        for (UTXOAddressData addr : addresses) {
            UTXO_Address__c utxoRecord = createUTXOAddressRecord(walletId, addr, type);
            allAddresses.add(utxoRecord);
            
            results.add(new Map<String, Object>{
                'address' => addr.address,
                'index' => addr.index,
                'type' => type,
                'typeLabel' => typeLabel
            });
        }
    }
    
    /**
     * Create UTXO address record
     */
    private static UTXO_Address__c createUTXOAddressRecord(String walletId, UTXOAddressData addr, String type) {
        return new UTXO_Address__c(
            Wallet__c = walletId,
            Address__c = addr.address,
            Index__c = addr.index,
            Is_Used__c = false,
            Public_Key__c = addr.publicKey,
            Payment_Key_Hash__c = DataEncryptor.encrypt(addr.paymentKeyHash),
            Path__c = addr.path,
            Private_Key__c = String.isNotBlank(addr.privateKey) ?  DataEncryptor.encrypt(addr.privateKey) : null,
            Type__c = type
        );
    }
    
    /**
     * Insert addresses and update results with IDs
     */
    private static void insertAddressesAndUpdateResults(List<UTXO_Address__c> allAddresses, List<Map<String, Object>> receivingResults, 
                                                    List<Map<String, Object>> changeResults, Integer receivingCount) {
        if (!allAddresses.isEmpty()) {
            if (!Schema.sObjectType.UTXO_Address__c.isCreateable() ||
                !Schema.sObjectType.UTXO_Address__c.fields.Wallet__c.isCreateable() ||
                !Schema.sObjectType.UTXO_Address__c.fields.Address__c.isCreateable() ||
                !Schema.sObjectType.UTXO_Address__c.fields.Index__c.isCreateable() ||
                !Schema.sObjectType.UTXO_Address__c.fields.Is_Used__c.isCreateable() ||
                !Schema.sObjectType.UTXO_Address__c.fields.Public_Key__c.isCreateable() ||
                !Schema.sObjectType.UTXO_Address__c.fields.Payment_Key_Hash__c.isCreateable() ||
                !Schema.sObjectType.UTXO_Address__c.fields.Path__c.isCreateable() ||
                !Schema.sObjectType.UTXO_Address__c.fields.Private_Key__c.isCreateable() ||
                !Schema.sObjectType.UTXO_Address__c.fields.Type__c.isCreateable()) {
                throw new AuraHandledException('Insufficient permissions to create UTXO addresses');
            }

            insert allAddresses;

            updateResultsWithIds(receivingResults, changeResults, allAddresses, receivingCount);
        }
    }

    /**
     * Update results with inserted record IDs
     */
    private static void updateResultsWithIds(List<Map<String, Object>> receivingResults, List<Map<String, Object>> changeResults, 
                                            List<SObject> insertedRecords, Integer receivingCount) {
        for (Integer i = 0; i < receivingResults.size(); i++) {
            receivingResults[i].put('utxoAddressId', insertedRecords[i].Id);
        }
        for (Integer i = 0; i < changeResults.size(); i++) {
            changeResults[i].put('utxoAddressId', insertedRecords[receivingCount + i].Id);
        }
    }
    
    /**
     * Create bulk creation result
     */
    private static Map<String, Object> createBulkCreationResult(String walletId, List<Map<String, Object>> receivingResults, 
                                                            List<Map<String, Object>> changeResults, Integer receivingCount, Integer changeCount) {
        return new Map<String, Object>{
            'success' => true,
            'walletId' => walletId,
            'receivingAddresses' => receivingResults,
            'changeAddresses' => changeResults,
            'statistics' => new Map<String, Object>{
                'totalReceivingCreated' => receivingCount,
                'totalChangeCreated' => changeCount
            }
        };
    }
}