public with sharing class CreateNewWalletCtrl {
    @AuraEnabled
    public static Id createWallet(String walletSetId, String walletName, String address, String accountPrivateKey, String accountPublicKey, Integer accountIndex, String stakeAddress) {
        try {
            Wallet__c newWallet = new Wallet__c(
                Wallet_Set__c = walletSetId,
                Name = walletName,
                Account_Private_Key__c = DataEncryptor.encrypt(accountPrivateKey),
                Account_Public_Key__c = DataEncryptor.encrypt(accountPublicKey),
                Account_Index__c = accountIndex,
                Stake_Address__c = stakeAddress
            );
            insert newWallet;
            
            Logger.logInfo('Wallet created: ' + newWallet.Name + ' for Wallet Set: ' + walletSetId + ' with Account Index: ' + accountIndex + ' by User: ' + UserInfo.getName());

            return newWallet.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Wallet: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
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



    @AuraEnabled(cacheable=true)
    public static Wallet__c getWalletById(String walletId) {
        try {
            if (String.isBlank(walletId)) {
                throw new AuraHandledException('Wallet ID is required');
            }
            Wallet__c wallet = WalletSelector.getWalletById(walletId);
            if (wallet == null) {
                throw new AuraHandledException('Wallet not found for ID: ' + walletId);
            }
            
            return wallet;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled
    public static Integer getNextAccountIndex(String walletSetId) {
        try {
            List<Wallet__c> wallets = walletSelector.getWalletsByWalletSetId(walletSetId);
            // Find the first unused index (gap or next after highest)
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
        } catch (Exception e) {            
            throw new AuraHandledException('Error getting next account index: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled
    public static String isIndexValid(String walletSetId, Integer accountIndex) {
        try {
            // Check if the index is already used
            List<Wallet__c> wallets = WalletSelector.getWalletByWalletSetAndAccountIndex(walletSetId, accountIndex);

            if (!wallets.isEmpty()) {
                String errorMessage = 'Account ' + accountIndex + ' already exists for this Wallet Set. Try a different wallet set or Account Index.';
                return errorMessage;
            }
            return null;
        } catch (Exception e) {            
            throw new AuraHandledException('Error validating account index: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getEncryptedSeedPhrase(Id walletSetId) {
        try {            
            return EncryptedDataService.getEncryptedSeedPhrase(walletSetId);
        } catch (Exception e) {            
            throw new AuraHandledException('Failed to get seed phrase: ' + e.getMessage());
        }
    }

    /**
     * Enhanced method to check if address has any transactions by calling Blockfrost directly
     * This avoids the DML + callout issue by doing only callouts
     */
    @AuraEnabled
    public static Map<String, Object> checkAddressUsageOnly(String address) {
        try {
            // Call Blockfrost directly to check if address is used
            Boolean isUsed = BlockfrostService.isAddressUsed(address);
            
            // Get more detailed information if the address is used
            Map<String, Object> result = new Map<String, Object>{
                'address' => address,
                'isUsed' => isUsed,
                'hasAssets' => false,
                'hasTransactions' => false,
                'checkMethod' => 'blockfrost_direct'
            };
            
            if (isUsed) {
                // Try to get more details about what makes it "used"
                String utxosJson = BlockfrostService.getAddressUtxos(address);
                List<Object> utxoList = (List<Object>) JSON.deserializeUntyped(utxosJson);
                result.put('hasAssets', !utxoList.isEmpty());
                
                String transactionsJson = BlockfrostService.getAddressTransactions(address);
                List<Object> transactionList = (List<Object>) JSON.deserializeUntyped(transactionsJson);
                result.put('hasTransactions', !transactionList.isEmpty());
            }
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to check address usage: ' + e.getMessage());
        }
    }

    /**
     * Bulk create UTXO addresses without syncing (to avoid DML + callout issues)
     */
    @AuraEnabled
    public static Map<String, Object> createUTXOAddressesBulk(String walletId, List<UTXOAddressData> receivingAddresses, List<UTXOAddressData> changeAddresses) {
        try {
            // Validate inputs
            if (receivingAddresses == null || changeAddresses == null) {
                throw new AuraHandledException('Address lists cannot be null');
            }

            List<UTXO_Address__c> allAddresses = new List<UTXO_Address__c>();
            List<Map<String, Object>> receivingResults = new List<Map<String, Object>>();
            List<Map<String, Object>> changeResults = new List<Map<String, Object>>();

            // Process receiving addresses
            for (UTXOAddressData addr : receivingAddresses) {
                UTXO_Address__c utxoRecord = new UTXO_Address__c(
                    Wallet__c = walletId,
                    Address__c = addr.address,
                    Index__c = addr.index,
                    Is_Used__c = false,
                    Public_Key__c = addr.publicKey,
                    Payment_Key_Hash__c = addr.paymentKeyHash,
                    Path__c = addr.path,
                    Private_Key__c = String.isNotBlank(addr.privateKey) ? addr.privateKey : null,
                    Type__c = '0'
                );
                allAddresses.add(utxoRecord);
                
                receivingResults.add(new Map<String, Object>{
                    'address' => addr.address,
                    'index' => addr.index,
                    'type' => '0',
                    'typeLabel' => 'Receiving'
                });
            }

            // Process change addresses  
            for (UTXOAddressData addr : changeAddresses) {
                UTXO_Address__c utxoRecord = new UTXO_Address__c(
                    Wallet__c = walletId,
                    Address__c = addr.address,
                    Index__c = addr.index,
                    Is_Used__c = false,
                    Public_Key__c = addr.publicKey,
                    Payment_Key_Hash__c = addr.paymentKeyHash,
                    Path__c = addr.path,
                    Private_Key__c = String.isNotBlank(addr.privateKey) ? addr.privateKey : null,
                    Type__c = '1'
                );
                allAddresses.add(utxoRecord);
                
                changeResults.add(new Map<String, Object>{
                    'address' => addr.address,
                    'index' => addr.index,
                    'type' => '1',
                    'typeLabel' => 'Change'
                });
            }

            // Insert all addresses in bulk
            if (!allAddresses.isEmpty()) {
                SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, allAddresses);
                insert decision.getRecords();
                
                // Update results with the inserted IDs
                for (Integer i = 0; i < receivingAddresses.size(); i++) {
                    receivingResults[i].put('utxoAddressId', decision.getRecords()[i].Id);
                }
                for (Integer i = 0; i < changeAddresses.size(); i++) {
                    changeResults[i].put('utxoAddressId', decision.getRecords()[receivingAddresses.size() + i].Id);
                }
            }

            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'walletId' => walletId,
                'receivingAddresses' => receivingResults,
                'changeAddresses' => changeResults,
                'statistics' => new Map<String, Object>{
                    'totalReceivingCreated' => receivingAddresses.size(),
                    'totalChangeCreated' => changeAddresses.size()
                }
            };
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error creating UTXO addresses in bulk: ' + e.getMessage());
        }
    }

    /**
     * Verify user-entered seed phrase against the encrypted seed phrase stored in the database
     */
    @AuraEnabled
    public static Boolean verifySeedPhrase(String walletSetId, String userSeedPhrase) {
        Wallet_Set__c walletSet = [
                SELECT Id, Seed_Phrase__c
                FROM Wallet_Set__c
                WHERE Id = :walletSetId
                LIMIT 1
            ];
            if (walletSet == null) {
                throw new AuraHandledException('Wallet Set not found');
            }

            if (String.isBlank(walletSet.Seed_Phrase__c)) {
                throw new AuraHandledException('Seed phrase not found for this Wallet Set');
            }

            try {
                return DataEncryptor.verifyHmac(userSeedPhrase, walletSet.Seed_Phrase__c);
            } catch (Exception e) {
                return false;
            }
    }
}