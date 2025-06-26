public with sharing class UTXOController {
    /**
     * Inner class for UTXO Address data
     */
    public class UTXOAddress {
        @AuraEnabled public Integer index { get; set; }
        @AuraEnabled public String publicKey { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String stakingKeyHash { get; set; }
        @AuraEnabled public String path { get; set; }
        @AuraEnabled public String stakePath { get; set; }
        @AuraEnabled public String privateKey { get; set; }
    }

    /**
     * Inner class for Transaction wrapper data
     */
    public class TransactionWrapper {
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String txHash { get; set; }
        @AuraEnabled public Datetime receivedAt { get; set; }
    }

    /**
     * Inner class for Token count data
     */
    public class TokenCount {
        @AuraEnabled public String symbol;
        @AuraEnabled public Decimal amount;
    }

    /**
     * Inner class for Asset token summary data
     */
    public class AssetTokenSummary {
        @AuraEnabled public Decimal ada;
        @AuraEnabled public List<TokenCount> tokens;
    }

    @AuraEnabled(cacheable=true)
    public static String getDecryptedSeedPhrase(Id walletSetId) {
        try {            
            return EncryptedDataService.getDecryptedSeedPhrase(walletSetId);
        } catch (Exception e) {            
            throw new AuraHandledException('Failed to get seed phrase: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Wallet__c getWallet(String walletId) {
        try {
            return WalletSelector.getWalletById(walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void createUTXOAddresses(String walletId, List<UTXOAddress> receivingAddresses, List<UTXOAddress> changeAddresses) {
        try {
            // Validate inputs
            if (receivingAddresses == null || changeAddresses == null) {
                throw new AuraHandledException('Address lists cannot be null');
            }

            // Prepare UTXO_Address__c records
            List<UTXO_Address__c> utxoRecords = new List<UTXO_Address__c>();

            // Process receiving addresses (Type__c = 0)
            utxoRecords.addAll(processReceivingAddresses(walletId, receivingAddresses));

            // Process change addresses (Type__c = 1)
            utxoRecords.addAll(processChangeAddresses(walletId, changeAddresses));

            // Insert records with security enforcement
            if (!utxoRecords.isEmpty()) {
                SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, utxoRecords);
                insert decision.getRecords();
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error creating UTxO addresses: ' + e.getMessage());
        }
    }

    /**
     * Process receiving addresses and return UTXO_Address__c records
     */
    private static List<UTXO_Address__c> processReceivingAddresses(String walletId, List<UTXOAddress> receivingAddresses) {
        List<UTXO_Address__c> records = new List<UTXO_Address__c>();
        
        for (UTXOAddress addr : receivingAddresses) {
            if (addr.index == null || String.isBlank(addr.address) || String.isBlank(addr.publicKey) || 
                String.isBlank(addr.stakingKeyHash) || String.isBlank(addr.path)) {
                throw new AuraHandledException('Invalid receiving address data for index ' + addr.index);
            }
            
            // Store private key without encryption
            String privateKey = String.isNotBlank(addr.privateKey) ? addr.privateKey : null;
            
            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = addr.address,
                Index__c = addr.index,
                Public_Key__c = addr.publicKey,
                Staking_Key_Hash__c = addr.stakingKeyHash,
                Path__c = addr.path,
                Private_Key__c = privateKey,
                Type__c = '0' // Receiving address
            );
            
            records.add(utxoRecord);
        }
        
        return records;
    }

    /**
     * Process change addresses and return UTXO_Address__c records
     */
    private static List<UTXO_Address__c> processChangeAddresses(String walletId, List<UTXOAddress> changeAddresses) {
        List<UTXO_Address__c> records = new List<UTXO_Address__c>();
        
        for (UTXOAddress addr : changeAddresses) {
            if (addr.index == null || String.isBlank(addr.address) || String.isBlank(addr.publicKey) || 
                String.isBlank(addr.stakingKeyHash) || String.isBlank(addr.path)) {
                throw new AuraHandledException('Invalid change address data for index ' + addr.index);
            }
            
            // Store private key without encryption
            String privateKey = String.isNotBlank(addr.privateKey) ? addr.privateKey : null;
            
            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = addr.address,
                Index__c = addr.index,
                Public_Key__c = addr.publicKey,
                Staking_Key_Hash__c = addr.stakingKeyHash,
                Path__c = addr.path,
                Private_Key__c = privateKey,
                Type__c = '1' // Change address
            );
            
            records.add(utxoRecord);
        }
        
        return records;
    }

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getUTXOAddresses(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            return UTXOAddressSelector.getUTXOAddressesByWalletId(walletId, null);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO addresses: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getUTXOAddressesWithAssets(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            
            // Get all addresses for this wallet
            List<UTXO_Address__c> allAddresses = [
                SELECT Id, Address__c, Index__c, Public_Key__c, Staking_Key_Hash__c, 
                       Path__c, Private_Key__c, Type__c, Name
                FROM UTXO_Address__c 
                WHERE Wallet__c = :walletId
                ORDER BY Index__c ASC
            ];
            
            // Filter out addresses without private keys in Apex
            List<UTXO_Address__c> filteredAddresses = new List<UTXO_Address__c>();
            for (UTXO_Address__c addr : allAddresses) {
                if (addr.Private_Key__c != null) {
                    filteredAddresses.add(addr);
                }
            }
            
            // Get addresses that have assets
            Set<Id> addressesWithAssets = new Set<Id>();
            for (UTXO_Asset__c asset : [
                SELECT UTXO_Address__c 
                FROM UTXO_Asset__c 
                WHERE UTXO_Address__c IN :filteredAddresses
            ]) {
                addressesWithAssets.add(asset.UTXO_Address__c);
            }
            
            // Filter addresses that have both private keys and assets
            List<UTXO_Address__c> result = new List<UTXO_Address__c>();
            for (UTXO_Address__c addr : allAddresses) {
                if (addressesWithAssets.contains(addr.Id)) {
                    result.add(addr);
                }
            }
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO addresses with assets: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<UTXOAddressSelector.UTXOAddressWithDecryptedKey> getUTXOAddressesWithDecryptedKeys(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            return UTXOAddressSelector.getUTXOAddressesWithDecryptedKeysByWalletId(walletId, null);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO addresses with decrypted keys: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static UTXOAddressSelector.UTXOAddressWithDecryptedKey getUTXOAddressWithDecryptedKeyById(String utxoAddressId) {
        try {
            if (String.isBlank(utxoAddressId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', utxoAddressId)) {
                throw new AuraHandledException('Invalid UTXO Address ID');
            }
            return UTXOAddressSelector.getUTXOAddressWithDecryptedKeyById(utxoAddressId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO address with decrypted key: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getUserPermissions() {
        try {
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
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving user permissions: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Integer getNextUTXOIndex(String walletId, String type) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (String.isBlank(type) || !(type == '0' || type == '1')) {
                throw new AuraHandledException('Type must be "0" (receiving) or "1" (change)');
            }

            // Query UTXO_Address__c records for the given Wallet__c and Type__c
            List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getLastUTXOAddressByType(walletId, type);

            // If no records are found, start at index 0
            if (utxoAddresses.isEmpty()) {
                return 0;
            }

            // Get the highest Index__c and return the next index
            Integer highestIndex = (Integer)utxoAddresses[0].Index__c;
            Integer nextIndex = highestIndex + 1;
            return nextIndex;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving next UTXO index: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String addReceivingUTXOAddress(String walletId, UTXOAddress receivingAddress) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (receivingAddress == null) {
                throw new AuraHandledException('Receiving address cannot be null');
            }
            if (receivingAddress.index == null || String.isBlank(receivingAddress.address) || 
                String.isBlank(receivingAddress.publicKey) || String.isBlank(receivingAddress.stakingKeyHash) || 
                String.isBlank(receivingAddress.path)) {
                throw new AuraHandledException('Invalid receiving address data for index ' + receivingAddress.index);
            }

            // Store private key without encryption
            String privateKey = String.isNotBlank(receivingAddress.privateKey) ? receivingAddress.privateKey : null;

            // Create a new UTXO_Address__c record for the receiving address (Type__c = 0)
            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = receivingAddress.address,
                Index__c = receivingAddress.index,
                Public_Key__c = receivingAddress.publicKey,
                Staking_Key_Hash__c = receivingAddress.stakingKeyHash,
                Path__c = receivingAddress.path,
                Private_Key__c = privateKey,
                Type__c = '0' // Receiving address
            );

            // Insert the record with security enforcement
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<UTXO_Address__c>{utxoRecord});
            insert decision.getRecords();
            
            return decision.getRecords()[0].Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error adding receiving UTXO address: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String addChangeUTXOAddress(String walletId, UTXOAddress changeAddress) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (changeAddress == null) {
                throw new AuraHandledException('Change address cannot be null');
            }
            if (changeAddress.index == null || String.isBlank(changeAddress.address) || 
                String.isBlank(changeAddress.publicKey) || String.isBlank(changeAddress.stakingKeyHash) || 
                String.isBlank(changeAddress.path)) {
                throw new AuraHandledException('Invalid change address data for index ' + changeAddress.index);
            }

            // Store private key without encryption
            String privateKey = String.isNotBlank(changeAddress.privateKey) ? changeAddress.privateKey : null;

            // Create a new UTXO_Address__c record for the change address (Type__c = 1)
            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = changeAddress.address,
                Index__c = changeAddress.index,
                Public_Key__c = changeAddress.publicKey,
                Staking_Key_Hash__c = changeAddress.stakingKeyHash,
                Path__c = changeAddress.path,
                Private_Key__c = privateKey,
                Type__c = '1' // Change address
            );

            // Insert the record with security enforcement
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<UTXO_Address__c>{utxoRecord});
            insert decision.getRecords();
            
            return decision.getRecords()[0].Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error adding change UTXO address: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TransactionWrapper> getReceivedTransactions(String walletId) {
        return new List<TransactionWrapper>();
    }

    @AuraEnabled(cacheable=true)
    public static Integer getUTXOAddressCountWithAssets(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }

            String soql = 'SELECT COUNT() FROM UTXO_Address__c WHERE Wallet__c = :walletId AND Id IN (SELECT UTXO_Address__c FROM UTXO_Asset__c WHERE UTXO_Address__c != NULL)';
            Integer cnt = Database.countQuery(soql);
            return cnt;
        } catch (Exception e) {
            throw new AuraHandledException('Error counting UTXO addresses with assets: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static AssetTokenSummary getAssetTokenSummary(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }

            List<AggregateResult> results = [
                SELECT Unit__c unit, SUM(Amount__c) total
                FROM UTXO_Asset__c
                WHERE UTXO_Address__r.Wallet__c = :walletId
                GROUP BY Unit__c
            ];

            AssetTokenSummary summary = new AssetTokenSummary();
            summary.ada = 0;
            summary.tokens = new List<TokenCount>();

            for (AggregateResult ar : results) {
                String unit = (String) ar.get('unit');
                Decimal amount = (Decimal) ar.get('total');
                if (unit == 'lovelace' || unit == 'ADA') {
                    summary.ada = amount;
                } else {
                    TokenCount tc = new TokenCount();
                    tc.symbol = unit;
                    tc.amount = amount;
                    summary.tokens.add(tc);
                }
            }

            return summary;
        } catch (Exception e) {
            throw new AuraHandledException('Error building asset summary: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static AssetTokenSummary getAssetTokenSummaryNoCache(String walletId) {
        // Wrapper to bypass Lightning Data Service cache
        return getAssetTokenSummary(walletId);
    }

    @AuraEnabled(cacheable=true)
    public static String getFirstUnusedReceivingAddress(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            List<UTXO_Address__c> addrs = [
                SELECT Address__c, Index__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId AND Type__c = '0' AND Id NOT IN (
                    SELECT UTXO_Address__c FROM UTXO_Asset__c WHERE UTXO_Address__c != NULL
                )
                ORDER BY Index__c
                LIMIT 1
            ];
            if (addrs.isEmpty()) {
                return null;
            }
            return addrs[0].Address__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching unused receiving address: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Asset__c> getAllUtxoAssetsForWallet(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }

            return [
                SELECT Id, UTXO_Address__c, Unit__c, Amount__c, Name__c, Asset_Name__c, 
                       Decimals__c, Policy_ID__c, Fingerprint__c,
                       UTXO_Address__r.Address__c, UTXO_Address__r.Index__c
                FROM UTXO_Asset__c
                WHERE UTXO_Address__r.Wallet__c = :walletId
                ORDER BY UTXO_Address__r.Index__c, Unit__c
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO assets: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean hasUTXOPrivateKey(String utxoAddressId) {
        try {
            if (String.isBlank(utxoAddressId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', utxoAddressId)) {
                throw new AuraHandledException('Invalid UTXO Address ID');
            }

            // Query the UTXO Address to check if Private_Key__c is populated
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Id, Private_Key__c
                FROM UTXO_Address__c
                WHERE Id = :utxoAddressId
                LIMIT 1
            ];

            if (utxoAddresses.isEmpty()) {
                throw new AuraHandledException('UTXO Address not found');
            }

            // Return true if Private_Key__c is not null and not empty
            return String.isNotBlank(utxoAddresses[0].Private_Key__c);
        } catch (Exception e) {
            throw new AuraHandledException('Error checking UTXO private key: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String createOutboundTransaction(String walletId, String toAddress, String amount) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (String.isBlank(toAddress)) {
                throw new AuraHandledException('To Address is required');
            }
            if (String.isBlank(amount)) {
                throw new AuraHandledException('Amount is required');
            }

            Decimal amountDecimal;
            try {
                amountDecimal = Decimal.valueOf(amount);
            } catch (Exception e) {
                throw new AuraHandledException('Invalid amount format');
            }

            if (amountDecimal <= 0) {
                throw new AuraHandledException('Amount must be greater than 0');
            }

            // Create outbound transaction record
            Outbound_Transaction__c txRecord = new Outbound_Transaction__c(
                Wallet__c = walletId,
                To_Address__c = toAddress,
                Amount__c = amountDecimal,
                Approved__c = 'Not Approved',
                Transaction_Status__c = 'New'
            );

            // Insert the record with security enforcement
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<Outbound_Transaction__c>{txRecord});
            insert decision.getRecords();

            return decision.getRecords()[0].Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating outbound transaction: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String getDecryptedUTXOPrivateKey(String utxoAddressId) {
        try {
            if (String.isBlank(utxoAddressId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', utxoAddressId)) {
                throw new AuraHandledException('Invalid UTXO Address ID');
            }

            // Query the UTXO Address to get the private key
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Id, Private_Key__c
                FROM UTXO_Address__c
                WHERE Id = :utxoAddressId
                LIMIT 1
            ];

            if (utxoAddresses.isEmpty()) {
                throw new AuraHandledException('UTXO Address not found');
            }

            UTXO_Address__c utxoAddress = utxoAddresses[0];

            if (String.isBlank(utxoAddress.Private_Key__c)) {
                throw new AuraHandledException('Private key not found for this UTXO address');
            }

            // Since we're storing private keys unencrypted, return directly
            return utxoAddress.Private_Key__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO private key: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static UTXO_Address__c getFirstUnusedChangeAddressWithNoAssets(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }

            List<UTXO_Address__c> changeAddresses = [
                SELECT Id, Address__c, Index__c, Public_Key__c, Staking_Key_Hash__c, 
                       Path__c, Private_Key__c, Type__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId 
                AND Type__c = '1' 
                AND Id NOT IN (
                    SELECT UTXO_Address__c 
                    FROM UTXO_Asset__c 
                    WHERE UTXO_Address__c != NULL
                )
                ORDER BY Index__c
                LIMIT 1
            ];

            return changeAddresses.isEmpty() ? null : changeAddresses[0];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving unused change address: ' + e.getMessage());
        }
    }
}