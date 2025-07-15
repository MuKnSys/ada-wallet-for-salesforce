public with sharing class UTXOController {
    
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

    // Core wallet and address methods
    @AuraEnabled(cacheable=true)
    public static String getEncryptedSeedPhrase(Id walletSetId) {
        try {            
            return EncryptedDataService.getEncryptedSeedPhrase(walletSetId);
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

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getUTXOAddresses(String walletId) {
        try {
            validateWalletId(walletId);
            return UTXOAddressSelector.getAddressesByWalletId(walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO addresses: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getAllWalletAddresses(String walletId) {
        try {
            validateWalletId(walletId);
            return UTXOAddressSelector.getAddressesByWalletId(walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet addresses: ' + e.getMessage());
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
            validateWalletId(walletId);
            if (String.isBlank(type) || !(type == '0' || type == '1')) {
                throw new AuraHandledException('Type must be "0" (receiving) or "1" (change)');
            }

            List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getLastUTXOAddressByType(walletId, type);

            if (utxoAddresses.isEmpty()) {
                return 0;
            }

            return (Integer)utxoAddresses[0].Index__c + 1;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving next UTXO index: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String addReceivingUTXOAddress(String walletId, UTXOAddress receivingAddress) {
        try {
            validateWalletId(walletId);
            validateAddress(receivingAddress, 'receiving');

            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = receivingAddress.address,
                Index__c = receivingAddress.index,
                Public_Key__c = receivingAddress.publicKey,
                Payment_Key_Hash__c = receivingAddress.paymentKeyHash,
                Path__c = receivingAddress.path,
                Private_Key__c = String.isNotBlank(receivingAddress.privateKey) ? receivingAddress.privateKey : null,
                Type__c = '0'
            );

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
            validateWalletId(walletId);
            validateAddress(changeAddress, 'change');

            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = changeAddress.address,
                Index__c = changeAddress.index,
                Public_Key__c = changeAddress.publicKey,
                Payment_Key_Hash__c = changeAddress.paymentKeyHash,
                Path__c = changeAddress.path,
                Private_Key__c = String.isNotBlank(changeAddress.privateKey) ? changeAddress.privateKey : null,
                Type__c = '1'
            );

            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<UTXO_Address__c>{utxoRecord});
            insert decision.getRecords();
            
            return decision.getRecords()[0].Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error adding change UTXO address: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getFirstUnusedReceivingAddress(String walletId) {
        try {
            validateWalletId(walletId);
            List<UTXO_Address__c> addrs = UTXOAddressSelector.getFirstUnusedAddressByType(walletId, '0');
            return addrs.isEmpty() ? null : addrs[0].Address__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching unused receiving address: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Asset__c> getAllUtxoAssetsForWallet(String walletId) {
        try {
            validateWalletId(walletId);
            return UTXOAssetSelector.getAssetsByWalletId(walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO assets: ' + e.getMessage());
        }
    }

    // Transaction methods
    @AuraEnabled
    public static String createMultiAssetOutboundTransaction(String walletId, String toAddress, List<Map<String, Object>> assets, String memo) {
        try {
            validateWalletId(walletId);
            if (String.isBlank(toAddress)) {
                throw new AuraHandledException('To Address is required');
            }
            if (assets == null || assets.isEmpty()) {
                throw new AuraHandledException('At least one asset is required');
            }

            Outbound_Transaction__c txRecord = new Outbound_Transaction__c(
                Wallet__c = walletId,
                To_Address__c = toAddress,
                Approved__c = OutboundTransactionHelper.APPROVAL_STATUS_NOT_APPROVED,
                Transaction_Status__c = OutboundTransactionHelper.STATUS_READY_TO_SIGN,
                Memo__c = String.isBlank(memo) ? null : memo
            );
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<Outbound_Transaction__c>{txRecord});
            insert decision.getRecords();
            Id outboundId = decision.getRecords()[0].Id;

            List<Outbound_Transaction_Line__c> lines = new List<Outbound_Transaction_Line__c>();
            for (Map<String, Object> assetMap : assets) {
                Decimal lineAmount;
                String lineAsset;
                try {
                    lineAmount = Decimal.valueOf(String.valueOf(assetMap.get('amount')));
                } catch (Exception e) {
                    continue;
                }
                lineAsset = String.valueOf(assetMap.get('asset'));
                if (String.isBlank(lineAsset)) {
                    continue;
                }
                lines.add(new Outbound_Transaction_Line__c(
                    Outbound_Transaction__c = outboundId,
                    Amount__c = lineAmount,
                    Asset__c = lineAsset
                ));
            }
            if (!lines.isEmpty()) {
                SObjectAccessDecision lineDecision = Security.stripInaccessible(AccessType.CREATABLE, lines);
                insert lineDecision.getRecords();
            }

            return outboundId;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating multi-asset outbound transaction: ' + e.getMessage());
        }
    }

    
    @AuraEnabled
    public static Map<String, Object> syncAssetsAndTransactions(Id utxoAddressId) {
        try {
            return UTXOHelper.syncAssetsAndTransactions(utxoAddressId);
        } catch (Exception e) {
            throw new AuraHandledException('Error syncing assets and transactions: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void setAddressesUsed(List<Id> utxoAddressIds) {
        try {
            UTXOHelper.setAddressesUsed(utxoAddressIds);
        } catch (Exception e) {
            throw new AuraHandledException('Error setting addresses as used: ' + e.getMessage());
        }
    }

    // Helper methods
    private static void validateWalletId(String walletId) {
        if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
            throw new AuraHandledException('Invalid Wallet ID');
        }
    }


    private static void validateAddress(UTXOAddress address, String addressType) {
        if (address == null) {
            throw new AuraHandledException(addressType + ' address cannot be null');
        }
        if (address.index == null || String.isBlank(address.address) || 
            String.isBlank(address.publicKey) || String.isBlank(address.paymentKeyHash) || 
            String.isBlank(address.path)) {
            throw new AuraHandledException('Invalid ' + addressType + ' address data for index ' + address.index);
        }
    }
}