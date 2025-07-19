/**
 * Controller for wallet-related operations
 * Provides methods for asset management, transaction handling, and wallet operations
 */
public with sharing class WalletController {    
    // Error messages
    private static final String ERROR_WALLET_ID_NULL = 'Wallet ID cannot be null';
    private static final String ERROR_TO_ADDRESS_REQUIRED = 'To Address is required';
    private static final String ERROR_ASSETS_REQUIRED = 'At least one asset is required';
    private static final String ERROR_AMOUNT_REQUIRED = 'Amount is required';
    private static final String ERROR_ASSET_REQUIRED = 'Asset is required';
    private static final String ERROR_INVALID_AMOUNT = 'Invalid amount format';
    private static final String ERROR_AMOUNT_MUST_BE_POSITIVE = 'Amount must be greater than 0';
    
    private static final String FIELD_ASSET_API_NAME = Schema.SObjectType.UTXO_Asset__c.fields.Asset__c.getName();
    
    /**
     * Get asset summary for a wallet (all assets across all UTXO addresses)
     * @param walletId The wallet ID to get assets for
     * @return Map with asset summary data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getWalletAssetSummary(Id walletId) {
        validateWalletId(walletId);
            
        List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getAddressesByWalletId(walletId);
            
        if (utxoAddresses.isEmpty()) {
            return createEmptyAssetSummary();
        }
            
        Set<Id> utxoAddressIds = extractAddressIds(utxoAddresses);
        AggregateResult[] assetAggregates = UTXOAssetSelector.getAssetAggregatesByUtxoAddressIds(utxoAddressIds);
            
        return buildAssetSummary(assetAggregates, utxoAddressIds);
    }
    
    /**
     * Get all transactions for a wallet
     * @param walletId The wallet ID to get transactions for
     * @return Map with transaction data
     */
    @AuraEnabled
    public static Map<String, Object> fetchWalletTransactions(Id walletId) {
        try {
            validateWalletId(walletId);
            
            List<Inbound_Transaction__c> inboundTxs = InboundTransactionSelector.getInboundTransactionsByWalletId(walletId);
            List<Outbound_Transaction__c> outboundTxs = OutboundTransactionSelector.getOutboundTransactionsByWalletId(walletId);
            
            List<Map<String, Object>> inbound = mapInboundTransactions(inboundTxs);
            List<Map<String, Object>> outbound = mapOutboundTransactions(outboundTxs);
            
            return createTransactionResult(inbound, outbound);
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get wallet transactions: ' + e.getMessage());
        }
    }
    
    /**
     * Synchronizes both assets and transactions for a UTXO address
     * @param utxoAddressId The UTXO Address ID to sync
     * @return Map with combined results
     */
    @AuraEnabled
    public static Map<String, Object> syncAssetsAndTransactions(Id utxoAddressId) {
        try {
            return UTXOHelper.syncAssetsAndTransactions(utxoAddressId);
        } catch (Exception e) {
            throw new AuraHandledException('Error syncing assets and transactions: ' + e.getMessage());
        }
    }
    
    /**
     * Get all UTXO addresses for a wallet
     * @param walletId The wallet ID to get addresses for
     * @return List of UTXO addresses
     */
    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getAllWalletAddresses(String walletId) {
        try {            
            return UTXOAddressSelector.getAddressesByWalletId(walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet addresses: ' + e.getMessage());
        }
    }
    
    /**
     * Get the first unused receiving address for a wallet
     * @param walletId The wallet ID to get address for
     * @return The first unused receiving address or null if none found
     */
    @AuraEnabled(cacheable=true)
    public static String getFirstUnusedReceivingAddress(String walletId) {
        try {
            List<UTXO_Address__c> addrs = UTXOAddressSelector.getFirstUnusedAddressByType(walletId, '0');
            return addrs.isEmpty() ? null : addrs[0].Address__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching unused receiving address: ' + e.getMessage());
        }
    }
    
    /**
     * Create a multi-asset outbound transaction
     * @param walletId The wallet ID
     * @param toAddress The recipient address
     * @param assets List of assets with amounts
     * @param memo Optional memo
     * @return The outbound transaction ID
     */
    @AuraEnabled
    public static String createMultiAssetOutboundTransaction(String walletId, String toAddress, List<Map<String, Object>> assets, String memo) {
        try {
            validateOutboundTransactionInput(toAddress, assets);
            
            Outbound_Transaction__c txRecord = createOutboundTransactionRecord(walletId, toAddress, memo);
            Id outboundId = insertTransactionRecord(txRecord);
            
            List<Outbound_Transaction_Line__c> lines = createTransactionLines(assets, outboundId);
            insertTransactionLines(lines);
            
            return outboundId;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating multi-asset outbound transaction: ' + e.getMessage());
        }
    }
    
    /**
     * Create a single asset outbound transaction
     * @param walletId The wallet ID
     * @param toAddress The recipient address
     * @param amount The amount to send
     * @param asset The asset to send
     * @param memo Optional memo
     * @return The outbound transaction ID
     */
    @AuraEnabled
    public static String createOutboundTransaction(String walletId, String toAddress, String amount, String asset, String memo) {
        try {
            validateSingleAssetOutboundTransactionInput(toAddress, amount, asset);
            
            Decimal amountDecimal = parseAmount(amount);
            
            Outbound_Transaction__c txRecord = createOutboundTransactionRecord(walletId, toAddress, memo);
            Id outboundId = insertTransactionRecord(txRecord);
            
            Outbound_Transaction_Line__c line = createSingleTransactionLine(outboundId, amountDecimal, asset);
            insertTransactionLines(new List<Outbound_Transaction_Line__c>{line});
            
            return outboundId;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating outbound transaction: ' + e.getMessage());
        }
    }
    
    // =============================================================================
    // PRIVATE HELPER METHODS
    // =============================================================================
    
    /**
     * Validate wallet ID is not null
     */
    private static void validateWalletId(Id walletId) {
        if (walletId == null) {
            throw new AuraHandledException(ERROR_WALLET_ID_NULL);
        }
    }
    
    /**
     * Validate outbound transaction input parameters
     */
    private static void validateOutboundTransactionInput(String toAddress, List<Map<String, Object>> assets) {
        if (String.isBlank(toAddress)) {
            throw new AuraHandledException(ERROR_TO_ADDRESS_REQUIRED);
        }
        if (assets == null || assets.isEmpty()) {
            throw new AuraHandledException(ERROR_ASSETS_REQUIRED);
        }
    }
    
    /**
     * Validate single asset outbound transaction input parameters
     */
    private static void validateSingleAssetOutboundTransactionInput(String toAddress, String amount, String asset) {
        if (String.isBlank(toAddress)) {
            throw new AuraHandledException(ERROR_TO_ADDRESS_REQUIRED);
        }
        if (String.isBlank(amount)) {
            throw new AuraHandledException(ERROR_AMOUNT_REQUIRED);
        }
        if (String.isBlank(asset)) {
            throw new AuraHandledException(ERROR_ASSET_REQUIRED);
        }
    }
    
    /**
     * Parse and validate amount
     */
    private static Decimal parseAmount(String amount) {
        try {
            Decimal amountDecimal = Decimal.valueOf(amount);
            if (amountDecimal <= 0) {
                throw new AuraHandledException(ERROR_AMOUNT_MUST_BE_POSITIVE);
            }
            return amountDecimal;
        } catch (Exception e) {
            throw new AuraHandledException(ERROR_INVALID_AMOUNT);
        }
    }
    
    /**
     * Create empty asset summary response
     */
    private static Map<String, Object> createEmptyAssetSummary() {
        return new Map<String, Object>{
            'success' => true,
            'adaBalance' => 0,
            'tokens' => new List<Object>(),
            'totalAssets' => 0,
            'message' => 'No UTXO addresses found for this wallet'
        };
    }
    
    /**
     * Extract address IDs from UTXO addresses
     */
    private static Set<Id> extractAddressIds(List<UTXO_Address__c> utxoAddresses) {
        Set<Id> utxoAddressIds = new Set<Id>();
        for (UTXO_Address__c addr : utxoAddresses) {
            utxoAddressIds.add(addr.Id);
        }
        return utxoAddressIds;
    }
    
    /**
     * Build asset summary from aggregates
     */
    private static Map<String, Object> buildAssetSummary(AggregateResult[] assetAggregates, Set<Id> utxoAddressIds) {
        try {
            Set<String> assetUnits = extractAssetUnits(assetAggregates);
            Map<String, String> assetToIcon = buildAssetIconMap(utxoAddressIds, assetUnits);
            
            Decimal adaBalance = 0;
            List<Map<String, Object>> tokens = new List<Map<String, Object>>();
            
            for (AggregateResult ar : assetAggregates) {
                if (ar == null) continue;
                
                String unit = String.valueOf(getAggField(ar, FIELD_ASSET_API_NAME));
                if (String.isBlank(unit)) continue;
                
                Decimal totalAmount = (Decimal) ar.get('totalAmount');
                Decimal totalValue = (Decimal) ar.get('totalValue');
                Object assetNameObj = getAggField(ar, 'assetName');
                String assetName = assetNameObj != null ? String.valueOf(assetNameObj) : unit;
                Integer decimals = ar.get('decimals') != null ? Integer.valueOf(ar.get('decimals')) : 0;
                Object policyIdObj = getAggField(ar, 'policyId');
                String policyId = policyIdObj != null ? String.valueOf(policyIdObj) : null;
                Object fingerprintObj = getAggField(ar, 'fingerprint');
                String fingerprint = fingerprintObj != null ? String.valueOf(fingerprintObj) : null;
                
                if (unit == ConstantsAda.ASSET_ADA) {
                    adaBalance = totalValue != null ? totalValue : 0;
                } else {
                    tokens.add(createTokenInfo(ar, assetToIcon));
                }
            }
            
            return new Map<String, Object>{
                'success' => true,
                'adaBalance' => adaBalance,
                'tokens' => tokens,
                'totalAssets' => assetAggregates.size(),
                'message' => 'Asset summary retrieved successfully'
            };
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'adaBalance' => 0,
                'tokens' => new List<Object>(),
                'totalAssets' => 0,
                'message' => 'Error building asset summary: ' + e.getMessage()
            };
        }
    }
    
    /**
     * Extract asset units from aggregates
     */
    private static Set<String> extractAssetUnits(AggregateResult[] assetAggregates) {
        Set<String> assetUnits = new Set<String>();
        for (AggregateResult ar : assetAggregates) {
            Object val = getAggField(ar, FIELD_ASSET_API_NAME);
            if (val != null) {
                assetUnits.add(String.valueOf(val));
            }
        }
        return assetUnits;
    }
    
    /**
     * Build asset to icon mapping
     */
    private static Map<String, String> buildAssetIconMap(Set<Id> utxoAddressIds, Set<String> assetUnits) {
        Map<String, String> assetToIcon = new Map<String, String>();
        List<UTXO_Asset__c> allAssetsWithIcons = UTXOAssetSelector.getAllAssetsByUtxoAddressIds(utxoAddressIds);
        
        for (UTXO_Asset__c asset : allAssetsWithIcons) {
            if (assetUnits.contains(asset.Asset__c) && asset.Icon__c != null && !assetToIcon.containsKey(asset.Asset__c)) {
                assetToIcon.put(asset.Asset__c, asset.Icon__c);
            }
        }
        return assetToIcon;
    }
    
    /**
     * Create token info map
     */
    private static Map<String, Object> createTokenInfo(AggregateResult ar, Map<String, String> assetToIcon) {
        String unit = String.valueOf(getAggField(ar, FIELD_ASSET_API_NAME));
        Decimal totalAmount = (Decimal) ar.get('totalAmount');
        Decimal totalValue = (Decimal) ar.get('totalValue');
        Object assetNameObj = getAggField(ar, 'assetName');
        String assetName = assetNameObj != null ? String.valueOf(assetNameObj) : unit;
        Integer decimals = ar.get('decimals') != null ? Integer.valueOf(ar.get('decimals')) : 0;
        Object policyIdObj = getAggField(ar, 'policyId');
        String policyId = policyIdObj != null ? String.valueOf(policyIdObj) : null;
        Object fingerprintObj = getAggField(ar, 'fingerprint');
        String fingerprint = fingerprintObj != null ? String.valueOf(fingerprintObj) : null;
        
        Decimal displayAmount = (totalValue != null && totalValue > 0) ? totalValue : totalAmount;
        
        return new Map<String, Object>{
            'unit' => unit,
            'name' => assetName != null ? assetName : unit,
            'symbol' => unit,
            'amount' => displayAmount,
            'rawAmount' => totalAmount,
            'decimals' => decimals,
            'policyId' => policyId != 'null' ? policyId : null,
            'fingerprint' => fingerprint != 'null' ? fingerprint : null,
                            'icon' => assetToIcon.containsKey(unit) ? assetToIcon.get(unit) : ConstantsAda.DEFAULT_ASSET_ICON
        };
    }
    
    /**
     * Map inbound transactions for LWC
     */
    private static List<Map<String, Object>> mapInboundTransactions(List<Inbound_Transaction__c> inboundTxs) {
        List<Map<String, Object>> inbound = new List<Map<String, Object>>();
        for (Inbound_Transaction__c tx : inboundTxs) {
            inbound.add(new Map<String, Object>{
                'Id' => tx.Id,
                'Name' => tx.Name,
                'Transaction_Hash__c' => tx.Transaction_Hash__c,
                'CreatedDate' => tx.CreatedDate,
                'UTXO_Address__c' => tx.UTXO_Address__c,
                'type' => ConstantsAda.TRANSACTION_TYPE_INBOUND
            });
        }
        return inbound;
    }
    
    /**
     * Map outbound transactions for LWC
     */
    private static List<Map<String, Object>> mapOutboundTransactions(List<Outbound_Transaction__c> outboundTxs) {
        List<Map<String, Object>> outbound = new List<Map<String, Object>>();
        for (Outbound_Transaction__c tx : outboundTxs) {
            List<Map<String, Object>> lines = mapTransactionLines(tx.Outbound_Transaction_Lines__r);
            outbound.add(new Map<String, Object>{
                'Id' => tx.Id,
                'Name' => tx.Name,
                'Transaction_Hash__c' => tx.Transaction_Hash__c,
                'Transaction_Status__c' => tx.Transaction_Status__c,
                'Memo__c' => tx.Memo__c,
                'CreatedDate' => tx.CreatedDate,
                'type' => ConstantsAda.TRANSACTION_TYPE_OUTBOUND,
                'lines' => lines
            });
        }
        return outbound;
    }
    
    /**
     * Map transaction lines
     */
    private static List<Map<String, Object>> mapTransactionLines(List<Outbound_Transaction_Line__c> lines) {
        List<Map<String, Object>> mappedLines = new List<Map<String, Object>>();
        if (lines != null) {
            for (Outbound_Transaction_Line__c line : lines) {
                mappedLines.add(new Map<String, Object>{
                    'Id' => line.Id,
                    'Asset__c' => line.Asset__c,
                    'Amount__c' => line.Amount__c
                });
            }
        }
        return mappedLines;
    }
    
    /**
     * Create transaction result
     */
    private static Map<String, Object> createTransactionResult(List<Map<String, Object>> inbound, List<Map<String, Object>> outbound) {
        return new Map<String, Object>{
            'success' => true,
            'inbound' => inbound,
            'outbound' => outbound,
            'totalInbound' => inbound.size(),
            'totalOutbound' => outbound.size(),
            'message' => 'Transactions retrieved successfully'
        };
    }
    
    /**
     * Create outbound transaction record
     */
    private static Outbound_Transaction__c createOutboundTransactionRecord(String walletId, String toAddress, String memo) {
        return new Outbound_Transaction__c(
            Wallet__c = walletId,
            To_Address__c = toAddress,
                            Approved__c = ConstantsAda.STATUS_NOT_APPROVED,
                Transaction_Status__c = ConstantsAda.STATUS_READY_TO_SIGN,
            Memo__c = String.isBlank(memo) ? null : memo
        );
    }
    
    /**
     * Insert transaction record with security
     */
    private static Id insertTransactionRecord(Outbound_Transaction__c txRecord) {
        if (!Schema.sObjectType.Outbound_Transaction__c.isCreateable() ||
            !Schema.sObjectType.Outbound_Transaction__c.fields.Wallet__c.isCreateable() ||
            !Schema.sObjectType.Outbound_Transaction__c.fields.To_Address__c.isCreateable() ||
            !Schema.sObjectType.Outbound_Transaction__c.fields.Approved__c.isCreateable() ||
            !Schema.sObjectType.Outbound_Transaction__c.fields.Transaction_Status__c.isCreateable() ||
            !Schema.sObjectType.Outbound_Transaction__c.fields.Memo__c.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create outbound transaction');
        }
        
        insert txRecord;
        return txRecord.Id;
    }
    
    /**
     * Create transaction lines from assets
     */
    private static List<Outbound_Transaction_Line__c> createTransactionLines(List<Map<String, Object>> assets, Id outboundId) {
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
        
        return lines;
    }
    
    /**
     * Create single transaction line
     */
    private static Outbound_Transaction_Line__c createSingleTransactionLine(Id outboundId, Decimal amount, String asset) {
        return new Outbound_Transaction_Line__c(
            Outbound_Transaction__c = outboundId,
            Amount__c = amount,
            Asset__c = asset
        );
    }
    
    /**
     * Insert transaction lines with security
     */
    private static void insertTransactionLines(List<Outbound_Transaction_Line__c> lines) {
        if (!lines.isEmpty()) {
            if (!Schema.sObjectType.Outbound_Transaction_Line__c.isCreateable() ||
                !Schema.sObjectType.Outbound_Transaction_Line__c.fields.Outbound_Transaction__c.isCreateable() ||
                !Schema.sObjectType.Outbound_Transaction_Line__c.fields.Amount__c.isCreateable() ||
                !Schema.sObjectType.Outbound_Transaction_Line__c.fields.Asset__c.isCreateable()) {
                throw new AuraHandledException('Insufficient permissions to create transaction lines');
            }
            
            insert lines;
        }
    }

    /**
     * Helper to get namespace prefix for this package
     */
    private static String getNamespacePrefix() {
        // The describe name includes namespace if present (e.g. ns__UTXO_Asset__c)
        String qualifiedName = UTXO_Asset__c.SObjectType.getDescribe().getName();
        Integer idx = qualifiedName.indexOf('__');
        if (idx > 0) {
            return qualifiedName.substring(0, idx);
        }
        return '';
    }

    /**
     * Retrieve a value from AggregateResult, aware of potential namespace prefixes.
     */
    private static Object getAggField(AggregateResult ar, String fieldApiName) {
        Map<String, Object> values = (Map<String, Object>) ar.getPopulatedFieldsAsMap();
        if (values.containsKey(fieldApiName)) {
            return values.get(fieldApiName);
        }
        String ns = getNamespacePrefix();
        if (!String.isBlank(ns)) {
            String namespacedField = ns + '__' + fieldApiName;
            if (values.containsKey(namespacedField)) {
                return values.get(namespacedField);
            }
        }
        return null;
    }
} 