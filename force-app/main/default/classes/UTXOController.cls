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

    public class TransactionWrapper {
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String txHash { get; set; }
        @AuraEnabled public Datetime receivedAt { get; set; }
    }

    public class TokenCount {
        @AuraEnabled public String symbol;
        @AuraEnabled public Decimal amount;
    }

    public class AssetTokenSummary {
        @AuraEnabled public Decimal ada;
        @AuraEnabled public List<TokenCount> tokens;
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
            return UTXOAddressSelector.getUTXOAddressesByWalletId(walletId, null);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO addresses: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getAllWalletAddresses(String walletId) {
        try {
            validateWalletId(walletId);
            
            return [
                SELECT Id, Address__c, Index__c, Type__c, Path__c, 
                       Private_Key__c, Public_Key__c, Payment_Key_Hash__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
                ORDER BY Type__c, Index__c
            ];
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
            List<UTXO_Address__c> addrs = [
                SELECT Address__c, Index__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
                  AND Type__c = '0'
                  AND (Is_Used__c = false OR Is_Used__c = null)
                ORDER BY Index__c
                LIMIT 1
            ];
            return addrs.isEmpty() ? null : addrs[0].Address__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching unused receiving address: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Asset__c> getAllUtxoAssetsForWallet(String walletId) {
        try {
            validateWalletId(walletId);

            return [
                SELECT Id, UTXO_Address__c, Asset__c, Amount__c, Name__c, 
                       Decimals__c, Policy_ID__c, Fingerprint__c,
                       UTXO_Address__r.Address__c, UTXO_Address__r.Index__c
                FROM UTXO_Asset__c
                WHERE UTXO_Address__r.Wallet__c = :walletId
                ORDER BY UTXO_Address__r.Index__c, Asset__c
            ];
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
                Approved__c = 'Not Approved',
                Transaction_Status__c = 'Ready to Sign',
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

    @AuraEnabled(cacheable=true)
    public static List<Outbound_Transaction_Line__c> getTransactionLinesForOutbound(String outboundTransactionId) {
        try {
            validateId(outboundTransactionId, 'Outbound Transaction ID');
            return [
                SELECT Id, Amount__c, Asset__c
                FROM Outbound_Transaction_Line__c
                WHERE Outbound_Transaction__c = :outboundTransactionId
                ORDER BY Id
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching transaction lines: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Outbound_Transaction__c getOutboundTransaction(String outboundTransactionId) {
        try {
            validateId(outboundTransactionId, 'Outbound Transaction ID');
            List<Outbound_Transaction__c> results = [
                SELECT Id, To_Address__c, Wallet__c, Memo__c
                FROM Outbound_Transaction__c
                WHERE Id = :outboundTransactionId
                LIMIT 1
            ];
            
            if (results.isEmpty()) {
                throw new AuraHandledException('Outbound Transaction not found');
            }
            
            return results[0];
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to fetch Outbound Transaction: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateOutboundTransactionWithSignedCbor(String recordId, String signedCbor) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }
            if (String.isBlank(signedCbor)) {
                throw new AuraHandledException('Signed CBOR is required');
            }
            List<Outbound_Transaction__c> txList = [
                SELECT Id, Signed_Transaction_CBOR__c, Transaction_Status__c, Memo__c
                FROM Outbound_Transaction__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (txList.isEmpty()) {
                throw new AuraHandledException('Outbound Transaction not found');
            }
            Outbound_Transaction__c tx = txList[0];
            tx.Signed_Transaction_CBOR__c = signedCbor;
            tx.Transaction_Status__c = 'Ready to Send';
            update tx;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating outbound transaction: ' + e.getMessage());
        }
    }

    // Helper methods
    private static void validateWalletId(String walletId) {
        if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
            throw new AuraHandledException('Invalid Wallet ID');
        }
    }

    private static void validateId(String id, String idType) {
        if (String.isBlank(id) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', id)) {
            throw new AuraHandledException('Invalid ' + idType);
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