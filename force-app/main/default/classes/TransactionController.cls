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

    // Core wallet methods
    @AuraEnabled
    public static List<UTXOAddress> getWalletUTXOs(String walletId) {
        try {
            validateWalletId(walletId);

            List<UTXO_Address__c> utxoAddresses = [
                SELECT Id, Address__c, Index__c, Type__c, Path__c, 
                       Private_Key__c, Public_Key__c, Payment_Key_Hash__c,
                       (SELECT Id, Asset__c, Amount__c, Name__c, 
                               Decimals__c, Policy_ID__c, Fingerprint__c
                        FROM UTXO_Assets__r
                        ORDER BY Asset__c)
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
                ORDER BY Type__c, Index__c
            ];

            List<UTXOAddress> utxoAddressList = new List<UTXOAddress>();
            List<Object> allUtxos = new List<Object>();
            Integer addressesWithFunds = 0;
            
            for (UTXO_Address__c addr : utxoAddresses) {
                UTXOAddress utxoAddress = buildUTXOAddress(addr);
                
                try {
                    String utxosJson = BlockfrostService.getAddressUtxos(addr.Address__c);
                    List<Object> utxos = (List<Object>) JSON.deserializeUntyped(utxosJson);
                    Map<String, Object> balance = calculateBalanceFromUTXOs(utxos);
                    utxoAddress.balance = balance;
                    utxoAddress.utxos = utxos;
                    
                    if (utxos != null && !utxos.isEmpty()) {
                        allUtxos.addAll(utxos);
                        addressesWithFunds++;
                    }
                } catch (Exception e) {
                    utxoAddress.balance = createEmptyBalance();
                    utxoAddress.utxos = new List<Object>();
                }
                
                utxoAddressList.add(utxoAddress);
            }
            
            Map<String, Object> walletSummary = buildWalletSummary(allUtxos);
            walletSummary.put('totalAddresses', utxoAddresses.size());
            walletSummary.put('addressesWithFunds', addressesWithFunds);
            
            for (UTXOAddress utxoAddress : utxoAddressList) {
                utxoAddress.walletSummary = walletSummary;
            }
            
            return utxoAddressList;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet UTXOs: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String getOutboundTransactionCbor(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            List<Outbound_Transaction__c> transactions = [
                SELECT Id, Signed_Transaction_CBOR__c
                FROM Outbound_Transaction__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            return transactions.isEmpty() ? null : transactions[0].Signed_Transaction_CBOR__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving transaction CBOR: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> getOutboundTransactionDetails(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            List<Outbound_Transaction__c> transactions = [
                SELECT Id, Name, Wallet__c, To_Address__c, 
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
            
            Integer cborLength = 0;
            if (!String.isBlank(tx.Signed_Transaction_CBOR__c)) {
                cborLength = Integer.valueOf(tx.Signed_Transaction_CBOR__c.length() / 2);
            }
            
            return new Map<String, Object>{
                'id' => tx.Id,
                'name' => tx.Name,
                'walletId' => tx.Wallet__c,
                'toAddress' => tx.To_Address__c,
                'transactionStatus' => tx.Transaction_Status__c,
                'approved' => tx.Approved__c,
                'hasCbor' => !String.isBlank(tx.Signed_Transaction_CBOR__c),
                'cborLength' => cborLength,
                'transactionHash' => tx.Transaction_Hash__c,
                'createdDate' => tx.CreatedDate,
                'lastModifiedDate' => tx.LastModifiedDate
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving transaction details: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String createOutboundTransaction(String walletId, String toAddress, String amount) {
        try {
            validateWalletId(walletId);
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

            Outbound_Transaction__c txRecord = new Outbound_Transaction__c(
                Wallet__c = walletId,
                To_Address__c = toAddress,
                Approved__c = 'Not Approved',
                Transaction_Status__c = 'Ready to Sign'
            );

            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<Outbound_Transaction__c>{txRecord});
            insert decision.getRecords();

            return decision.getRecords()[0].Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating outbound transaction: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> getWalletData(String walletId) {
        validateWalletId(walletId);

        try {
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Id, Address__c, Index__c, Type__c, Path__c, 
                       Private_Key__c, Public_Key__c, Payment_Key_Hash__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
                ORDER BY Type__c, Index__c
            ];

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
            throw new AuraHandledException('Error retrieving wallet data: ' + e.getMessage());
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
    
    // Helper methods
    private static void validateWalletId(String walletId) {
        if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
            throw new AuraHandledException('Invalid Wallet ID');
        }
    }

    private static UTXOAddress buildUTXOAddress(UTXO_Address__c addr) {
        UTXOAddress utxoAddress = new UTXOAddress();
        utxoAddress.id = addr.Id;
        utxoAddress.address = addr.Address__c;
        utxoAddress.addressIndex = Integer.valueOf(addr.Index__c);
        utxoAddress.addressType = addr.Type__c;
        utxoAddress.path = addr.Path__c;
        utxoAddress.privateKey = addr.Private_Key__c;
        utxoAddress.publicKey = addr.Public_Key__c;
        utxoAddress.paymentKeyHash = addr.Payment_Key_Hash__c;
        utxoAddress.xprv = addr.Private_Key__c;
        utxoAddress.xpub = addr.Public_Key__c;
        
        for (UTXO_Asset__c asset : addr.UTXO_Assets__r) {
            UTXOAsset utxoAsset = new UTXOAsset();
            utxoAsset.id = asset.Id;
            utxoAsset.unit = asset.Asset__c;
            utxoAsset.amount = asset.Amount__c;
            utxoAsset.assetName = asset.Name__c;
            utxoAsset.displayName = asset.Name__c;
            utxoAsset.decimals = Integer.valueOf(asset.Decimals__c != null ? asset.Decimals__c : 0.0);
            utxoAsset.policyId = asset.Policy_ID__c;
            utxoAsset.fingerprint = asset.Fingerprint__c;
            utxoAddress.assets.add(utxoAsset);
        }
        
        return utxoAddress;
    }

    private static Map<String, Object> buildWalletSummary(List<Object> allUtxos) {
        Map<String, Object> walletSummary = new Map<String, Object>();
        Map<String, Object> totalBalance = new Map<String, Object>();
        List<Map<String, Object>> assets = new List<Map<String, Object>>();
        
        if (allUtxos == null || allUtxos.isEmpty()) {
            totalBalance.put('lovelace', '0');
            totalBalance.put('ada', '0');
            totalBalance.put('assets', assets);
            walletSummary.put('totalBalance', totalBalance);
            walletSummary.put('totalAddresses', 0);
            walletSummary.put('addressesWithFunds', 0);
            return walletSummary;
        }
        
        Decimal totalLovelace = 0;
        Set<String> uniqueUnits = new Set<String>();
        Map<String, Decimal> unitTotals = new Map<String, Decimal>();
        
        for (Object utxoObj : allUtxos) {
            Map<String, Object> utxo = (Map<String, Object>) utxoObj;
            List<Object> amounts = (List<Object>) utxo.get('amount');
            if (amounts != null) {
                for (Object assetObj : amounts) {
                    Map<String, Object> asset = (Map<String, Object>) assetObj;
                    String unit = (String) asset.get('unit');
                    String quantity = (String) asset.get('quantity');
                    
                    if (String.isNotBlank(unit) && String.isNotBlank(quantity)) {
                        Decimal amount = Decimal.valueOf(quantity);
                        
                        if (unit == 'lovelace') {
                            totalLovelace += amount;
                        } else {
                            uniqueUnits.add(unit);
                            Decimal currentTotal = unitTotals.get(unit);
                            if (currentTotal == null) {
                                currentTotal = 0;
                            }
                            currentTotal += amount;
                            unitTotals.put(unit, currentTotal);
                        }
                    }
                }
            }
        }
        
        for (String unit : uniqueUnits) {
            try {
                Map<String, Object> assetData = BlockfrostService.getAssetInfo(unit);
                Map<String, Object> asset = buildAssetInfo(unit, unitTotals.get(unit), assetData);
                assets.add(asset);
            } catch (Exception e) {
                Map<String, Object> asset = buildFallbackAssetInfo(unit, unitTotals.get(unit));
                assets.add(asset);
            }
        }
        
        totalBalance.put('lovelace', totalLovelace.toPlainString());
        totalBalance.put('ada', (totalLovelace / 1000000).setScale(6).toPlainString());
        totalBalance.put('assets', assets);
        
        walletSummary.put('totalBalance', totalBalance);
        walletSummary.put('totalAddresses', 0);
        walletSummary.put('addressesWithFunds', 0);
        
        return walletSummary;
    }

    private static Map<String, Object> buildAssetInfo(String unit, Decimal quantity, Map<String, Object> assetData) {
        Map<String, Object> asset = new Map<String, Object>();
        asset.put('unit', unit);
        asset.put('quantity', quantity);
        
        if (assetData.containsKey('asset_name')) {
            String assetName = (String) assetData.get('asset_name');
            asset.put('assetName', assetName);
            asset.put('displayName', assetName);
        }
        
        if (assetData.containsKey('policy_id')) {
            asset.put('policyId', (String) assetData.get('policy_id'));
        }
        
        if (assetData.containsKey('fingerprint')) {
            asset.put('fingerprint', (String) assetData.get('fingerprint'));
        }
        
        if (assetData.containsKey('metadata')) {
            Object metadataObj = assetData.get('metadata');
            if (metadataObj instanceof Map<String, Object>) {
                Map<String, Object> metadata = (Map<String, Object>) metadataObj;
                
                if (metadata.containsKey('decimals') && metadata.get('decimals') != null) {
                    Integer decimalsValue = Integer.valueOf(String.valueOf(metadata.get('decimals')));
                    asset.put('decimals', decimalsValue);
                }
                
                if (metadata.containsKey('ticker') && metadata.get('ticker') != null) {
                    asset.put('ticker', String.valueOf(metadata.get('ticker')));
                }
                
                if (metadata.containsKey('description') && metadata.get('description') != null) {
                    asset.put('description', String.valueOf(metadata.get('description')));
                }
            }
        }
        
        return asset;
    }

    private static Map<String, Object> buildFallbackAssetInfo(String unit, Decimal quantity) {
        Map<String, Object> asset = new Map<String, Object>();
        asset.put('unit', unit);
        asset.put('quantity', quantity);
        asset.put('assetName', 'Unknown Asset');
        asset.put('displayName', 'Unknown Asset');
        asset.put('decimals', 0);
        asset.put('policyId', unit.length() > 56 ? unit.substring(0, 56) : unit);
        asset.put('fingerprint', 'unknown');
        return asset;
    }

    private static Map<String, Object> calculateBalanceFromUTXOs(List<Object> utxos) {
        Map<String, Object> balance = new Map<String, Object>();
        List<Map<String, Object>> receivedSum = new List<Map<String, Object>>();
        List<Map<String, Object>> sentSum = new List<Map<String, Object>>();
        Integer txCount = 0;
        
        if (utxos == null || utxos.isEmpty()) {
            balance.put('received_sum', receivedSum);
            balance.put('sent_sum', sentSum);
            balance.put('tx_count', txCount);
            return balance;
        }
        
        Map<String, Decimal> assetTotals = new Map<String, Decimal>();
        Set<String> uniqueTxHashes = new Set<String>();
        
        for (Object utxoObj : utxos) {
            Map<String, Object> utxo = (Map<String, Object>) utxoObj;
            String txHash = (String) utxo.get('tx_hash');
            if (String.isNotBlank(txHash)) {
                uniqueTxHashes.add(txHash);
            }
            
            List<Object> amounts = (List<Object>) utxo.get('amount');
            if (amounts != null) {
                for (Object assetObj : amounts) {
                    Map<String, Object> asset = (Map<String, Object>) assetObj;
                    String unit = (String) asset.get('unit');
                    String quantity = (String) asset.get('quantity');
                    
                    if (String.isNotBlank(unit) && String.isNotBlank(quantity)) {
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
        
        for (String unit : assetTotals.keySet()) {
            Map<String, Object> assetBalance = new Map<String, Object>();
            assetBalance.put('unit', unit);
            assetBalance.put('quantity', assetTotals.get(unit).toPlainString());
            receivedSum.add(assetBalance);
        }
        
        balance.put('received_sum', receivedSum);
        balance.put('sent_sum', sentSum);
        balance.put('tx_count', uniqueTxHashes.size());
        
        return balance;
    }

    private static Map<String, Object> createEmptyBalance() {
        Map<String, Object> emptyBalance = new Map<String, Object>();
        emptyBalance.put('received_sum', new List<Map<String, Object>>());
        emptyBalance.put('sent_sum', new List<Map<String, Object>>());
        emptyBalance.put('tx_count', 0);
        return emptyBalance;
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