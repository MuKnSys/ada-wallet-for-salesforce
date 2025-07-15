// Import BlockfrostService for transaction submission
// Note: BlockfrostService is already available in the same namespace

public with sharing class TransactionController {
    
    // Inner classes for data structures
    public class UTXOAddress {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public Integer addressIndex { get; set; }
        @AuraEnabled public String addressType { get; set; }
        @AuraEnabled public String path { get; set; }
        @AuraEnabled public String privateKey { get; set; }
        @AuraEnabled public String publicKey { get; set; }
        @AuraEnabled public String paymentKeyHash { get; set; }
        @AuraEnabled public String xprv { get; set; }
        @AuraEnabled public String xpub { get; set; }
        @AuraEnabled public List<UTXOAsset> assets { get; set; }
        @AuraEnabled public Map<String, Object> balance { get; set; }
        @AuraEnabled public Map<String, Object> walletSummary { get; set; }
        @AuraEnabled public List<Object> utxos { get; set; }
        
        public UTXOAddress() {
            this.assets = new List<UTXOAsset>();
            this.balance = new Map<String, Object>();
            this.walletSummary = new Map<String, Object>();
            this.utxos = new List<Object>();
        }
    }
    
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

    @AuraEnabled
    public static String createOutboundTransaction(String walletId, String toAddress, String amount, String asset, String memo) {
        try {
            validateWalletId(walletId);
            if (String.isBlank(toAddress)) {
                throw new AuraHandledException('To Address is required');
            }
            if (String.isBlank(amount)) {
                throw new AuraHandledException('Amount is required');
            }
            if (String.isBlank(asset)) {
                throw new AuraHandledException('Asset is required');
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

            Outbound_Transaction_Line__c line = new Outbound_Transaction_Line__c(
                Outbound_Transaction__c = outboundId,
                Amount__c = amountDecimal,
                Asset__c = asset
            );
            SObjectAccessDecision lineDecision = Security.stripInaccessible(AccessType.CREATABLE, new List<Outbound_Transaction_Line__c>{line});
            insert lineDecision.getRecords();

            return outboundId;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating outbound transaction: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> loadWallet(String walletId) {
        validateWalletId(walletId);

        try {
            List<UTXO_Address__c> utxoAddresses = UTXOController.getAllWalletAddresses(walletId);

            List<Map<String, Object>> receivingAddresses = new List<Map<String, Object>>();
            List<Map<String, Object>> changeAddresses = new List<Map<String, Object>>();
            
            Decimal totalLovelace = 0;
            Integer addressesWithFunds = 0;
            Map<String, Decimal> assetTotals = new Map<String, Decimal>();
            
            for (UTXO_Address__c addr : utxoAddresses) {
                Map<String, Object> addressData = processAddress(addr);
                
                if ('0'.equals(addr.Type__c)) {
                    receivingAddresses.add(addressData);
                } else if ('1'.equals(addr.Type__c)) {
                    changeAddresses.add(addressData);
                }
                
                String balanceStr = (String) ((Map<String, Object>) addressData.get('balance')).get('lovelace');
                Decimal addressBalance = Decimal.valueOf(balanceStr);
                if (addressBalance > 0) {
                    totalLovelace += addressBalance;
                    addressesWithFunds++;
                }
                
                List<Object> utxos = (List<Object>) addressData.get('utxos');
                collectAssetTotals(utxos, assetTotals);
            }
            
            List<Map<String, Object>> assetsList = buildAssetsList(assetTotals);
            
            Map<String, Object> walletSummary = new Map<String, Object>{
                'totalBalance' => new Map<String, Object>{
                    'lovelace' => String.valueOf(totalLovelace),
                    'ada' => String.valueOf(totalLovelace / 1000000),
                    'assets' => assetsList
                },
                'totalAddresses' => utxoAddresses.size(),
                'addressesWithFunds' => addressesWithFunds
            };
            
            return new Map<String, Object>{
                'receivingAddresses' => receivingAddresses,
                'changeAddresses' => changeAddresses,
                'walletSummary' => walletSummary
            };
            
        } catch (Exception e) {
            throw new AuraHandledException('Error loading wallet: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=false)
    public static String getEpochParameters() {
        return BlockfrostService.getEpochParameters();
    }

    @AuraEnabled(cacheable=true)
    public static List<Outbound_Transaction_Line__c> getTransactionLinesForOutbound(String outboundTransactionId) {
        try {
            UTXOHelper.validateId(outboundTransactionId, 'Outbound Transaction ID');
            return OutboundTransactionLineSelector.getTransactionLinesByOutboundId(outboundTransactionId);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching transaction lines: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Outbound_Transaction__c getOutboundTransaction(String outboundTransactionId) {
        try {
            UTXOHelper.validateId(outboundTransactionId, 'Outbound Transaction ID');
            List<Outbound_Transaction__c> results = OutboundTransactionSelector.getOutboundTransactionById(outboundTransactionId);
            
            if (results.isEmpty()) {
                throw new AuraHandledException('Outbound Transaction not found');
            }
            
            return results[0];
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
            List<Outbound_Transaction__c> txList = OutboundTransactionSelector.getOutboundTransactionById(recordId);
            if (txList.isEmpty()) {
                throw new AuraHandledException('Outbound Transaction not found');
            }
            Outbound_Transaction__c tx = txList[0];
            tx.Signed_Transaction_CBOR__c = signedCbor;
            tx.Transaction_Status__c = OutboundTransactionHelper.STATUS_READY_TO_SEND;
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

    private static Map<String, Object> processAddress(UTXO_Address__c addr) {
        Decimal addressLovelace = 0;
        List<Object> addressUtxos = new List<Object>();
        
        try {
            String utxosJson = BlockfrostService.getAddressUtxos(addr.Address__c);
            List<Object> utxos = (List<Object>) JSON.deserializeUntyped(utxosJson);
            
            if (utxos != null && !utxos.isEmpty()) {
                addressUtxos = utxos;
                addressLovelace = calculateLovelaceFromUtxos(utxos);
            }
        } catch (Exception e) {
            // UTXOs will remain empty if API call fails
        }
        
        return new Map<String, Object>{
            'index' => Integer.valueOf(addr.Index__c),
            'address' => addr.Address__c,
            'paymentKeyHash' => addr.Payment_Key_Hash__c != null ? addr.Payment_Key_Hash__c : '',
            'privateKey' => addr.Private_Key__c != null ? addr.Private_Key__c : '',
            'keyMatch' => true,
            'utxos' => addressUtxos,
            'balance' => new Map<String, Object>{
                'lovelace' => String.valueOf(addressLovelace)
            },
            'transactionCount' => addressUtxos.size()
        };
    }
    
    private static Decimal calculateLovelaceFromUtxos(List<Object> utxos) {
        Decimal totalLovelace = 0;
        
        for (Object utxoObj : utxos) {
            Map<String, Object> utxo = (Map<String, Object>) utxoObj;
            List<Object> amounts = (List<Object>) utxo.get('amount');
            
            if (amounts != null) {
                for (Object amountObj : amounts) {
                    Map<String, Object> amount = (Map<String, Object>) amountObj;
                    String unit = (String) amount.get('unit');
                    String quantity = (String) amount.get('quantity');
                    
                    if ('lovelace'.equals(unit) && String.isNotBlank(quantity)) {
                        totalLovelace += Decimal.valueOf(quantity);
                    }
                }
            }
        }
        
        return totalLovelace;
    }
    
    private static void collectAssetTotals(List<Object> utxos, Map<String, Decimal> assetTotals) {
        for (Object utxoObj : utxos) {
            Map<String, Object> utxo = (Map<String, Object>) utxoObj;
            List<Object> amounts = (List<Object>) utxo.get('amount');
            
            if (amounts != null) {
                for (Object amountObj : amounts) {
                    Map<String, Object> amount = (Map<String, Object>) amountObj;
                    String unit = (String) amount.get('unit');
                    String quantity = (String) amount.get('quantity');
                    
                    if (!'lovelace'.equals(unit) && String.isNotBlank(unit) && String.isNotBlank(quantity)) {
                        Decimal currentTotal = assetTotals.get(unit);
                        if (currentTotal == null) {
                            currentTotal = 0;
                        }
                        currentTotal += Decimal.valueOf(quantity);
                        assetTotals.put(unit, currentTotal);
                    }
                }
            }
        }
    }
    
    private static List<Map<String, Object>> buildAssetsList(Map<String, Decimal> assetTotals) {
        List<Map<String, Object>> assetsList = new List<Map<String, Object>>();
        
        for (String unit : assetTotals.keySet()) {
            Map<String, Object> assetObj = new Map<String, Object>();
            assetObj.put('unit', unit);
            assetObj.put('quantity', String.valueOf(assetTotals.get(unit)));
            
            try {
                Map<String, Object> assetInfo = BlockfrostService.getAssetInfo(unit);
                populateAssetMetadata(assetObj, assetInfo);
            } catch (Exception e) {
                populateFallbackAssetMetadata(assetObj, unit);
            }
            
            assetsList.add(assetObj);
        }
        
        return assetsList;
    }
    
    private static void populateAssetMetadata(Map<String, Object> assetObj, Map<String, Object> assetInfo) {
        if (assetInfo == null) {
            return;
        }
        
        assetObj.put('policyId', getStringValue(assetInfo, 'policy_id', ''));
        assetObj.put('assetName', getStringValue(assetInfo, 'asset_name', ''));
        assetObj.put('fingerprint', getStringValue(assetInfo, 'fingerprint', ''));
        
        Object metadataObj = assetInfo.get('metadata');
        if (metadataObj instanceof Map<String, Object>) {
            Map<String, Object> metadata = (Map<String, Object>) metadataObj;
            
            Object decimalsObj = metadata.get('decimals');
            if (decimalsObj != null) {
                assetObj.put('decimals', Integer.valueOf(String.valueOf(decimalsObj)));
            } else {
                assetObj.put('decimals', 0);
            }
            
            String assetName = (String) assetObj.get('assetName');
            assetObj.put('ticker', getStringValue(metadata, 'ticker', assetName));
            assetObj.put('description', getStringValue(metadata, 'description', ''));
        } else {
            assetObj.put('decimals', 0);
            assetObj.put('ticker', (String) assetObj.get('assetName'));
            assetObj.put('description', '');
        }
    }
    
    private static void populateFallbackAssetMetadata(Map<String, Object> assetObj, String unit) {
        assetObj.put('policyId', unit.length() >= 56 ? unit.substring(0, 56) : '');
        assetObj.put('assetName', unit.length() > 56 ? unit.substring(56) : unit);
        assetObj.put('fingerprint', 'asset' + unit.substring(0, Math.min(8, unit.length())));
        assetObj.put('decimals', 0);
        assetObj.put('ticker', unit.length() > 56 ? unit.substring(56) : unit);
        assetObj.put('description', '');
    }
    
    private static String getStringValue(Map<String, Object> dataMap, String fieldKey, String defaultVal) {
        Object fieldValue = dataMap.get(fieldKey);
        return fieldValue != null ? String.valueOf(fieldValue) : defaultVal;
    }
} 