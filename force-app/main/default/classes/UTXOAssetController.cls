/**
 * UTXOAssetController - Clean controller for UTXO asset and transaction synchronization
 */
public with sharing class UTXOAssetController {
    
    // Place this at the class level, outside of any method
    private static void populateAssetFields(UTXO_Asset__c asset, String unit, Decimal totalAmount, String assetName, String displayUnit, Map<String, Object> metadata) {
        asset.Amount__c = totalAmount;
        asset.Asset__c = (unit == 'lovelace' ? 'ADA' : displayUnit);
        asset.Name__c = (unit == 'lovelace' ? 'Cardano' : assetName);
        asset.Icon__c = null;
        
        if (unit == 'lovelace') {
            asset.Decimals__c = 6;
            asset.Icon__c = null;
        } else {
            // For non-lovelace assets, try to get decimals from metadata
            if (metadata != null) {
                // Set Policy ID
                if (metadata.containsKey('policy_id') && metadata.get('policy_id') != null) {
                    asset.Policy_ID__c = String.valueOf(metadata.get('policy_id'));
                }
                // Set Fingerprint
                if (metadata.containsKey('fingerprint') && metadata.get('fingerprint') != null) {
                    asset.Fingerprint__c = String.valueOf(metadata.get('fingerprint'));
                }
                // Set Decimals from metadata
                if (metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                    Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                    if (innerMeta.containsKey('decimals') && innerMeta.get('decimals') != null) {
                        Object decimalsObj = innerMeta.get('decimals');
                        if (decimalsObj instanceof Integer) {
                            asset.Decimals__c = (Integer) decimalsObj;
                        } else if (decimalsObj instanceof Decimal) {
                            asset.Decimals__c = ((Decimal) decimalsObj).intValue();
                        } else {
                            asset.Decimals__c = Integer.valueOf(String.valueOf(decimalsObj));
                        }
                    } else {
                        // If no decimals in metadata, default to 0
                        asset.Decimals__c = 0;
                    }
                } else {
                    // If no metadata at all, default to 0
                    asset.Decimals__c = 0;
                }
                
                // Set Icon__c from logo if present at top level or in inner metadata
                if (metadata.containsKey('logo') && metadata.get('logo') != null) {
                    asset.Icon__c = String.valueOf(metadata.get('logo'));
                } else if (metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                    Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                    if (innerMeta.containsKey('logo') && innerMeta.get('logo') != null) {
                        asset.Icon__c = String.valueOf(innerMeta.get('logo'));
                    }
                }
            } else {
                // If no metadata at all, set defaults
                asset.Decimals__c = 0;
            }
        }
        
        // Fallback to default icon if not set
        if (asset.Icon__c == null) {
            asset.Icon__c = 'utility:money';
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
            Long totalStartTime = System.now().getTime();
            
            if (utxoAddressId == null) {
                throw new AuraHandledException('UTXO Address ID cannot be null');
            }
            
            // Get the UTXO Address record
            UTXO_Address__c utxoAddress = [
                SELECT Id, Address__c, Wallet__c, Is_Used__c
                FROM UTXO_Address__c
                WHERE Id = :utxoAddressId
                LIMIT 1
            ];
            
            if (utxoAddress == null) {
                throw new AuraHandledException('UTXO Address not found');
            }
            
            // PHASE 1: ALL CALLOUTS FIRST (to avoid callout-after-DML issues)
            
            // Step 1: Get UTXOs from Blockfrost (for asset calculation)
            String utxoJson = BlockfrostService.getAddressUtxos(utxoAddress.Address__c);
            List<Object> utxoList = (List<Object>) JSON.deserializeUntyped(utxoJson);

            // Step 2: Get ALL transactions from Blockfrost (for usage and inbound/outbound analysis)
            String transactionsJson = BlockfrostService.getAddressTransactionsList(utxoAddress.Address__c);
            List<Object> transactionList = (List<Object>) JSON.deserializeUntyped(transactionsJson);
            
            // Step 3: Get all wallet addresses for transaction direction analysis
            List<UTXO_Address__c> walletAddresses = [
                SELECT Id, Address__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :utxoAddress.Wallet__c
            ];
            
            List<String> walletAddressList = new List<String>();
            for (UTXO_Address__c addr : walletAddresses) {
                walletAddressList.add(addr.Address__c);
            }
            
            // Step 4: Extract transaction hashes and analyze directions
            List<String> txHashes = new List<String>();
            for (Object txObj : transactionList) {
                Map<String, Object> tx = (Map<String, Object>) txObj;
                String txHash = String.valueOf(tx.get('tx_hash'));
                if (String.isNotBlank(txHash)) {
                    txHashes.add(txHash);
                }
            }
            
            // Step 5: Use UTXO data to determine inbound transactions
            Map<String, Object> directionAnalysis = new Map<String, Object>();
            Map<String, Object> transactionDetails = new Map<String, Object>();
            
            // Create a set of transaction hashes from UTXOs (these are inbound transactions)
            Set<String> inboundTxHashes = new Set<String>();
            for (Object utxoObj : utxoList) {
                Map<String, Object> utxo = (Map<String, Object>) utxoObj;
                String utxoTxHash = String.valueOf(utxo.get('tx_hash'));
                if (String.isNotBlank(utxoTxHash)) {
                    inboundTxHashes.add(utxoTxHash);
                }
            }
            
            if (!txHashes.isEmpty()) {
                String analysisJson = BlockfrostService.analyzeMultipleTransactionDirections(txHashes, walletAddressList);
                directionAnalysis = (Map<String, Object>) JSON.deserializeUntyped(analysisJson);
                
                // Get full transaction details for each transaction
                for (String txHash : txHashes) {
                    try {
                        String txDetailJson = BlockfrostService.getTransactionDetails(txHash);
                        if (txDetailJson != null && txDetailJson != '{}') {
                            Map<String, Object> txDetail = (Map<String, Object>) JSON.deserializeUntyped(txDetailJson);
                            transactionDetails.put(txHash, txDetail);
                        }
                    } catch (Exception e) {
                        // Continue processing other transactions
                    }
                }
            }
            
            // Step 6: Process all transactions using UTXO data for direction detection
            List<Object> allTransactions = new List<Object>();
            Integer inboundCount = 0;
            Integer outboundCount = 0;
            
            for (Object txObj : transactionList) {
                Map<String, Object> tx = (Map<String, Object>) txObj;
                String txHash = String.valueOf(tx.get('tx_hash'));
                
                // Start with the basic transaction data
                Map<String, Object> enrichedTx = new Map<String, Object>(tx);
                
                // Merge with full transaction details if available
                if (transactionDetails.containsKey(txHash)) {
                    Map<String, Object> fullDetails = (Map<String, Object>) transactionDetails.get(txHash);
                    enrichedTx.putAll(fullDetails);
                }
                
                // Determine direction using UTXO data (more reliable than API analysis)
                if (inboundTxHashes.contains(txHash)) {
                    // This transaction hash appears in UTXOs, so it's inbound
                    enrichedTx.put('direction', 'incoming');
                    inboundCount++;
                } else {
                    // This transaction doesn't appear in UTXOs, so it's outbound or external
                    // Use API analysis as fallback
                    if (directionAnalysis.containsKey(txHash)) {
                        Map<String, Object> analysis = (Map<String, Object>) directionAnalysis.get(txHash);
                        
                        if (analysis.get('success') == true) {
                            if (analysis.get('isOutbound') == true) {
                                enrichedTx.put('direction', 'outgoing');
                                outboundCount++;
                            } else {
                                enrichedTx.put('direction', 'external');
                            }
                        } else {
                            // Skip transactions that can't be analyzed - don't include them in response
                            continue;
                        }
                    } else {
                        // Skip transactions without analysis - don't include them in response
                        continue;
                    }
                }
                
                allTransactions.add(enrichedTx);
            }
            
            // Step 7: Collect all unique asset units and fetch metadata
            Set<String> allUnits = new Set<String>();
            Map<String, String> unitToMetadata = new Map<String, String>();
            
            for (Object utxoObj : utxoList) {
                Map<String, Object> utxo = (Map<String, Object>) utxoObj;
                List<Object> amounts = (List<Object>) utxo.get('amount');
                if (amounts != null) {
                    for (Object amtObj : amounts) {
                        Map<String, Object> amt = (Map<String, Object>) amtObj;
                        String unit = String.valueOf(amt.get('unit'));
                        allUnits.add(unit);
                    }
                }
            }
            
            // Fetch metadata for all non-lovelace units
            for (String unit : allUnits) {
                if (unit != 'lovelace') {
                    try {
                        Map<String, Object> assetData = BlockfrostService.getAssetInfo(unit);
                        if (assetData != null && !assetData.isEmpty()) {
                            unitToMetadata.put(unit, JSON.serialize(assetData));
                        }
                    } catch (Exception e) {
                        // Continue processing other assets
                    }
                }
            }
            
            // PHASE 2: PROCESS AND SAVE DATA (all DML operations)
            
            // Process and aggregate assets
            Map<String, Decimal> unitToTotalAmount = new Map<String, Decimal>();
            
            for (Object utxoObj : utxoList) {
                Map<String, Object> utxo = (Map<String, Object>) utxoObj;
                List<Object> amounts = (List<Object>) utxo.get('amount');
                if (amounts != null) {
                    for (Object amtObj : amounts) {
                        Map<String, Object> amt = (Map<String, Object>) amtObj;
                        String unit = String.valueOf(amt.get('unit'));
                        Decimal quantity = Decimal.valueOf(String.valueOf(amt.get('quantity')));
                        
                        if (!unitToTotalAmount.containsKey(unit)) {
                            unitToTotalAmount.put(unit, 0);
                        }
                        unitToTotalAmount.put(unit, unitToTotalAmount.get(unit) + quantity);
                    }
                }
            }
            
            // Get existing assets and transactions
            List<UTXO_Asset__c> existingAssets = [
                SELECT Id, Asset__c, Amount__c, UTXO_Address__c
                FROM UTXO_Asset__c
                WHERE UTXO_Address__c = :utxoAddress.Id
            ];
            
            Map<String, Inbound_Transaction__c> existingTransactions = new Map<String, Inbound_Transaction__c>();
            for (Inbound_Transaction__c existing : [
                SELECT Id, Transaction_Hash__c, Block_Height__c, Block_Time__c
                FROM Inbound_Transaction__c
                WHERE UTXO_Address__c = :utxoAddress.Id
            ]) {
                existingTransactions.put(existing.Transaction_Hash__c, existing);
            }
            
            // Prepare asset operations - Create a comprehensive lookup map for existing assets
            // We need to handle cases where existing records might have old or new unit formats
            Map<String, UTXO_Asset__c> unitToExistingAsset = new Map<String, UTXO_Asset__c>();
            for (UTXO_Asset__c existingAsset : existingAssets) {
                unitToExistingAsset.put(existingAsset.Asset__c, existingAsset);
            }
            
            // Prepare asset operations
            List<UTXO_Asset__c> assetsToInsert = new List<UTXO_Asset__c>();
            List<UTXO_Asset__c> assetsToUpdate = new List<UTXO_Asset__c>();
            Set<String> validUnits = new Set<String>();
            Integer insertedCount = 0;
            Integer updatedCount = 0;
            for (String unit : unitToTotalAmount.keySet()) {
                Decimal totalAmount = unitToTotalAmount.get(unit);
                String displayUnit = unit;
                String assetName = unit;
                Map<String, Object> metadata = null;
                if (unit == 'lovelace') {
                    displayUnit = 'ADA';
                    assetName = 'Cardano';
                } else if (unitToMetadata.containsKey(unit)) {
                    try {
                        metadata = (Map<String, Object>) JSON.deserializeUntyped(unitToMetadata.get(unit));
                        if (metadata.containsKey('metadata')) {
                            Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                            if (innerMeta.containsKey('ticker')) {
                                displayUnit = String.valueOf(innerMeta.get('ticker'));
                                assetName = displayUnit;
                            }
                            if (innerMeta.containsKey('name')) {
                                assetName = String.valueOf(innerMeta.get('name'));
                            }
                        }
                    } catch (Exception e) {
                        // Continue processing other assets
                    }
                }
                String intendedUnit = displayUnit;
                validUnits.add(intendedUnit);
                UTXO_Asset__c existingAsset = unitToExistingAsset.get(intendedUnit);
                if (existingAsset != null) {
                    // Always update existing asset, even if nothing changed
                    populateAssetFields(existingAsset, unit, totalAmount, assetName, displayUnit, metadata);
                    assetsToUpdate.add(existingAsset);
                } else {
                    // Always insert if not found
                    UTXO_Asset__c newAsset = new UTXO_Asset__c(UTXO_Address__c = utxoAddress.Id);
                    populateAssetFields(newAsset, unit, totalAmount, assetName, displayUnit, metadata);
                    assetsToInsert.add(newAsset);
                }
            }
            if (!assetsToInsert.isEmpty()) {
                insert assetsToInsert;
                insertedCount = assetsToInsert.size();
            }
            if (!assetsToUpdate.isEmpty()) {
                update assetsToUpdate;
                updatedCount = assetsToUpdate.size();
            }
            // After all upserts, clean up any assets not in the current sync
            List<UTXO_Asset__c> assetsToDelete = [
                SELECT Id, Asset__c FROM UTXO_Asset__c
                WHERE UTXO_Address__c = :utxoAddress.Id
                AND Asset__c NOT IN :validUnits
            ];
            Integer deletedCount = 0;
            if (!assetsToDelete.isEmpty()) {
                delete assetsToDelete;
                deletedCount = assetsToDelete.size();
            }
            
            // Step 2.5: Upsert Inbound_Transaction__c records for all transactions
            Map<String, Inbound_Transaction__c> existingInbound = new Map<String, Inbound_Transaction__c>();
            for (Inbound_Transaction__c itx : [
                SELECT Id, Transaction_Hash__c, Block_Height__c, Block_Time__c, Transaction_Index__c
                FROM Inbound_Transaction__c
                WHERE UTXO_Address__c = :utxoAddress.Id
            ]) {
                existingInbound.put(itx.Transaction_Hash__c, itx);
            }

            List<Inbound_Transaction__c> toInsert = new List<Inbound_Transaction__c>();
            List<Inbound_Transaction__c> toUpdate = new List<Inbound_Transaction__c>();

            for (Object txObj : transactionList) {
                Map<String, Object> tx = (Map<String, Object>) txObj;
                String txHash = (String) tx.get('tx_hash');
                Integer blockHeight = (Integer) tx.get('block_height');
                Integer blockTime = (Integer) tx.get('block_time');
                Integer txIndex = (Integer) tx.get('tx_index');

                if (String.isNotBlank(txHash)) {
                    if (existingInbound.containsKey(txHash)) {
                        // Optionally update fields if needed
                        Inbound_Transaction__c existing = existingInbound.get(txHash);
                        Boolean changed = false;
                        if (existing.Block_Height__c != blockHeight) {
                            existing.Block_Height__c = blockHeight;
                            changed = true;
                        }
                        if (existing.Block_Time__c != blockTime) {
                            existing.Block_Time__c = blockTime;
                            changed = true;
                        }
                        if (existing.Transaction_Index__c != txIndex) {
                            existing.Transaction_Index__c = txIndex;
                            changed = true;
                        }
                        if (changed) {
                            toUpdate.add(existing);
                        }
                    } else {
                        // Insert new inbound transaction
                        toInsert.add(new Inbound_Transaction__c(
                            UTXO_Address__c = utxoAddress.Id,
                            Transaction_Hash__c = txHash,
                            Block_Height__c = blockHeight,
                            Block_Time__c = blockTime,
                            Transaction_Index__c = txIndex
                        ));
                    }
                }
            }

            if (!toInsert.isEmpty()) insert toInsert;
            if (!toUpdate.isEmpty()) update toUpdate;
            
            Long processingTime = System.now().getTime() - totalStartTime;
            
            // Set hasTransactions based on the transaction count (transactionList), not UTXOs
            Boolean hasTransactions = transactionList.size() > 0;
            utxoAddress.Is_Used__c = hasTransactions;
            try {
                upsert utxoAddress;
            } catch (Exception e) {
                throw e;
            }
            
            return new Map<String, Object>{
                'success' => true,
                'assets' => utxoList,
                'transactions' => allTransactions,
                'statistics' => new Map<String, Object>{
                    'assetsInserted' => insertedCount,
                    'assetsUpdated' => updatedCount,
                    'assetsDeleted' => deletedCount,
                    'transactionsInserted' => inboundCount + outboundCount,
                    'transactionsUpdated' => 0,
                    'transactionsDeleted' => 0,
                    'totalTransactionsFound' => allTransactions.size(),
                    'inboundTransactionsFound' => inboundCount,
                    'outboundTransactionsFound' => outboundCount,
                    'totalProcessingTimeMs' => processingTime
                },
                'message' => allTransactions.isEmpty() ? 'No transactions found - cleanup completed' : 'Assets and transactions synchronized successfully with cleanup'
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => e.getMessage(),
                'error' => e.getTypeName()
            };
        }
    }

    /**
     * Sets Is_Used__c = true for a list of UTXO_Address__c records
     * @param utxoAddressIds List of UTXO Address record IDs
     */
    @AuraEnabled
    public static void setAddressesUsed(List<Id> utxoAddressIds) {
        if (utxoAddressIds == null || utxoAddressIds.isEmpty()) return;
        List<UTXO_Address__c> addressesToUpdate = [
            SELECT Id, Is_Used__c FROM UTXO_Address__c WHERE Id IN :utxoAddressIds
        ];
        for (UTXO_Address__c addr : addressesToUpdate) {
            addr.Is_Used__c = true;
        }
        if (!addressesToUpdate.isEmpty()) {
            update addressesToUpdate;
        }
    }

    /**
     * Get asset summary for a wallet (all assets across all UTXO addresses)
     * @param walletId The wallet ID to get assets for
     * @return Map with asset summary data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getWalletAssetSummary(Id walletId) {
        try {
            if (walletId == null) {
                throw new AuraHandledException('Wallet ID cannot be null');
            }
            
            // Get all UTXO addresses for this wallet
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Id
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
            ];
            
            if (utxoAddresses.isEmpty()) {
                return new Map<String, Object>{
                    'success' => true,
                    'adaBalance' => 0,
                    'tokens' => new List<Object>(),
                    'totalAssets' => 0,
                    'message' => 'No UTXO addresses found for this wallet'
                };
            }
            
            Set<Id> utxoAddressIds = new Set<Id>();
            for (UTXO_Address__c addr : utxoAddresses) {
                utxoAddressIds.add(addr.Id);
            }
            
            // Get all assets for these addresses, aggregated by Asset
            AggregateResult[] assetAggregates = [
                SELECT Asset__c, SUM(Amount__c) totalAmount, SUM(Value__c) totalValue, 
                       MAX(Name__c) assetName, 
                       MAX(Decimals__c) decimals, MAX(Policy_ID__c) policyId,
                       MAX(Fingerprint__c) fingerprint
                FROM UTXO_Asset__c
                WHERE UTXO_Address__c IN :utxoAddressIds
                GROUP BY Asset__c
                ORDER BY Asset__c
            ];

            // Build a set of all asset units
            Set<String> assetUnits = new Set<String>();
            for (AggregateResult ar : assetAggregates) {
                assetUnits.add(String.valueOf(ar.get('Asset__c')));
            }
            // Query one UTXO_Asset__c per asset to get Icon__c
            Map<String, String> assetToIcon = new Map<String, String>();
            for (UTXO_Asset__c asset : [
                SELECT Asset__c, Icon__c FROM UTXO_Asset__c
                WHERE UTXO_Address__c IN :utxoAddressIds AND Asset__c IN :assetUnits
            ]) {
                if (asset.Icon__c != null && !assetToIcon.containsKey(asset.Asset__c)) {
                    assetToIcon.put(asset.Asset__c, asset.Icon__c);
                }
            }
            
            Decimal adaBalance = 0;
            List<Map<String, Object>> tokens = new List<Map<String, Object>>();
            
            for (AggregateResult ar : assetAggregates) {
                String unit = String.valueOf(ar.get('Asset__c'));
                Decimal totalAmount = (Decimal) ar.get('totalAmount');
                Decimal totalValue = (Decimal) ar.get('totalValue');
                String assetName = String.valueOf(ar.get('assetName'));
                Integer decimals = ar.get('decimals') != null ? Integer.valueOf(ar.get('decimals')) : 0;
                String policyId = String.valueOf(ar.get('policyId'));
                String fingerprint = String.valueOf(ar.get('fingerprint'));
                
                if (unit == 'ADA') {
                    // For ADA, use the Value__c field which converts lovelace to ADA
                    adaBalance = totalValue != null ? totalValue : 0;
                } else {
                    // For tokens, add to tokens list
                    // Use Amount__c if Value__c is 0 or null, otherwise use Value__c
                    Decimal displayAmount = (totalValue != null && totalValue > 0) ? totalValue : totalAmount;
                    
                    Map<String, Object> tokenInfo = new Map<String, Object>{
                        'unit' => unit,
                        'name' => assetName != null ? assetName : unit,
                        'symbol' => unit, // Use Asset__c field as the ticker/symbol
                        'amount' => displayAmount, // Use appropriate amount
                        'rawAmount' => totalAmount, // Keep raw amount for reference
                        'decimals' => decimals,
                        'policyId' => policyId != 'null' ? policyId : null,
                        'fingerprint' => fingerprint != 'null' ? fingerprint : null,
                        'icon' => assetToIcon.containsKey(unit) ? assetToIcon.get(unit) : 'utility:money'
                    };
                    tokens.add(tokenInfo);
                }
            }
            
            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'adaBalance' => adaBalance,
                'tokens' => tokens,
                'totalAssets' => assetAggregates.size(),
                'message' => 'Asset summary retrieved successfully'
            };
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get wallet asset summary: ' + e.getMessage());
        }
    }
    
    /**
     * Get all transactions for a wallet
     * @param walletId The wallet ID to get transactions for
     * @return Map with transaction data
     */
    @AuraEnabled
    public static Map<String, Object> fetchWalletTransactions(Id walletId) {
        try {
            if (walletId == null) {
                throw new AuraHandledException('Wallet ID cannot be null');
            }
            
            // Get Inbound Transactions
            List<Inbound_Transaction__c> inboundTxs = [
                SELECT Id, Name, Transaction_Hash__c, CreatedDate, UTXO_Address__c
                FROM Inbound_Transaction__c
                WHERE UTXO_Address__r.Wallet__c = :walletId
                ORDER BY CreatedDate DESC
            ];
            
            // Get Outbound Transactions with joined lines
            List<Outbound_Transaction__c> outboundTxs = [
                SELECT Id, Name, Transaction_Hash__c, Transaction_Status__c, Memo__c, CreatedDate,
                       (SELECT Id, Asset__c, Amount__c FROM Outbound_Transaction_Lines__r)
                FROM Outbound_Transaction__c
                WHERE Wallet__c = :walletId
                ORDER BY CreatedDate DESC
            ];
            
            // Map inbound transactions for LWC
            List<Map<String, Object>> inbound = new List<Map<String, Object>>();
            for (Inbound_Transaction__c tx : inboundTxs) {
                inbound.add(new Map<String, Object>{
                    'Id' => tx.Id,
                    'Name' => tx.Name,
                    'Transaction_Hash__c' => tx.Transaction_Hash__c,
                    'CreatedDate' => tx.CreatedDate,
                    'UTXO_Address__c' => tx.UTXO_Address__c,
                    'type' => 'inbound'
                });
            }
            
            // Map outbound transactions for LWC
            List<Map<String, Object>> outbound = new List<Map<String, Object>>();
            for (Outbound_Transaction__c tx : outboundTxs) {
                List<Map<String, Object>> lines = new List<Map<String, Object>>();
                if (tx.Outbound_Transaction_Lines__r != null) {
                    for (Outbound_Transaction_Line__c line : tx.Outbound_Transaction_Lines__r) {
                        lines.add(new Map<String, Object>{
                            'Id' => line.Id,
                            'Asset__c' => line.Asset__c,
                            'Amount__c' => line.Amount__c
                        });
                    }
                }
                outbound.add(new Map<String, Object>{
                    'Id' => tx.Id,
                    'Name' => tx.Name,
                    'Transaction_Hash__c' => tx.Transaction_Hash__c,
                    'Transaction_Status__c' => tx.Transaction_Status__c,
                    'Memo__c' => tx.Memo__c,
                    'CreatedDate' => tx.CreatedDate,
                    'type' => 'outbound',
                    'lines' => lines
                });
            }
            
            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'inbound' => inbound,
                'outbound' => outbound,
                'totalInbound' => inbound.size(),
                'totalOutbound' => outbound.size(),
                'message' => 'Transactions retrieved successfully'
            };
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get wallet transactions: ' + e.getMessage());
        }
    }
    
    /**
     * Get all UTXO assets for a wallet
     * @param walletId The wallet ID to get assets for
     * @return Map with asset data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAllUtxoAssetsForWallet(Id walletId) {
        try {
            if (walletId == null) {
                throw new AuraHandledException('Wallet ID cannot be null');
            }
            // Get all UTXO addresses for this wallet
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Id
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
            ];
            if (utxoAddresses.isEmpty()) {
                return new Map<String, Object>{
                    'success' => true,
                    'assets' => new List<Object>(),
                    'message' => 'No UTXO addresses found for this wallet'
                };
            }
            Set<Id> utxoAddressIds = new Set<Id>();
            for (UTXO_Address__c addr : utxoAddresses) {
                utxoAddressIds.add(addr.Id);
            }
            // Get all assets for these addresses
            List<UTXO_Asset__c> assets = [
                SELECT Id, Asset__c, Amount__c, Value__c, Name__c, Decimals__c, 
                       Policy_ID__c, Fingerprint__c, Icon__c, UTXO_Address__c
                FROM UTXO_Asset__c
                WHERE UTXO_Address__c IN :utxoAddressIds
                ORDER BY Asset__c
            ];
            List<Map<String, Object>> assetList = new List<Map<String, Object>>();
            for (UTXO_Asset__c asset : assets) {
                assetList.add(new Map<String, Object>{
                    'id' => asset.Id,
                    'asset' => asset.Asset__c,
                    'amount' => asset.Amount__c,
                    'value' => asset.Value__c,
                    'name' => asset.Name__c,
                    'decimals' => asset.Decimals__c,
                    'policyId' => asset.Policy_ID__c,
                    'fingerprint' => asset.Fingerprint__c,
                    'icon' => asset.Icon__c,
                    'utxoAddressId' => asset.UTXO_Address__c
                });
            }
            return new Map<String, Object>{
                'success' => true,
                'assets' => assetList,
                'message' => 'Assets retrieved successfully'
            };
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get wallet assets: ' + e.getMessage());
        }
    }
} 