/**
 * UTXOAssetController - Clean controller for UTXO asset and transaction synchronization
 */
public with sharing class UTXOAssetController {
    
    // Place this at the class level, outside of any method
    private static void populateAssetFields(UTXO_Asset__c asset, String unit, Decimal totalAmount, String assetName, String displayUnit, Map<String, Object> metadata) {
        asset.Amount__c = totalAmount;
        asset.Unit__c = (unit == 'lovelace' ? 'ADA' : displayUnit);
        asset.Name__c = (unit == 'lovelace' ? 'Cardano' : assetName);
        asset.Asset_Name__c = displayUnit;
        if (unit == 'lovelace') {
            asset.Decimals__c = 6;
        } else if (metadata != null) {
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
                }
            }
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
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 🚀 Starting combined sync for address ID: ' + utxoAddressId);
            Long totalStartTime = System.now().getTime();
            
            if (utxoAddressId == null) {
                throw new AuraHandledException('UTXO Address ID cannot be null');
            }
            
            // Get the UTXO Address record
            UTXO_Address__c utxoAddress = [
                SELECT Id, Address__c, Wallet__c
                FROM UTXO_Address__c
                WHERE Id = :utxoAddressId
                LIMIT 1
            ];
            
            if (utxoAddress == null) {
                throw new AuraHandledException('UTXO Address not found');
            }
            
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📍 Processing address: ' + utxoAddress.Address__c);
            
            // PHASE 1: ALL CALLOUTS FIRST (to avoid callout-after-DML issues)
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📡 Phase 1: Making all API callouts');
            
            // Step 1: Get UTXOs from Blockfrost
            String utxoJson = BlockfrostService.getAddressUtxos(utxoAddress.Address__c);
            List<Object> utxoList = (List<Object>) JSON.deserializeUntyped(utxoJson);
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📦 Found ' + utxoList.size() + ' UTXOs');
            
            // Step 2: Get transactions from Blockfrost
            String transactionsJson = BlockfrostService.getAddressTransactions(utxoAddress.Address__c);
            List<Object> transactionList = (List<Object>) JSON.deserializeUntyped(transactionsJson);
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📊 Found ' + transactionList.size() + ' transactions');
            
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
            
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 🔍 Analyzing transaction directions for ' + walletAddressList.size() + ' wallet addresses');
            
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
                    Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ✅ Found inbound transaction from UTXO: ' + utxoTxHash);
                }
            }
            
            if (!txHashes.isEmpty()) {
                Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 🔍 Analyzing ' + txHashes.size() + ' transactions for direction');
                String analysisJson = BlockfrostService.analyzeMultipleTransactionDirections(txHashes, walletAddressList);
                directionAnalysis = (Map<String, Object>) JSON.deserializeUntyped(analysisJson);
                Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📊 Direction analysis completed, found ' + directionAnalysis.size() + ' results');
                
                // Get full transaction details for each transaction
                Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 🔍 Fetching full transaction details for ' + txHashes.size() + ' transactions');
                for (String txHash : txHashes) {
                    try {
                        String txDetailJson = BlockfrostService.getTransactionDetails(txHash);
                        if (txDetailJson != null && txDetailJson != '{}') {
                            Map<String, Object> txDetail = (Map<String, Object>) JSON.deserializeUntyped(txDetailJson);
                            transactionDetails.put(txHash, txDetail);
                            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ✅ Fetched details for transaction: ' + txHash);
                        } else {
                            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ⚠️ No details available for transaction: ' + txHash);
                        }
                    } catch (Exception e) {
                        Logger.logError('[UTXOAssetController.syncAssetsAndTransactions] ❌ Failed to fetch details for transaction: ' + txHash + ' - ' + e.getMessage());
                    }
                }
                
                // Debug: Log the analysis results
                for (String txHash : directionAnalysis.keySet()) {
                    Map<String, Object> analysis = (Map<String, Object>) directionAnalysis.get(txHash);
                    Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 🔍 Analysis for ' + txHash + ': ' + JSON.serialize(analysis));
                }
            } else {
                Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ⚠️ No transaction hashes to analyze');
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
                    Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ✅ Merged full details for transaction: ' + txHash);
                }
                
                // Determine direction using UTXO data (more reliable than API analysis)
                if (inboundTxHashes.contains(txHash)) {
                    // This transaction hash appears in UTXOs, so it's inbound
                    enrichedTx.put('direction', 'incoming');
                    inboundCount++;
                    Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ✅ Inbound transaction confirmed from UTXO: ' + txHash);
                } else {
                    // This transaction doesn't appear in UTXOs, so it's outbound or external
                    // Use API analysis as fallback
                    if (directionAnalysis.containsKey(txHash)) {
                        Map<String, Object> analysis = (Map<String, Object>) directionAnalysis.get(txHash);
                        
                        if (analysis.get('success') == true) {
                            if (analysis.get('isOutbound') == true) {
                                enrichedTx.put('direction', 'outgoing');
                                outboundCount++;
                                Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ⏭️ Outbound transaction from API analysis: ' + txHash);
                            } else {
                                enrichedTx.put('direction', 'external');
                                Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ⚠️ External transaction from API analysis: ' + txHash);
                            }
                        } else {
                            // Skip transactions that can't be analyzed - don't include them in response
                            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ⚠️ Skipping transaction with failed analysis: ' + txHash);
                            continue;
                        }
                    } else {
                        // Skip transactions without analysis - don't include them in response
                        Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ⚠️ Skipping transaction without analysis: ' + txHash);
                        continue;
                    }
                }
                
                allTransactions.add(enrichedTx);
            }
            
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📊 Transaction analysis complete - Total: ' + allTransactions.size() + ', Inbound: ' + inboundCount + ', Outbound: ' + outboundCount);
            
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
                        String metadata = BlockfrostService.getAssetMetadata(unit);
                        if (metadata != null && metadata != '{}') {
                            unitToMetadata.put(unit, metadata);
                        }
                    } catch (Exception e) {
                        Logger.logError('[UTXOAssetController.syncAssetsAndTransactions] ❌ Failed to fetch metadata for unit: ' + unit + ' - ' + e.getMessage());
                    }
                }
            }
            
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ✅ Phase 1 complete - All callouts finished');
            
            // PHASE 2: PROCESS AND SAVE DATA (all DML operations)
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 💾 Phase 2: Processing and saving data');
            
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
                SELECT Id, Unit__c, Amount__c, UTXO_Address__c
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
                unitToExistingAsset.put(existingAsset.Unit__c, existingAsset);
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
                        Logger.logError('[UTXOAssetController.syncAssets] ❌ Error parsing metadata for display unit: ' + unit);
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
                SELECT Id, Unit__c FROM UTXO_Asset__c
                WHERE UTXO_Address__c = :utxoAddress.Id
                AND Unit__c NOT IN :validUnits
            ];
            Integer deletedCount = 0;
            if (!assetsToDelete.isEmpty()) {
                delete assetsToDelete;
                deletedCount = assetsToDelete.size();
                Logger.logInfo('[UTXOAssetController.syncAssets] ✅ Deleted ' + deletedCount + ' stale assets');
            }
            Logger.logInfo('[UTXOAssetController.syncAssets] 🧹 Cleanup phase completed');
            Long processingTime = System.now().getTime() - totalStartTime;
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ✅ Combined sync completed in ' + processingTime + 'ms');
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📊 Assets - Inserted: ' + insertedCount + ', Updated: ' + updatedCount + ', Deleted: ' + deletedCount);
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📊 Transactions - Inbound: ' + inboundCount + ', Outbound: ' + outboundCount);
            
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
            Logger.logError('[UTXOAssetController.syncAssetsAndTransactions] ❌ Error: ' + e.getMessage());
            return new Map<String, Object>{
                'success' => false,
                'message' => e.getMessage(),
                'error' => e.getTypeName()
            };
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
            Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] 🚀 Getting asset summary for wallet: ' + walletId);
            
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
            
            // Get all assets for these addresses, aggregated by Unit
            AggregateResult[] assetAggregates = [
                SELECT Unit__c, SUM(Amount__c) totalAmount, SUM(Value__c) totalValue, 
                       MAX(Name__c) assetName, MAX(Asset_Name__c) displayName, 
                       MAX(Decimals__c) decimals, MAX(Policy_ID__c) policyId,
                       MAX(Fingerprint__c) fingerprint
                FROM UTXO_Asset__c
                WHERE UTXO_Address__c IN :utxoAddressIds
                AND Amount__c > 0
                GROUP BY Unit__c
                ORDER BY Unit__c
            ];
            
            Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] 📊 Found ' + assetAggregates.size() + ' aggregated assets');
            
            Decimal adaBalance = 0;
            List<Map<String, Object>> tokens = new List<Map<String, Object>>();
            
            for (AggregateResult ar : assetAggregates) {
                String unit = String.valueOf(ar.get('Unit__c'));
                Decimal totalAmount = (Decimal) ar.get('totalAmount');
                Decimal totalValue = (Decimal) ar.get('totalValue');
                String assetName = String.valueOf(ar.get('assetName'));
                String displayName = String.valueOf(ar.get('displayName'));
                Integer decimals = ar.get('decimals') != null ? Integer.valueOf(ar.get('decimals')) : 0;
                String policyId = String.valueOf(ar.get('policyId'));
                String fingerprint = String.valueOf(ar.get('fingerprint'));
                
                if (unit == 'ADA') {
                    // For ADA, use the Value__c field which converts lovelace to ADA
                    adaBalance = totalValue != null ? totalValue : 0;
                    Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] 💰 ADA Balance: ' + adaBalance + ' (from ' + totalAmount + ' lovelace)');
                } else {
                    // For tokens, add to tokens list
                    Map<String, Object> tokenInfo = new Map<String, Object>{
                        'unit' => unit,
                        'name' => assetName != null ? assetName : unit,
                        'symbol' => displayName != null ? displayName : unit,
                        'amount' => totalValue != null ? totalValue : totalAmount, // Use Value__c for formatted amount
                        'rawAmount' => totalAmount, // Keep raw amount for reference
                        'decimals' => decimals,
                        'policyId' => policyId != 'null' ? policyId : null,
                        'fingerprint' => fingerprint != 'null' ? fingerprint : null,
                        'icon' => 'utility:apps' // Default icon
                    };
                    tokens.add(tokenInfo);
                    
                    Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] 🪙 Token: ' + unit + 
                                 ' - Amount: ' + totalValue + ' (from ' + totalAmount + ' raw)');
                }
            }
            
            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'adaBalance' => adaBalance,
                'tokens' => tokens,
                'totalAssets' => assetAggregates.size(),
                'message' => 'Asset summary retrieved successfully'
            };
            
            Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] ✅ Summary complete - ADA: ' + adaBalance + ', Tokens: ' + tokens.size());
            return result;
            
        } catch (Exception e) {
            Logger.logError('[UTXOAssetController.getWalletAssetSummary] ❌ Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to get wallet asset summary: ' + e.getMessage());
        }
    }
} 