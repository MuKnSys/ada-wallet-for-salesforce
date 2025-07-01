// Import BlockfrostService for transaction submission
// Note: BlockfrostService is already available in the same namespace

public with sharing class TransactionController {
    
    /**
     * Inner class for UTXO Address data
     */
    public class UTXOAddress {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public Integer addressIndex { get; set; }
        @AuraEnabled public String addressType { get; set; }
        @AuraEnabled public String path { get; set; }
        @AuraEnabled public String privateKey { get; set; }
        @AuraEnabled public String publicKey { get; set; }
        @AuraEnabled public String stakingKeyHash { get; set; }
        @AuraEnabled public List<UTXOAsset> assets { get; set; }
        
        public UTXOAddress() {
            this.assets = new List<UTXOAsset>();
        }
    }
    
    /**
     * Inner class for UTXO Asset data
     */
    public class UTXOAsset {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String unit { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String assetName { get; set; }
        @AuraEnabled public String displayName { get; set; }
        @AuraEnabled public Integer decimals { get; set; }
        @AuraEnabled public String policyId { get; set; }
        @AuraEnabled public String fingerprint { get; set; }
    }
    
    /**
     * Calculate minimum ADA required for a UTXO with multi-assets
     * @param multiAsset Map of policy ID to asset name/amount mapping
     * @param protocolParams Map containing min_utxo and coins_per_utxo_size parameters
     * @return Minimum ADA amount in lovelace
     */
    @AuraEnabled
    public static Integer calculateMinAda(Map<String, Map<String, Integer>> multiAsset, Map<String, Object> protocolParams) {
        try {
            Integer minUtxo = (protocolParams.containsKey('min_utxo') && protocolParams.get('min_utxo') != null)
                ? Integer.valueOf(String.valueOf(protocolParams.get('min_utxo')))
                : 4310;
            Integer coinsPerUtxoByte = (protocolParams.containsKey('coins_per_utxo_size') && protocolParams.get('coins_per_utxo_size') != null)
                ? Integer.valueOf(String.valueOf(protocolParams.get('coins_per_utxo_size')))
                : 4310;
            Integer baseBytes = 160; // Approximate base size of a UTXO without assets
            Integer additionalBytes = 0;

            if (multiAsset != null && !multiAsset.isEmpty()) {
                for (String policy : multiAsset.keySet()) {
                    Map<String, Integer> assets = multiAsset.get(policy);
                    if (assets != null) {
                        for (String assetName : assets.keySet()) {
                            // 8 bytes for asset entry + asset name length
                            additionalBytes += 8 + assetName.length();
                        }
                    }
                }
            }

            Integer totalBytes = baseBytes + additionalBytes;
            return Integer.valueOf(Math.ceil((Decimal.valueOf(totalBytes) * coinsPerUtxoByte) / 8));
        } catch (Exception e) {
            throw new AuraHandledException('Error calculating minimum ADA: ' + e.getMessage());
        }
    }

    /**
     * Calculate minimum ADA from UTXO amount array (Blockfrost format)
     * @param amountArrayJson JSON string of amount array from Blockfrost
     * @param protocolParamsJson JSON string of protocol parameters
     * @return Minimum ADA amount in lovelace
     */
    @AuraEnabled
    public static Integer calculateMinAdaFromAmount(String amountArrayJson, String protocolParamsJson) {
        try {
            // Parse protocol parameters
            Map<String, Object> protocolParams = (Map<String, Object>) JSON.deserializeUntyped(protocolParamsJson);
            
            // Parse amount array
            List<Object> amountArray = (List<Object>) JSON.deserializeUntyped(amountArrayJson);
            
            // Create multi-asset structure
            Map<String, Map<String, Integer>> multiAsset = new Map<String, Map<String, Integer>>();
            
            for (Object assetObj : amountArray) {
                Map<String, Object> asset = (Map<String, Object>) assetObj;
                String unit = String.valueOf(asset.get('unit'));
                
                if (unit == 'lovelace') {
                    continue; // Skip ADA/lovelace as it's handled separately
                }
                
                // Extract policy ID and asset name from unit
                // Unit format: policyId + assetName (hex encoded)
                if (unit.length() >= 56) { // Policy ID is 28 bytes = 56 hex chars
                    String policyId = unit.substring(0, 56);
                    String assetName = unit.substring(56);
                    Integer quantity = Integer.valueOf(String.valueOf(asset.get('quantity')));
                    
                    if (!multiAsset.containsKey(policyId)) {
                        multiAsset.put(policyId, new Map<String, Integer>());
                    }
                    multiAsset.get(policyId).put(assetName, quantity);
                }
            }
            
            return calculateMinAda(multiAsset, protocolParams);
        } catch (Exception e) {
            throw new AuraHandledException('Error calculating minimum ADA from amount: ' + e.getMessage());
        }
    }

    /**
     * Get all UTXO addresses for a given wallet ID with their associated assets
     * @param walletId The ID of the wallet to query UTXO addresses for
     * @return List of UTXO address records with their assets
     */
    @AuraEnabled
    public static List<UTXOAddress> getWalletUTXOs(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }

            // Query all UTXO addresses for the wallet with all cryptographic fields
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Id, Address__c, Index__c, Type__c, Path__c, 
                       Private_Key__c, Public_Key__c, Staking_Key_Hash__c,
                       (SELECT Id, Unit__c, Amount__c, Name__c, Asset_Name__c, 
                               Decimals__c, Policy_ID__c, Fingerprint__c
                        FROM UTXO_Assets__r
                        WHERE Amount__c > 0
                        ORDER BY Unit__c)
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
                ORDER BY Type__c, Index__c
            ];

            // Convert to wrapper class
            List<UTXOAddress> utxoAddressList = new List<UTXOAddress>();
            for (UTXO_Address__c addr : utxoAddresses) {
                UTXOAddress utxoAddress = new UTXOAddress();
                utxoAddress.id = addr.Id;
                utxoAddress.address = addr.Address__c;
                utxoAddress.addressIndex = Integer.valueOf(addr.Index__c);
                utxoAddress.addressType = addr.Type__c;
                utxoAddress.path = addr.Path__c;
                utxoAddress.privateKey = addr.Private_Key__c;
                utxoAddress.publicKey = addr.Public_Key__c;
                utxoAddress.stakingKeyHash = addr.Staking_Key_Hash__c;
                
                // Add assets if any exist
                for (UTXO_Asset__c asset : addr.UTXO_Assets__r) {
                    UTXOAsset utxoAsset = new UTXOAsset();
                    utxoAsset.id = asset.Id;
                    utxoAsset.unit = asset.Unit__c;
                    utxoAsset.amount = asset.Amount__c;
                    utxoAsset.assetName = asset.Name__c;
                    utxoAsset.displayName = asset.Asset_Name__c;
                    utxoAsset.decimals = Integer.valueOf(asset.Decimals__c != null ? asset.Decimals__c : 0);
                    utxoAsset.policyId = asset.Policy_ID__c;
                    utxoAsset.fingerprint = asset.Fingerprint__c;
                    utxoAddress.assets.add(utxoAsset);
                }
                
                utxoAddressList.add(utxoAddress);
            }

            return utxoAddressList;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet UTXOs: ' + e.getMessage());
        }
    }

    /**
     * Update Outbound Transaction record with signed transaction CBOR
     * @param recordId The ID of the Outbound_Transaction__c record
     * @param signedTransactionCbor The signed transaction in CBOR hex format
     * @return Success message
     */
    @AuraEnabled
    public static String updateOutboundTransactionCbor(String recordId, String signedTransactionCbor) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            // Query the record to ensure it exists and user has access
            List<Outbound_Transaction__c> transactions = [
                SELECT Id, Signed_Transaction_CBOR__c, Transaction_Status__c
                FROM Outbound_Transaction__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (transactions.isEmpty()) {
                throw new AuraHandledException('Outbound Transaction record not found');
            }

            Outbound_Transaction__c outboundTransactionRecord = transactions[0];
            outboundTransactionRecord.Signed_Transaction_CBOR__c = signedTransactionCbor;
            
            // Set status based on whether CBOR is provided
            if (String.isBlank(signedTransactionCbor)) {
                // No CBOR - set to "Ready to Sign"
                outboundTransactionRecord.Transaction_Status__c = 'Ready to Sign';
            } else {
                // CBOR provided - set to "Ready to Send"
                outboundTransactionRecord.Transaction_Status__c = 'Ready to Send';
            }

            // Update the record with security enforcement
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, new List<Outbound_Transaction__c>{outboundTransactionRecord});
            update decision.getRecords();

            return 'Transaction CBOR updated successfully';
        } catch (Exception e) {
            throw new AuraHandledException('Error updating transaction CBOR: ' + e.getMessage());
        }
    }

    /**
     * Get the current signed transaction CBOR from an Outbound Transaction record
     * @param recordId The ID of the Outbound_Transaction__c record
     * @return The signed transaction CBOR or null if not found
     */
    @AuraEnabled
    public static String getOutboundTransactionCbor(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            List<Outbound_Transaction__c> transactions = [
                SELECT Id, Signed_Transaction_CBOR__c, Transaction_Status__c
                FROM Outbound_Transaction__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (transactions.isEmpty()) {
                return null;
            }

            return transactions[0].Signed_Transaction_CBOR__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving transaction CBOR: ' + e.getMessage());
        }
    }

    /**
     * Get Outbound Transaction record details
     * @param recordId The ID of the Outbound_Transaction__c record
     * @return Map containing transaction details
     */
    @AuraEnabled
    public static Map<String, Object> getOutboundTransactionDetails(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            List<Outbound_Transaction__c> transactions = [
                SELECT Id, Name, Wallet__c, To_Address__c, Amount__c, 
                       Transaction_Status__c, Approved__c, Signed_Transaction_CBOR__c,
                       Transaction_Hash__c, CreatedDate, LastModifiedDate
                FROM Outbound_Transaction__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (transactions.isEmpty()) {
                throw new AuraHandledException('Outbound Transaction record not found');
            }

            Outbound_Transaction__c tx = transactions[0];
            Map<String, Object> details = new Map<String, Object>{
                'id' => tx.Id,
                'name' => tx.Name,
                'walletId' => tx.Wallet__c,
                'toAddress' => tx.To_Address__c,
                'amount' => tx.Amount__c,
                'transactionStatus' => tx.Transaction_Status__c,
                'approved' => tx.Approved__c,
                'hasCbor' => !String.isBlank(tx.Signed_Transaction_CBOR__c),
                'cborLength' => String.isBlank(tx.Signed_Transaction_CBOR__c) ? 0 : tx.Signed_Transaction_CBOR__c.length() / 2,
                'transactionHash' => tx.Transaction_Hash__c,
                'createdDate' => tx.CreatedDate,
                'lastModifiedDate' => tx.LastModifiedDate
            };

            return details;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving transaction details: ' + e.getMessage());
        }
    }
} 